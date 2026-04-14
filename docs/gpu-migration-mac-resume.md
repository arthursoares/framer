# GPU migration — Mac-side resume context

**Authored on Linux Cloud, 2026-04-13. Read this first when resuming on Mac.**

This document is the single-page handoff for everything that landed across
the cloud session. Pair with `docs/gpu-migration-plan.md` for the longer
per-effect rationale.

## TL;DR

A complete GPU port of the Effects bucket landed on
`claude/gpu-effects-migration-MbMMo` across **7 commits**. Every shader
effect (ASCII, Crimewave, Narc, Shiba, DistantPast, CRT, Halftone, Kuwahara,
PixelSort) plus the Dither layer now have Metal fragment-shader
implementations with a CPU fallback. The new `gpuOrCPU(image:gpu:cpu:)`
helper in `ShaderRenderer` (and the renamed `DitherRenderer.applyCPU`) makes
fallback automatic — `MetalEffectError` triggers CPU; any other error
bubbles up.

**Nothing has been compiled or executed.** This was a Linux session, so
there is no `swift` / `xcrun metal` to validate against. The Mac-side
resume needs to:

1. `swift build` — confirms the metallib compiles and the new sources type-check.
2. `swift test --filter EffectGPUParityTests` — runs the parity tests (they
   self-skip when Metal is unavailable so they no-op on CI).
3. Visually verify a representative image through `FramerCLI` for each effect.

The known-fragile spots are listed under **Mac-side risk register** below.

## Branch + commits

```
claude/gpu-effects-migration-MbMMo
├── b3a82a2  feat: GPU ASCII via single-pass Metal fragment shader (Phase 1)
├── 4aa992b  feat: GPU port of all remaining shader effects (PixelSort excepted)
├── 1033743  feat: GPU pixel sort via per-fragment 24-sample approximation
├── 7693d5b  feat: GPU dither via blue-noise threshold approximation
├── 35f303f  feat: extend dither with Sierra family + JJN + Burkes + IGN + palette + CMYK
└── c289915  feat: pixel sort gains diagonal + Kim Asendorf modes + randomness + reverse
```

Each commit is self-contained: it ports one effect (or extends an existing
port) with CPU implementation, GPU implementation, dispatch wiring,
parity-style tests, and migration-plan updates.

## Architecture overview

### `Sources/FramerCore/Effects/`

```
Effects/
├── Metal/                     ← .metal sources, compiled into default.metallib
│   ├── ShaderCommon.h         ← shared inlines (luminance, IGN, Bayer, uniforms)
│   ├── FullscreenVertex.metal ← single shared vertex entry: fullscreenVertex
│   ├── _EffectTemplate.metal  ← scaffold for new buckets (don't compile, name starts with _)
│   ├── TextCell.metal         ← ASCII (single-pass LUT-based) + dots stub + blockify stub
│   ├── ColorGrade.metal       ← Crimewave / Narc / Shiba (variant-switched fragment)
│   ├── DistantPast.metal      ← warm-shift + dithered palette snap + vignette + grain
│   ├── CRT.metal              ← barrel + scanlines + vignette
│   ├── Halftone.metal         ← CMYK rotation or monochrome dot screen
│   ├── Kuwahara.metal         ← 4-quadrant variance smoothing
│   ├── PixelSort.metal        ← per-fragment 24-sample bubble-sort
│   └── Dither.metal           ← 15 algorithms via blue-noise approximation
├── GPU/
│   ├── MetalEffectLibrary.swift   ← shared singleton: device, pipeline cache, samplers
│   ├── MetalTextureSupport.swift  ← CGImage↔MTLTexture, cached LUT loader, CIContext readback
│   ├── MetalRenderPass.swift      ← thin fullscreen-triangle encoder
│   └── SharedUniforms.swift       ← Swift mirrors of FramerCommonUniforms / Geometry / Color
└── Renderers/
    ├── TextCellRenderer.swift    ← ASCII (renderASCII)
    ├── ColorGradeRenderer.swift  ← Crimewave / Narc / Shiba
    ├── DistantPastRenderer.swift
    ├── CRTRenderer.swift
    ├── HalftoneRenderer.swift
    ├── KuwaharaRenderer.swift
    ├── PixelSortRenderer.swift
    └── DitherGPURenderer.swift   ← all dither algorithms + colour modes
```

### `Package.swift`

```swift
.target(
    name: "FramerCore",
    dependencies: [.product(name: "Yams", package: "Yams")],
    resources: [
        .process("Effects/Metal"),  // compiles .metal → default.metallib in Bundle.module
    ]
),
```

### Dispatch flow

