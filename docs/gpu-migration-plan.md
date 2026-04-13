# GPU migration plan — Framer Effects bucket

Status as of 2026-04-13. Session handoff document for resuming on Claude Cloud.

## Status snapshot (post Phase 1 + Phase 2 land)

| Effect       | CPU path                              | GPU renderer                                    | Wired |
|--------------|---------------------------------------|-------------------------------------------------|-------|
| ASCII        | `ShaderASCIIRenderer.apply`           | `TextCellRenderer.renderASCII`                  | ✅ + fallback |
| Crimewave    | `ShaderRenderer.applyCrimewave`       | `ColorGradeRenderer.renderCrimewave` (variant 0)| ✅ + fallback |
| Narc         | `ShaderRenderer.applyNarc`            | `ColorGradeRenderer.renderNarc` (variant 1)     | ✅ + fallback |
| Shiba        | `ShaderRenderer.applyShiba`           | `ColorGradeRenderer.renderShiba` (variant 2)    | ✅ + fallback |
| DistantPast  | `ShaderRenderer.applyDistantPast`     | `DistantPastRenderer.render`                    | ✅ + fallback |
| CRT          | `ShaderRenderer.applyCRT`             | `CRTRenderer.render`                            | ✅ + fallback |
| Halftone     | `ShaderRenderer.applyHalftone`        | `HalftoneRenderer.render`                       | ✅ + fallback |
| Kuwahara     | `ShaderRenderer.applyKuwahara`        | `KuwaharaRenderer.render`                       | ✅ + fallback |
| PixelSort    | `ShaderPixelSortRenderer.apply`       | `PixelSortRenderer.render`                      | ✅ + fallback (CPU stays as export-quality path) |
| Dither       | `DitherRenderer.applyCPU` (renamed)   | `DitherGPURenderer.apply`                       | ✅ + fallback (GPU uses blue-noise approximation; Riemersma is CPU-only) |

`ShaderRenderer.gpuOrCPU(image:gpu:cpu:)` runs each GPU path with a CPU
fallback; only `MetalEffectError` triggers fallback so genuine bugs surface.

`Tests/FramerCoreTests/EffectGPUParityTests.swift` ships per-effect CPU vs GPU
delta checks. They self-skip when Metal is unavailable so they no-op on the
Linux container that authored them.

## PixelSort port notes

Implemented as `PixelSort.metal::pixelSortFragment` + `PixelSortRenderer`,
using the fragment-per-pixel design from `grainrad/notes/pixel-sort.md`. Each
fragment walks back/forward along the sort axis to find its enclosing span
(stopping at thresholds, image edges, or the configured span cap), samples up
to 24 evenly-spaced positions across the span into thread-local arrays,
bubble-sorts them by luminance, and returns the colour at this fragment's
proportional rank.

Semantics match `ShaderPixelSortRenderer.apply` exactly for the existing
parameter surface:
  - Span criterion: `luminance ≥ threshold` (continues a run).
  - Sort criterion: luminance ascending.
  - Direction: horizontal / vertical (no diagonal in this pass).
  - Span cap: 1..256, identical to CPU clamp.

**Approximation**: spans longer than `SAMPLE_COUNT = 24` are sub-sampled. For
Framer's default `span = 24` every pixel in every span is read by both CPU
and GPU — the parity test (`testPixelSortParityDefaultSpan`) validates this.
For deliberate long-streak settings (span 32+), the GPU output is visibly
coarser; the CPU path remains the export-quality fallback (and the
Metal-unavailable fallback) via `gpuOrCPU(...)` in ShaderRenderer.

**Deferred to a follow-up**:
  - Kim Asendorf's four span-detection modes (Black / White / Bright / Dark)
  - Diagonal direction (`dir = normalize(1, 1)` along anti-diagonals)
  - Per-line randomness (hash-based threshold jitter)
  - Reverse sort (descending)

