---
name: framer-metal-pipeline-reference
description: >
  Load when touching anything under Sources/FramerCore/Effects/Metal/ or
  Effects/GPU/ (MetalEffectLibrary, MetalRenderPass, MetalTextureSupport,
  SharedUniforms, uniformBytes), when adding or modifying a GPU effect or
  .metal shader, when debugging "all effects look like CPU", garbled colors,
  a Metal validation error about uniform buffer length, wrong colors after
  HEIC/PNG upload, upside-down output, or CPU/GPU parity drift, and when
  working on the LUT compute path (LUTMetalRenderer). Keywords: Metal, metallib,
  fragment shader, uniforms, MTLTexture, MTKTextureLoader, threadgroup,
  pixel sort span, parity test, gpuOrCPU, MetalEffectError.
---

# Framer Metal Pipeline Reference

The Metal infrastructure knowledge pack: how shaders are loaded, how uniforms
are passed without corruption, how images get on and off the GPU, and the
exact checklist for adding a new GPU effect. Everything here was verified
against the repo at commit 48d85a5 (2026-07-09).

## When NOT to use this skill

| You actually want | Go to |
|---|---|
| Effect MATH/theory (dither IGN approximation, blend-mode formulas, color spaces, LUT interpolation theory) | framer-image-processing-reference |
| Parameter catalog, capability flags per effect, add-a-parameter UI wiring | framer-config-and-flags |
| Symptom→triage for a live bug | framer-debugging-playbook |
| Full incident stories (referenced by name below) | framer-failure-archaeology |
| Why the CPU fallback exists at all / whether it should be retired | framer-architecture-contract (open decision) |
| Fixing the broken xcodebuild/app-test tier | framer-campaign-restore-validation |

## Metal vocabulary (one line each)

- **Fragment shader**: a GPU function that computes the color of one output pixel; Framer's effects are almost all fragment shaders.
- **Vertex shader**: a GPU function that positions geometry; here a single shared one (`fullscreenVertex`) draws one triangle covering the whole screen.
- **Compute kernel**: a GPU function dispatched over an arbitrary grid instead of geometry; only the LUT stack uses one.
- **Uniform buffer**: a small block of constant parameters (a struct) passed from Swift to the shader each draw.
- **metallib**: a compiled library of Metal shader functions, analogous to a `.o`/`.dylib` for shaders.
- **MSL**: Metal Shading Language, the C++-dialect the `.metal` files are written in.
- **Threadgroup**: the tile of GPU threads a compute kernel is dispatched in (the LUT kernel uses up-to-16×16 tiles).
- **Sampler**: the GPU object that controls how a texture is read (nearest vs linear filtering, edge clamping).

## Map: the TWO Metal stacks (they share no code)

**1. Effects stack** — fragment shaders over a fullscreen triangle.
Shaders: `Sources/FramerCore/Effects/Metal/` (13 `.metal` files + `ShaderCommon.h`).
Infrastructure: `Sources/FramerCore/Effects/GPU/` (`MetalEffectLibrary`,
`MetalRenderPass`, `MetalTextureSupport`, `MetalUniformEncoding`,
`SharedUniforms`, `ASCIIAtlasGenerator`, `GPUEffectsPlatform`).
Renderers: `Sources/FramerCore/Effects/Renderers/`.

**2. LUT compute stack** — `Sources/FramerCore/Processing/LUTMetalRenderer.swift`.
Completely self-contained: its MSL source is an embedded Swift string compiled at
runtime via `device.makeLibrary(source:)`; one compute kernel `applyLUT`; input/
output textures are `.rgba8Uint` 2D, the LUT itself is a `.rgba32Float` 3D texture;
threadgroups sized `min(threadExecutionWidth,16) × min(maxThreads/width,16)`.
Fallback contract differs too: `LUTMetalRenderer.apply` returns `nil` on any
failure and `LUTRenderer` then runs `applyCPU` — no `MetalEffectError` involved.
Textures are cached per (width,height) and LUTs per content key, never evicted.