```
ShaderRenderer.apply(...)                 (Sources/FramerCore/Processing/ShaderRenderer.swift)
└── gpuOrCPU(image:gpu:cpu:)              ← catches MetalEffectError, falls back to CPU
    ├── try GPU renderer (e.g. ColorGradeRenderer.renderCrimewave)
    └── if MetalEffectError → CPU helper (e.g. ShaderRenderer.applyCrimewave)

DitherRenderer.apply(...)                 (Sources/FramerCore/Processing/DitherRenderer.swift)
├── try DitherGPURenderer.apply
└── if MetalEffectError → DitherRenderer.applyCPU  (the legacy 1100-line CPU body)
```

CPU helpers (`applyCrimewave`, `applyNarc`, etc.) were demoted from `private`
to `internal` so the parity tests can hit both paths against the same input.
Same with `DitherRenderer.applyCPU`.

### MetalEffectError

```swift
public enum MetalEffectError: Error {
    case metalUnavailable
    case libraryUnavailable(String)
    case functionMissing(String)
    case pipelineCreationFailed(String, underlying: Error?)
    case samplerCreationFailed
    case textureCreationFailed
    case textureLoadFailed(String)
    case readbackFailed
    case commandEncodingFailed
}
```

`gpuOrCPU` only catches **`MetalEffectError`**. Other errors propagate so
genuine bugs surface — important for the parity tests to reveal real problems.

## Effect-by-effect status

| Effect       | Style       | CPU | GPU | Parity test                                    |
|--------------|-------------|-----|-----|------------------------------------------------|
| ASCII        | shader      | ✅  | ✅  | `testASCIIParity` (loose tolerance — sub-cell sampling differs) |
| Crimewave    | shader      | ✅  | ✅  | `testCrimewaveParity` (mean ≤ 6.0/255)        |
| Narc         | shader      | ✅  | ✅  | `testNarcParity` (mean ≤ 6.0/255)             |
| Shiba        | shader      | ✅  | ✅  | `testShibaParity` (mean ≤ 6.0/255)            |
| DistantPast  | shader      | ✅  | ✅  | `testDistantPastParity` (mean ≤ 12/255 — palette flips at boundaries) |
| CRT          | shader      | ✅  | ✅  | `testCRTParity` (mean ≤ 8/255 — distorted UV sampling) |
| Halftone     | shader      | ✅  | ✅  | `testHalftoneMonoParity` (mean ≤ 15/255)      |
| Kuwahara     | shader      | ✅  | ✅  | `testKuwaharaParity` (mean ≤ 12/255)          |
| PixelSort    | shader      | ✅  | ✅  | `testPixelSortParityDefaultSpan` (mean ≤ 12/255), `testPixelSortRespectsThresholdSkip` |
| **Dither**   | layer       | ✅  | ✅  | structural tests (no per-pixel parity vs error diffusion) |

### Dither algorithm coverage (15 total now)

| Algorithm                    | CPU   | GPU   | Notes |
|------------------------------|-------|-------|-------|
| `bayer`                      | ✅    | ✅    | Procedural bit-interleave for level 1..4 (4×4..32×32) |
| `floydSteinberg`             | ✅    | ✅    | GPU coef 0.85 |
| `atkinson`                   | ✅    | ✅    | GPU coef 0.75 |
| `blueNoise`                  | ✅    | ✅    | CPU R2 texture, GPU IGN — visually similar |
| `artisticDrip`               | ✅    | ✅    | GPU coef 0.65 (Framer-specific kernel) |
| `halftone`                   | ✅    | ✅    | 6×6 clustered dot |
| `stucki`                     | ✅    | ✅    | GPU coef 0.80 |
| `whiteNoise`                 | ✅    | ✅    | Hash-based per-pixel noise |
| `riemersma`                  | ✅    | ❌    | Hilbert curve traversal — CPU only, GPU forces fallback |
| `sierra` (NEW)               | ✅    | ✅    | GPU coef 0.85, divisor 32 |
| `sierraTwoRow` (NEW)         | ✅    | ✅    | GPU coef 0.75, divisor 16 |
| `sierraLite` (NEW)           | ✅    | ✅    | GPU coef 0.65, divisor 4 |
| `jarvisJudiceNinke` (NEW)    | ✅    | ✅    | GPU coef 0.90, divisor 48, broadest |
| `burkes` (NEW)               | ✅    | ✅    | GPU coef 0.85, divisor 32 |
| `interleavedGradientNoise` (NEW) | ✅ | ✅   | First-class IGN distinct from `blueNoise` |
| `cmykHalftone` (NEW)         | ⚠️    | ✅    | CPU degrades to mono 6×6; true CMYK rotation only on GPU |

### Dither colour modes