Adding any of those requires extending `PixelSortShaderParams` and the YAML
config / preset format; out of scope for the GPU port pass to keep
backwards-compatibility risk low.

## Dither port notes

Implemented as `Dither.metal::ditherFragment` + `DitherGPURenderer`. Routes
through the renamed `DitherRenderer.apply` (was the CPU implementation, now
GPU-first with CPU fallback). The legacy CPU body lives at
`DitherRenderer.applyCPU` — same signature, called by tests directly and by
the GPU-fallback path.

GPU implementation strategy follows Grainrad's design from
`grainrad/notes/dithering.md`: error-diffusion algorithms (Floyd-Steinberg,
Atkinson, Stucki, Artistic Drip) are *approximated* by an Interleaved
Gradient Noise threshold with per-algorithm scaling coefficient. True
serial error diffusion can't run as a single fragment pass because each
pixel's quantization error feeds forward into neighbours. Blue-noise
threshold approximation produces visually similar output on natural images
without the serial bottleneck.

Algorithm coverage:

| Algorithm        | GPU strategy                                      |
|------------------|---------------------------------------------------|
| bayer            | procedural bit-interleave Bayer (level 1..4 → 4..32) |
| floydSteinberg   | IGN approximation, coefficient 0.85               |
| atkinson         | IGN approximation, coefficient 0.75               |
| blueNoise        | IGN unmodulated                                   |
| artisticDrip     | IGN approximation, coefficient 0.65               |
| halftone         | hard-coded 6×6 clustered-dot matrix               |
| stucki           | IGN approximation, coefficient 0.80               |
| whiteNoise       | hash-based per-pixel white noise                  |
| **riemersma**    | **CPU only** — Hilbert curve traversal is serial  |

Colour modes:
- `.bw` → mono dither, output 0/1 → mapped to black/white
- `.twoTone(fg, bg)` → mono dither → mapped to fg/bg colours
- `.dominantTwoTone(...)` → CPU resolves dominant colours via
  `ColorExtractor.extractTwoDominantColors`, then mono dither maps to them