### The 13 .metal files and what lives where (as of 2026-07-09, commit 48d85a5)

| File | Entry point | Serves |
|---|---|---|
| FullscreenVertex.metal | `fullscreenVertex` (vertex) | shared by every effect pipeline |
| TextCell.metal | `textCellFragment` | bucket variants: 0 dots, 1 blockify, 2 ascii, 3 matrixRain (also the `.shader` ASCII layer via TextCellRenderer) |
| PrintSampling.metal | `printSamplingFragment` | bucket variants: 0 threshold, 1 crosshatch (bucket halftone/dithering are CPU-only and hidden from the picker) |
| EdgeField.metal | `edgeFieldFragment` | bucket variants: 0 edgeDetection, 1 contour, 2 waveLines, 3 voronoi, 4 noiseField |
| Glitch.metal | `glitchFragment` | bucket variant: 0 VHS |
| PixelSort.metal | `pixelSortFragment` | `.shader` PixelSort layer AND the Glitch bucket's pixelSort (same shader, two Swift front doors) |
| Dither.metal | `ditherFragment` | the `.dither` layer (all algorithms except Riemersma, which is forced to CPU) |
| ColorGrade.metal | `colorGradeFragment` | `.shader` variants: 0 crimewave, 1 narc, 2 shiba |
| DistantPast.metal | `distantPastFragment` | `.shader` DistantPast |
| CRT.metal | `crtFragment` | `.shader` CRT |
| Halftone.metal | `halftoneFragment` | `.shader` Halftone |
| Kuwahara.metal | `kuwaharaFragment` | `.shader` Kuwahara |
| _EffectTemplate.metal | `__bucketFragment` (scaffold) | copy-me template; EXCLUDED from the build (Package.swift `exclude:`) |

`ShaderCommon.h` (not a .metal file) is the shared header: `VertexOut`, Rec.601
`luminance()`, `maxRGB()` (Kim Asendorf brightness), `applyCommonAdjustments()`
(order: brightness/contrast → saturation → hue → gamma; sharpness deliberately
NOT applied), the IGN noise function, Bayer matrices, and the canonical
`FramerCommonUniforms` / `FramerGeometryUniforms` / `FramerColorUniforms` layouts.

## Dispatch topology: who calls whom

```
.shader layer      → ShaderRenderer.apply → gpuOrCPU(gpu:, cpu:)
                       gpu: TextCellRenderer / PixelSortRenderer / ColorGradeRenderer /
                            DistantPastRenderer / CRTRenderer / HalftoneRenderer / KuwaharaRenderer
                       cpu: ShaderASCIIRenderer / ShaderPixelSortRenderer / ShaderRenderer.applyX
.gpuEffect layer   → FrameProcessor → GPUEffectsPlatform.dispatchRenderPreview
                       .textCell      → TextCellBucketRenderer  ┐ each tries its GPU renderer,
                       .printSampling → PrintSamplingRenderer   │ catches MetalEffectError inline,
                       .edgeField     → EdgeFieldRenderer       │ runs its own CPU pixel loop
                       .glitch        → GlitchRenderer          ┘
.dither layer      → DitherRenderer → DitherGPURenderer (catch is MetalEffectError → CPU)
.lut layer         → LUTRenderer → LUTMetalRenderer (nil return → applyCPU)
```

**The fallback contract** (`Sources/FramerCore/Processing/ShaderRenderer.swift:76-90`):
`gpuOrCPU` catches ONLY `MetalEffectError` (9 cases, declared in
MetalEffectLibrary.swift) and runs the CPU implementation; any other error type
propagates so genuine bugs are not masked. It prints
`[ShaderRenderer] GPU path ✓` or `[ShaderRenderer] CPU fallback (Metal error: ...)`
per call — several effects logging fallback simultaneously means the Metal
library itself failed to load, not one broken effect.

Note maintainer ruling (2026-07-09): the CPU path is current mechanical reality,
not sacred doctrine — whether to retire it entirely is an OPEN decision owned by
framer-architecture-contract. While the CPU path exists, parity tests must stay
green and new effects need matching CPU semantics.