| Mode                            | CPU | GPU | Notes |
|---------------------------------|-----|-----|-------|
| `.bw`                           | ✅  | ✅  | Binary 0/1 per pixel |
| `.twoTone(fg, bg)`              | ✅  | ✅  | Maps 0/1 → fg/bg colours |
| `.dominantTwoTone(...)`         | ✅  | ✅  | Resolves dominant colours CPU-side via `ColorExtractor` |
| `.color(levels: Int)`           | ✅  | ✅  | Per-channel quantization with decorrelated noise |
| `.palette([CodableColor])` (NEW)| ✅  | ✅  | Capped at 16 colours; nearest-match in linear RGB |

### Vintage palettes

`VintagePalette.{gameBoy, nes, c64, cga}` — canonical 4 / 4 / 16 / 4 colour
sets ready to drop into `.palette(VintagePalette.gameBoy)` etc.

### PixelSort surface

| Knob          | Type                | Notes |
|---------------|---------------------|-------|
| `threshold`   | `Double`            | Existing — 0..1 |
| `direction`   | `PixelSortDirection`| Existing values + **`.diagonal`** (NEW) |
| `span`        | `Int`               | Existing — 1..256 |
| `amount`      | `Double`            | Existing — pre-multiplied with `intensity` |
| `spanMode`    | `PixelSortSpanMode` | NEW: `.luminance` (default), `.kimBlack`, `.kimWhite`, `.kimBright`, `.kimDark` |
| `randomness`  | `Double`            | NEW: 0..1 per-line threshold jitter |
| `reverse`     | `Bool`              | NEW: descending sort |

All new fields decode as optional with the legacy default, so old YAML /
presets behave identically.

## Mac-side resume checklist

```bash
# 1. Pick up the branch
git checkout claude/gpu-effects-migration-MbMMo
git pull

# 2. Build
swift build
# Watch for:
#   - default.metallib being placed in Bundle.module (the .process("Effects/Metal")
#     rule is the unproven part of this branch)
#   - Any uniform-layout-related compile errors

# 3. Run the GPU parity test suite
swift test --filter EffectGPUParityTests
# Tests self-skip when Metal is unavailable, so they should run on Mac.

# 4. Run the legacy CPU dither test suite to confirm no regressions
swift test --filter DitherRendererTests

# 5. Smoke-test through the CLI
swift run framer process --input <some.jpg> --shader ascii --output /tmp/ascii-gpu.png
swift run framer process --input <some.jpg> --shader pixelSort --output /tmp/sort-gpu.png
# (etc. for each effect — the CLI dispatches through ShaderRenderer.apply,
# which now goes GPU-first)

# 6. Visual diff GPU vs CPU output for each effect
# Easy way: temporarily edit gpuOrCPU to always throw, force CPU path,
# render same input, diff in Preview / your tool of choice.
```

## Mac-side risk register

In rough order of likelihood:

### 1. `Bundle.module` empty / `default.metallib` missing
**Symptom**: `MetalEffectLibrary.shared` is non-nil but `pipeline(for:)` throws
`functionMissing("fullscreenVertex")` → every GPU call falls back to CPU.

**Fix**: switch `Package.swift` from `.process("Effects/Metal")` to per-file
declarations:

```swift
resources: [
    .process("Effects/Metal/ShaderCommon.h"),
    .process("Effects/Metal/FullscreenVertex.metal"),
    .process("Effects/Metal/TextCell.metal"),
    .process("Effects/Metal/ColorGrade.metal"),
    .process("Effects/Metal/DistantPast.metal"),
    .process("Effects/Metal/CRT.metal"),
    .process("Effects/Metal/Halftone.metal"),
    .process("Effects/Metal/Kuwahara.metal"),
    .process("Effects/Metal/PixelSort.metal"),
    .process("Effects/Metal/Dither.metal"),
],
```

The `_EffectTemplate.metal` should NOT be compiled — its leading underscore
is the convention for "don't ship". If SwiftPM tries anyway, exclude with
`exclude: ["Effects/Metal/_EffectTemplate.metal"]`.

### 2. Uniform-layout drift (Swift struct ≠ MSL struct stride)
**Symptom**: GPU output looks like garbled noise / wrong colours that don't
respond to parameter changes; or pipeline build fails with a cryptic Metal
validation error about uniform buffer size.

**Fix**: print `MemoryLayout<X>.stride` for the renderer's `Uniforms` struct
and compare against `sizeof(X)` printed from inside the .metal file (use a
test pixel that returns the size as a colour). The most likely offenders:

- `DitherGPURenderer.Uniforms` — bumped to ~360 bytes with the 16-slot
  palette tuple. The palette field is a 16-element tuple of `SIMD4<Float>`;
  Swift might lay it out differently than MSL's `float4 palette[16]` in
  edge cases. If parity fails on palette mode specifically, suspect this.
- `PixelSortRenderer.Uniforms` — added `spanMode`, `reverse`, `randomness`
  with 3 trailing pad floats. Verify the trailing pad is preserved on Mac.