- `.color(levels: N)` → per-channel quantization with per-channel decorrelated
  IGN offset (channels read different positions in the noise field so they
  don't snap together)

Pixel-scale handling matches CPU exactly: downscale source to work resolution
with bilinear, run dither pass, upscale back to original with nearest-neighbour
for chunky pixels.

Sharpen and contrast pre-processing are inline in the shader (unsharp mask
via 3×3 box blur + S-curve contrast) so they don't require a separate pass.

Parity test strategy (`testDitherBayerOutputIsBinaryBW`,
`testDitherTwoToneMapsToColors`, `testDitherRiemersmaRoutesToCPU`,
`testDitherColorLevelsQuantizesPerChannel`) checks structural properties
rather than per-pixel deltas — the blue-noise approximation guarantees
visual similarity, not bit-for-bit equivalence with serial error diffusion.

### Extended algorithms (landed in dither-extensions pass)

`DitherAlgorithm` now covers Sierra (3-row), Sierra Two-Row, Sierra Lite,
Jarvis-Judice-Ninke, Burkes, Interleaved Gradient Noise, and CMYK Halftone.
All have full CPU implementations (kernel-table form for the error-diffusion
family, procedural for IGN). GPU implementations use the same blue-noise
approximation strategy with per-algorithm coefficients tuned by visual
character on natural photos.

Coefficient table (`thresholdForAlgorithm` in `Dither.metal`):

| Algorithm           | Coefficient | Notes |
|---------------------|-------------|-------|
| floydSteinberg      | 0.85        | original tuning |
| sierra              | 0.85        | similar spread to Floyd-Steinberg |
| burkes              | 0.85        | larger 5×2 kernel, similar character |
| stucki              | 0.80        | wider 5×3 kernel |
| atkinson            | 0.75        | partial diffusion (6/8) |
| sierraTwoRow        | 0.75        | tighter Sierra variant |
| artisticDrip        | 0.65        | heavy downward bias in CPU kernel |
| sierraLite          | 0.65        | smallest Sierra variant |
| jarvisJudiceNinke   | 0.90        | largest 5×3 kernel — broadest spread |
| interleavedGradientNoise | 1.0    | unmodulated IGN |

`DitherColorMode` gains `.palette([CodableColor])` (capped at 16 colours).
The model file ships canonical vintage palettes via `VintagePalette`:
GameBoy DMG-01, NES (subset), Commodore 64 (full 16), and IBM CGA palette 1.
Palette-mode dithering uses per-channel decorrelated IGN jitter to nudge
pixels across palette boundaries — the trick that makes vintage palette
output painterly instead of posterised.

`.cmykHalftone` is GPU-first with a documented degradation: CPU fallback
uses monochrome 6×6 clustered dot (no per-channel rotation). True CMYK
rotated screens only run on the GPU path.

### Algorithms still NOT ported

The remaining items from `grainrad/notes/dithering.md` would change the
parameter surface significantly:

- Modulation overlays (wave / grid / radial / horizontal / rgbSplit on top of
  the threshold)
- Epsilon glow post-pass
- JPEG-glitch effects (block-shift, channel-swap, scanline-offset)
- Chromatic aberration as part of the dither pass

Most of these probably belong as separate effect layers rather than dither
sub-modes.

## Original plan continues below.

## Target

Replace all four Effects-bucket renderers in Framer with Metal fragment shaders. GPU-only — CPU renderers deleted as each bucket lands. Framer is macOS-only, so `MTLCreateSystemDefaultDevice()` is always available, including in `FramerCLI`.

**In scope** (the `Sources/FramerCore/Effects/Renderers/` directory):
- `TextCellRenderer` — ASCII, Dots, Blockify, MatrixRain
- `PrintSamplingRenderer` — Dithering, Halftone, Threshold, Crosshatch
- `EdgeFieldRenderer` — Contour, Edge Detection, Wave Lines, Voronoi, Noise Field
- `GlitchRenderer` — Pixel Sort, VHS

**Out of scope** (left as CPU):
- `FrameProcessor` and all adjustment passes (brightness, contrast, saturation, gamma, hue, sharpness, curves, etc.)
- Legacy `ShaderASCIIRenderer` (the `.shader` layer type)
- Gradient / dominant-color / dust / light-leak / wet-plate / frame layer types
- Preset store, YAML config, border renderer

If adjustments later need GPU, that's a separate project.

## Root cause of "ASCII is broken"

`Sources/FramerCore/Effects/Renderers/TextCellRenderer.swift:78` dispatches `.ascii` to `paintASCII()` at lines 318–338, which draws **placeholder horizontal bars** instead of glyphs. The full infrastructure (dispatch, parameters, YAML, tests) was wired end-to-end but the renderer itself is a stub. The working ASCII algorithm already exists at `Sources/FramerCore/Processing/ShaderASCIIRenderer.swift` (CPU, 522 lines, Sobel + `edgesASCII.png`/`fillASCII.png` LUT atlases) — but isn't connected to the new Effects system.

The entire `Effects/GPU/` directory is currently a scaffold labeled "GPU" — `GPUCommandContext` creates `MTLDevice`+`MTLCommandQueue` that are never used. All four bucket renderers are pure Swift pixel loops. No `.metal` files exist anywhere in `Sources/`.

## Phase 1 — Metal infrastructure + ASCII pilot

**Design decision**: Single-pass fragment shader (not Grainrad's two-pass compute+fragment). The `edgesASCII.png`/`fillASCII.png` atlas already encodes 10 luminance levels × 4 edge directions, so there's no need for a compute matching pass. This is simpler and visually equivalent. Grainrad-style compute matching can be revisited later as a quality upgrade.

**Files to create** in `Sources/FramerCore/Effects/Metal/`:

| File | Purpose |
|---|---|
| `ShaderCommon.h` | Shared inlines: luminance, IGN, brightness/contrast/gamma helpers, Bayer matrices, VertexOut struct, common uniform layouts. Copied from `/Users/arthur.soares/Github/grainrad/port/ShaderCommon.h`. |
| `FullscreenVertex.metal` | Single shared `fullscreenVertex` entry point. Copied from port template. |
| `TextCell.metal` | Fragment shader dispatching on variant. Dots already fully implemented in port template. ASCII needs new `asciiVariant` function. |

**Files to create** in `Sources/FramerCore/Effects/GPU/`:

| File | Purpose |
|---|---|
| `MetalEffectLibrary.swift` | Loads `default.metallib` from `Bundle.module`. Caches `MTLRenderPipelineState` by fragment function name. Provides shared nearest+clamp and linear+clamp samplers. Thread-safe with `NSLock`. |
| `MetalTextureSupport.swift` | CGImage → MTLTexture via `MTKTextureLoader`, atlas PNG loader with LUT caching (loads from `TextureFrameProvider.searchPaths`), MTLTexture → CGImage readback via CIContext. |
| `MetalRenderPass.swift` | Thin wrapper: pipeline + source texture + uniform bytes + output size → render-encoded private MTLTexture. Keeps bucket renderers ~20 lines. |

**ASCII fragment shader** (`TextCell.metal::asciiVariant`):

Mirrors `ShaderASCIIRenderer.apply()` algorithm:
1. Compute cell coordinates from `in.uv` and `uniforms.geometry.scale`
2. Sample source at cell center; compute per-cell average luminance
3. Run 3×3 Sobel on luminance neighbors to detect edge direction
4. Apply exposure/attenuation/black-level/invert to luminance
5. If edge detected: sample `edgesASCII` at `(glyphX + (direction+1)*8, glyphY)`. Else: quantize luminance to 0–9, sample `fillASCII` at `(glyphX + level*8, glyphY)`
6. Return `mix(background, foreground, glyphValue)` with intensity

Atlas textures bound at `texture(1)` (edges) and `texture(2)` (fill). Source at `texture(0)`. Uniforms at `buffer(0)`.

**Wire-up** in `TextCellRenderer.renderPreview`:
- For `.ascii` case: fetch pipeline via `MetalEffectLibrary.pipeline(for: "textCellFragment")`, upload source + atlas textures, encode uniforms from `TextCellParameters`, run pass, readback CGImage
- Other variants (`dots`, `blockify`, `matrixRain`) keep CPU path until Phase 2
- Delete `paintASCII()` and ASCII-specific branches in `styledColor`/`backgroundColor`/`characterSetBias`

**Validation**:
- `swift test --filter ASCIIParityTests` passes (character sets differ; fg/bg colors affect output)
- `swift test --filter EffectGoldenImageTests` passes (regenerate baselines if needed — GPU ≠ CPU bit-for-bit due to fp precision; use tolerance-based SSIM or channel-delta ≤ 0.5%)
- `FramerCLI` renders ASCII through GPU path headlessly

## Phase 2 — Finish TextCell bucket

Port the remaining variants to GPU. `dotsVariant` is already fully drafted in `/Users/arthur.soares/Github/grainrad/port/TextCell.metal` (branchless shape selection, hex-grid math).

- **Dots** (20 min port — copy from template)
- **Blockify** (20 min port — same pipeline, solid vs outlined)
- **MatrixRain** (needs time uniform + per-column state buffer for column velocities/phases)

Delete `TextCellRenderer`'s CPU pixel-loop entirely. The Swift function body shrinks to: switch on variant → fetch pipeline → encode pass.

## Phase 3 — PrintSampling bucket

One fragment shader switching on algorithm uniform. Key insight from `/Users/arthur.soares/Github/grainrad/notes/dithering.md`: Grainrad's "Floyd-Steinberg" is a **blue-noise threshold approximation** (IGN from SIGGRAPH 2014), not real error diffusion. Same visual, GPU-parallelizable, no cell-to-cell dependency.

Variants:
- **Dithering**: Bayer 4×4, Bayer 8×8, blue-noise-approximated Floyd-Steinberg, Atkinson, Stucki, Sierra variants
- **Halftone**: dot/square/diamond shapes with angle rotation (via rotation matrix in UV space)
- **Threshold**: N-level quantization with optional dither
- **Crosshatch**: multi-layer line patterns at configurable angles + thickness

Delete `PrintSamplingRenderer` CPU path.

## Phase 4 — EdgeField bucket

Sobel/Laplacian edge detection, contour extraction, wave-line displacement, Voronoi cells, noise-field distortion. Delete CPU path.

## Phase 5 — Glitch bucket

Pixel sort (per-pixel fragment-shader trick from `/Users/arthur.soares/Github/grainrad/notes/pixel-sort.md` — 24-sample cap per pixel, no serial passes), VHS (scanlines + chromatic aberration + tracking error). Delete CPU path.

## Phase 6 — CLI + test validation

- Confirm `FramerCLI` renders through `GPUEffectsPlatform` headlessly (Mac-only → Metal always available)
- Regenerate golden-image baselines from GPU output (existing ones are CPU-based)
- Decide test policy when `MTLCreateSystemDefaultDevice()` returns nil — likely fail-hard since GPU is now required

## Files and locations

**Study/reference repo** (this repo, `/Users/arthur.soares/Github/grainrad`):
- `notes/ascii.md` — ASCII algorithm notes, Grainrad's two-pass design vs. our single-pass atlas approach
- `notes/dithering.md` — blue-noise approximation insight
- `notes/dots.md` — grid math, branchless shape selection
- `notes/pixel-sort.md` — Kim Asendorf 4 modes, fragment-per-pixel trick
- `port/ShaderCommon.h`, `port/FullscreenVertex.metal`, `port/TextCell.metal` — Metal templates to copy
- `port/DotsExample.swift` — Swift integration example (won't compile standalone, references Framer types)
- `reference/` (gitignored) — Grainrad's production JS bundle + extracted WGSL shaders, read-only study material

**Framer worktree** (`/Users/arthur.soares/Github/.dotfiles_2024/config/.config/superpowers/worktrees/framer/grainrad-gpu-effects`, branch `feat/grainrad-gpu-effects`):
- `Sources/FramerCore/Effects/Renderers/*.swift` — current CPU renderers (to be replaced)
- `Sources/FramerCore/Effects/GPU/*.swift` — current scaffold (to be filled in)
- `Sources/FramerCore/Effects/Models/GPUEffectParameters.swift` — parameter shapes (kept)
- `Sources/FramerCore/Processing/ShaderASCIIRenderer.swift` — working CPU ASCII reference (untouched)
- `assets/textures/edgesASCII.png`, `assets/textures/fillASCII.png` — atlas files (loaded via `TextureFrameProvider.searchPaths`)
- `project.yml` — XcodeGen config (consumes FramerCore as SPM package; no changes needed for Metal since SPM auto-compiles `.metal` files into `default.metallib` in `Bundle.module`)
- `Package.swift` — FramerCore target (no resource changes needed for `.metal` auto-compilation)
- `Tests/FramerCoreTests/ASCIIParityTests.swift` — must pass post-migration
- `Tests/FramerCoreTests/EffectGoldenImageTests.swift` — may need regenerated baselines

## Attribution

Every ported shader carries the Grainrad attribution header per `/Users/arthur.soares/Github/grainrad/CREDITS.md`. No Grainrad code is copied or translated line-by-line; techniques are studied via the `reference/` WGSL extracts and re-implemented fresh in Metal against primary sources (Bayer 1973, Jimenez 2014 IGN, Sobel, Kim Asendorf pixel sort, Paul Bourke, Ulichney).