**Naming trap** (deliberate, don't "fix"): `TextCellRenderer` = GPU front door
for the `.shader` ASCII layer; `TextCellBucketRenderer` = the `.gpuEffect`
bucket dispatcher (header comment explains the split). Same pattern:
`PixelSortRenderer` (shader layer, full params) vs
`GlitchGPURenderer.renderPixelSort` (bucket, leaner `GlitchParameters`,
spanMode fixed to 0); `EdgeFieldRenderer` (dispatcher + CPU) vs
`EdgeFieldGPURenderer`; `PrintSamplingRenderer` vs `PrintSamplingGPURenderer`.

## Shader loading order (MetalEffectLibrary)

`MetalEffectLibrary.init` (`Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift`):

1. Try `device.makeDefaultLibrary(bundle: Bundle.module)` — works under **Xcode
   builds**, where SPM's per-file `.process` rules compile the `.metal` files
   into a `default.metallib` inside Bundle.module.
2. Else (plain `swift build` / `swift test` / FramerCLI, where SwiftPM 5.10 just
   copies the `.metal` files verbatim): read `ShaderCommon.h` from the bundle,
   concatenate it with ALL `.metal` text resources (stripping each file's
   `#include "ShaderCommon.h"` line), and compile the combined source at runtime
   via `makeLibrary(source:)`.

Consequences you must respect:

- **`_EffectTemplate.metal` must stay in `exclude:` in Package.swift.** If it
  ships as a resource, the concatenated runtime compile breaks on its TODO
  scaffold.
- **No duplicate symbols across `.metal` files.** They are compiled as ONE
  translation unit in the fallback path; two files defining the same helper
  function compile fine in Xcode but fail at runtime under `swift test`.
- **Every new `.metal` file needs its own `.process("Effects/Metal/X.metal")`
  entry in Package.swift.** The directory form `.process("Effects/Metal")` is a
  known SPM gotcha — it copies the files opaquely instead of compiling a
  metallib (documented in the Package.swift comment).
- Pipelines are cached per fragment-function name; the color attachment is
  always `.rgba8Unorm`. Two samplers exist: `nearestClamp()` (pixel-perfect
  atlas/span reads) and `linearClamp()` (smooth source sampling).

## Uniform discipline (the #1 way to corrupt output)

A Swift struct is copied byte-for-byte into the shader's uniform buffer, so the
Swift and MSL layouts must be identical.

1. **Mirror field-for-field with explicit padding.**
   `Sources/FramerCore/Effects/GPU/SharedUniforms.swift` provides Swift mirrors
   of the ShaderCommon.h structs (`FramerCommonUniformsLayout`,
   `FramerGeometryUniformsLayout`, `FramerColorUniformsLayout`). Rules from that
   file: field order, types, and explicit `_pad` fields must match the MSL
   structs exactly; `SIMD4<Float>` is 16-byte aligned in both languages, so
   `_pad` fields exist wherever alignment demands them; **when you change the C
   header, change the Swift mirror in the same patch.**
2. **ALWAYS encode with `uniformBytes(_:)`**
   (`Sources/FramerCore/Effects/GPU/MetalUniformEncoding.swift`), never
   `withUnsafeBytes(of:) { Data($0) }`. Metal's debug validation checks the
   buffer length against the MSL struct's ALIGNMENT-ROUNDED STRIDE, not its
   content size. A 152-byte struct containing a `float4` has stride 160; passing
   `MemoryLayout<T>.size` bytes trips this exact validation error (quoted in
   the file header):

   > Fragment Function(x): argument uniforms[0] from Buffer(0) with offset(0)
   > and length(152) has space for 152 bytes, but argument has a length(160).

   `uniformBytes` returns `Data` of `MemoryLayout<T>.stride` bytes, zero-padded.
3. **Shared numeric constants duplicated Swift/MSL must change together.**
   Canonical example: `GlitchGPURenderer.maxSpanWalk = 1024`
   (GlitchGPURenderer.swift:23) ↔ `PIXEL_SORT_MAX_WALK = 1024`
   (PixelSort.metal:31) — also consumed by the CPU path in GlitchRenderer.
   Another: the dither palette cap is duplicated across `Dither.metal`
   (`DITHER_MAX_PALETTE`), `DitherGPURenderer`, and the model type.

Symptom of layout drift: garbled colors that do NOT respond to parameter
changes, or the validation error above. Full incident story: see
framer-failure-archaeology.

## Texture upload and readback

**Upload** — `MetalTextureSupport.makeTexture(from:device:)`:

- Every `CGImage` first goes through `normalizedForTextureUpload`: a strict
  fast path that returns the image unchanged ONLY if it is exactly 8-bit,
  32-bpp, `bitmapInfo.rawValue == CGImageAlphaInfo.premultipliedLast.rawValue`
  (exact equality — no extra byte-order/pixel-format flags), RGB color model.
  Anything else is redrawn through a canonical premultipliedLast RGBA8
  `CGContext`. WHY: `MTKTextureLoader` internally attempts
  `CGBitmapContextCreate` with the source's native alpha info; certain PNG/HEIC
  decodes arrive as `.alphaLast` (rejected) or `.premultipliedLast |
  kCGImagePixelFormatPacked` (slipped past an earlier alpha-mask-only check),
  and the loader silently falls back to a path producing visibly wrong colors.
  Two successive fixes hardened this — copy this normalization pattern in any
  new pixel-path code.
- Loader options: `.SRGB: false` (byte values pass through unchanged — shaders
  operate on nonlinear sRGB values unless they explicitly linearize),
  `.textureUsage: shaderRead`, `.textureStorageMode: private`.

**Readback** — `MetalTextureSupport.makeCGImage(from:)`:

- The shared `fullscreenVertex` maps clip space to texture space with a Y-flip
  (its uv table is `(0,1),(2,1),(0,-1)`); readback undoes this by orienting the
  `CIImage` `.downMirrored` before rendering through a shared `CIContext`
  (workingColorSpace deviceRGB, outputColorSpace sRGB) to RGBA8. If your output
  is upside-down you bypassed this helper.

**Command buffer status** — `MetalRenderPass.encode` calls `commit()` +
`waitUntilCompleted()` (synchronous), then throws
`MetalEffectError.commandEncodingFailed` if `commandBuffer.status != .completed`.
Without this check a driver-level GPU error returns garbage pixels that the
caller treats as success (that happened; fixed in MetalRenderPass.swift:88-90).

## Render-pass anatomy (worked example: GlitchGPURenderer.renderPixelSort)

Every bucket GPU renderer is the same ~7 steps. Read
`Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift:119-191` alongside:

1. `guard let library = MetalEffectLibrary.shared else { throw MetalEffectError.metalUnavailable }`
   — the shared singleton owns the `MTLDevice`, `MTLCommandQueue`, compiled
   `MTLLibrary`, pipeline cache (keyed by fragment name), and both samplers.
2. `let pipeline = try library.pipeline(for: "pixelSortFragment")` — builds or
   returns the cached pipeline (vertex stage always `fullscreenVertex`).
3. Pick a sampler deliberately: here `nearestClamp()` because span detection
   compares per-pixel luminance and bilinear filtering would smear span
   boundaries (comment at GlitchGPURenderer.swift:135-137).
4. `let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)`.
5. Fill the uniform mirror struct (`PixelSortUniforms`, declared in-file with
   the shared layout blocks first, then bucket fields, then `_pad0/_pad1`).
   Note the bridging: `GlitchParameters.streakLength` (a 0..1 dial) becomes
   `spanCap = clamp(streak² × sort-axis-dimension, 1, maxSpanWalk)` so streaks
   are resolution-relative; `amount` maps to the shader's `intensity` mix
   factor (matching CPU blend semantics — see the pixel-sort parity incident,
   commit f21a6fe, in framer-failure-archaeology).
6. `let uniformData = uniformBytes(uniforms)`.
7. `MetalRenderPass.encode(pipeline:source:auxTextures:sampler:uniformBytes:outputSize:library:)`
   → draws 3 vertices into a fresh private `.rgba8Unorm` render target (cleared
   to black; uniforms go through `setFragmentBytes`, so keep them ≤ 4 KB; aux
   textures bind at fragment slots 1+, source at slot 0, sampler at slot 0) →
   `MetalTextureSupport.makeCGImage(from: outputTexture)`.

## CHECKLIST: adding a new GPU effect end-to-end

Work through every row; a skipped row is a shipped bug (each row maps to a past
incident).

- [ ] Copy `Sources/FramerCore/Effects/Metal/_EffectTemplate.metal` →
      `<Bucket>.metal`; fill the TODOs; cite any Grainrad-studied technique in
      the header (template mandates it). No symbol may collide with any other
      `.metal` file (single-translation-unit runtime compile).
- [ ] Add `.process("Effects/Metal/<Bucket>.metal")` to Package.swift resources
      (per-file — never the directory form). Leave `_EffectTemplate.metal` in
      `exclude:`.
- [ ] Define the MSL uniform struct (shared blocks first: common, geometry,
      color) and its Swift mirror with explicit `_pad` fields; same field order
      and types. Encode with `uniformBytes()`.
- [ ] Write the Swift GPU renderer following the 7-step anatomy above; choose
      the sampler deliberately (nearest for span/atlas/integer-grid reads,
      linear for smooth image sampling).
- [ ] Porting a CPU integer-pixel loop? **Pin uv to the pixel grid**:
      `int2 pixel = int2(floor(in.uv * resolution))` then derive coordinates
      from `pixel`, not raw `in.uv`. `in.uv` arrives at fragment CENTERS
      (half-texel offset); Halftone drifted ~half a dot (mean parity delta
      32/255) before this fix — see the comment block in Halftone.metal:60-66.
- [ ] Add the `GPUEffectKind` case
      (`Sources/FramerCore/Effects/Models/GPUEffectKind.swift`): `label`,
      `menuIcon`, `makeDefaultLayer()` defaults, and the four capability flags
      (`usesGeometry`, `usesColorModeAndFgBg`, `usesBackgroundIntensity`,
      `usesCommonAdjustments`) so the UI only shows controls the shader reads
      (dead-slider incidents: framer-failure-archaeology; full parameter
      catalog: framer-config-and-flags). Decide `userFacingCases` visibility.
- [ ] Wrap your source sample in `applyCommonAdjustments(...)` from
      ShaderCommon.h if (and only if) you set `usesCommonAdjustments = true`.
- [ ] While the CPU path exists (open decision — framer-architecture-contract):
      implement the CPU counterpart with IDENTICAL semantics — same scoring
      formulas, same blend interpretation, same constants. The pixel-sort
      `amount` divergence (rank-scaling on CPU vs mix-blend on GPU, commit
      f21a6fe) is the cautionary tale.
- [ ] Add a parity test to `Tests/FramerCoreTests/EffectGPUParityTests.swift`
      (27 tests as of 2026-07-09; mean/max per-channel delta tolerances,
      self-skipping when Metal is unavailable). Run
      `swift test --filter EffectGPUParityTests`.
- [ ] Wire the UI: macOS controls in
      `Sources/FramerApp/Editor/LayerListSection.swift` (gates blocks on the
      capability flags, see lines ~325-380); iOS controls in
      `Sources/FramerMobile/Layers/LayerDetailView.swift` (`GPUEffectControls`)
      and the add-picker in `Sources/FramerMobile/Layers/LayerStrip.swift`.
      As of 2026-07-09 the iOS controls do NOT consult capability flags —
      only macOS prunes; check before assuming parity.
- [ ] `swift build && swift test`, then remember the metallib caveat below.

## Validation caveat: what `swift test` does NOT prove

Under `swift test`, MetalEffectLibrary compiles shaders from concatenated
SOURCE at runtime. The Xcode-built path — SPM-driven metallib compilation, plus
Xcode's Metal validation layers — is only exercised by building/testing through
the Xcode 'Framer' scheme. That app-test tier is broken on this machine as of
2026-07-09 (revoked signing certificate — `CSSMERR_TP_CERT_REVOKED`, not merely
expired — plus missing Metal Toolchain component);
repairing it is the framer-campaign-restore-validation campaign. Until then, a
shader that compiles at runtime could still fail the offline metallib compile
(e.g. stricter diagnostics), so treat green `swift test` as necessary, not
sufficient, for shader changes. Evidence standards: framer-validation-and-qa;
measuring output instead of eyeballing: framer-diagnostics-and-proof.

## Quick smoke signals

| Observation | Meaning | First move |
|---|---|---|
| Console shows `[ShaderRenderer] CPU fallback (Metal error: ...)` for MANY effects at once | Metal library failed to load (bad .metal file breaks the combined runtime compile, or missing resources) | Check `MetalEffectLibrary: makeLibrary failed:` in the log; compile-error text names the offending line |
| Garbled colors, parameter-insensitive | Swift/MSL uniform layout drift | Diff the Swift mirror against the MSL struct field-by-field, check `_pad` fields |
| Validation error "...has space for N bytes, but argument has a length(M)" | Encoded `size` instead of `stride` | Use `uniformBytes()` |
| Wrong colors only for some HEIC/PNG inputs | Upload normalization bypassed | Route through `MetalTextureSupport.makeTexture` |
| Output upside-down | Readback bypassed `.downMirrored` | Use `MetalTextureSupport.makeCGImage` |
| GPU output shifted ~half a cell vs CPU | uv-at-fragment-centers phase bug | Pin to `floor(uv * resolution)` |

(Deeper triage lives in framer-debugging-playbook.)

## Provenance and maintenance

All facts verified 2026-07-09 against commit 48d85a5 by reading the cited files
and running `swift test --filter EffectGPUParityTests` (27 tests, 0 failures,
Apple Silicon).

Re-verification one-liners for facts that may drift:

```bash
# .metal file inventory + per-file .process entries + template exclusion
ls Sources/FramerCore/Effects/Metal/ && grep -n "process\|exclude" Package.swift
# Fragment entry points per file
grep -n "^fragment\|^vertex" Sources/FramerCore/Effects/Metal/*.metal
# Fallback contract (MetalEffectError-only) + log strings
grep -n "MetalEffectError\|GPU path\|CPU fallback" Sources/FramerCore/Processing/ShaderRenderer.swift
# Dual loading path (metallib vs runtime source compile)
grep -n "makeDefaultLibrary\|makeLibrary(source" Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift
# Uniform stride rule + exact validation error string
sed -n '1,20p' Sources/FramerCore/Effects/GPU/MetalUniformEncoding.swift
# Upload normalization fast path + SRGB:false + .downMirrored readback
grep -n "premultipliedLast\|SRGB\|downMirrored" Sources/FramerCore/Effects/GPU/MetalTextureSupport.swift
# Command-buffer status check
grep -n "status != .completed" Sources/FramerCore/Effects/GPU/MetalRenderPass.swift
# Shared constant sync
grep -n "maxSpanWalk" Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift Sources/FramerCore/Effects/Renderers/GlitchRenderer.swift && grep -n "PIXEL_SORT_MAX_WALK" Sources/FramerCore/Effects/Metal/PixelSort.metal
# Capability flags + hidden picker cases
grep -n "userFacingCases\|usesGeometry\|usesCommonAdjustments" Sources/FramerCore/Effects/Models/GPUEffectKind.swift
# iOS still not flag-pruning?
grep -rn "usesCommonAdjustments" Sources/FramerMobile/ || echo "iOS: still no flag pruning"
# Parity suite health + count
swift test --filter EffectGPUParityTests 2>&1 | tail -3
# LUT compute stack (embedded source, formats, threadgroups)
grep -n "makeLibrary(source\|rgba32Float\|rgba8Uint\|threadExecutionWidth" Sources/FramerCore/Processing/LUTMetalRenderer.swift
```