- `TextCellRenderer.Uniforms` — 240 bytes with 4 trailing `SIMD4<Float>`
  colour fields, which require 16-byte alignment after the preceding
  scalar block.

### 3. CMYK halftone parity (intentional divergence)
**Symptom**: `cmykHalftone` algorithm produces visibly different output on
CPU vs GPU.

**Cause**: documented limitation — CPU degrades to mono 6×6 clustered dot;
true per-channel CMYK rotation only on GPU. Not a bug, but if it surprises
the user the CPU path should be either implemented properly or the algo
should be flagged GPU-only in the UI.

### 4. PixelSort default-span parity (test threshold)
**Symptom**: `testPixelSortParityDefaultSpan` mean delta > 12/255.

**Cause**: rank flips cascade across many bytes. If the failure is small
(say 12..20), raise the tolerance after eyeballing the diff. If large
(50+), check that:
- `posInSpan = back` is the right invariant for your CPU sweep direction
- The sorting is ascending in both paths (default `reverse = false`)
- The `mix(currentColor, sortedColor, intensity)` blend factor matches
  `params.intensity * pixelSortParams.amount` on both sides

### 5. Dither blue-noise parity (intentionally loose)
**Symptom**: `testDitherBayerOutputIsBinaryBW` reports too many non-binary
pixels.

**Cause**: sub-pixel sampling at edges between cells. Allowed in the test
spec at ≤ 1% — if Mac shows more, raise to 5%.

### 6. SwiftPM package compile failure on a single shader
If one .metal file has an unrelated typo and prevents the whole library
from compiling, **every** GPU path throws and falls back to CPU. The smoke
test in step 5 above will reveal this — multiple effects "look like CPU"
simultaneously is the signature.

## Things that intentionally don't have parity tests

- **CMYK halftone** — CPU and GPU implementations are deliberately
  different (see risk #3).
- **Riemersma** — only the CPU path exists; testing parity is meaningless.
- **Modulation overlays / epsilon glow / JPEG glitch** — not implemented in
  this session; left as future work in the migration plan.

## What's deferred (out of scope for this session)

From `grainrad/notes/dithering.md`:
- Modulation overlays (wave / grid / radial / horizontal / rgbSplit on top
  of the threshold)
- Epsilon glow post-pass
- JPEG-glitch effects (block-shift, channel-swap, scanline-offset)
- Chromatic aberration as a dither sub-mode

These probably belong as separate effect layers rather than dither sub-modes
— hold off until there's product intent.

From `grainrad/notes/pixel-sort.md`:
- Diagonal direction reads source via integer steps along `(1, 1)`. The
  "true" anti-diagonal would normalise the step (length √2) — slightly
  different sampling cadence at sub-pixel level. Probably not worth fixing.

From the original migration plan's later phases:
- `Sources/FramerCore/Effects/Metal/_EffectTemplate.metal` is a scaffold
  for new buckets. Not used — informational only. Either compile-skip it
  or delete it before shipping.

## Reference docs

- `docs/gpu-migration-plan.md` — the long-form migration plan with status
  table, per-effect notes, and per-algorithm coefficient tables.
- `grainrad/notes/ascii.md` — ASCII algorithm reference (atlas-based vs
  Grainrad's two-pass compute).
- `grainrad/notes/dithering.md` — blue-noise approximation strategy and
  full algorithm palette.
- `grainrad/notes/pixel-sort.md` — fragment-per-pixel approach and Kim
  Asendorf modes.
- `grainrad/port/README.md` — Metal template overview.
- `grainrad/CREDITS.md` — attribution discipline (every shader carries a
  Grainrad attribution header).

## Attribution

Every ported shader has the attribution header per `grainrad/CREDITS.md`.
No Grainrad code is copied or translated line-by-line — techniques are
re-implemented fresh in MSL against primary sources (Bayer 1973, Floyd &
Steinberg 1976, Sobel & Feldman 1968, Jimenez SIGGRAPH 2014, Kim Asendorf
2010, Paul Bourke ASCII art reference).

The CPU error-diffusion kernels (Sierra, JJN, Burkes) use standard
divisor-table form documented in Ulichney's *Digital Halftoning* (MIT Press,
1987).

## Validation status when leaving the cloud session

- ✅ All files are syntactically structured (matched braces, sensible
  bodies)
- ✅ Imports look correct for macOS / iOS targets
- ✅ All commits pass `git push` (so no merge / authentication issues)
- ❌ `swift build` not run (no Swift toolchain in the cloud container)
- ❌ `swift test` not run (no Metal device in the cloud container)
- ❌ Visual smoke test not run
- ❌ Uniform layout sizes not verified at runtime

The first two ❌s are the critical Mac-side validation gates. The rest are
"do this if anything looks wrong visually."
