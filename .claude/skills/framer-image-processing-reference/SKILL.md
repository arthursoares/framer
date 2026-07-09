---
name: framer-image-processing-reference
description: Domain theory for Framer's pixel math — load when touching color spaces, luminance/luma coefficients, dithering (ordered, error-diffusion, IGN approximation, Riemersma, palettes), pixel sort (spans, sort keys, streak), overlay blending (luminance-deviation alpha, deadband), LayerCompositor blend modes (multiply/screen/HSL/etc.), or .cube LUT parsing/trilinear interpolation. Also load when GPU and CPU outputs of the same effect disagree, when a "wrong brightness/gray/hue" bug appears, or when editing Dither.metal, PixelSort.metal, ShaderCommon.h, BorderRenderer, LayerCompositor, CubeFileParser, or LUTMetalRenderer.
---

# framer-image-processing-reference

The image-processing math AS USED IN THIS REPO, for someone who has never done pixel work. Formulas here are transcribed from the shipped code, with file:line citations (as of 2026-07-09, commit 48d85a5). When a code comment and the code disagree, this skill says so — trust the executable statement.

**When NOT to use this skill:**

| You need... | Go to |
|---|---|
| Metal plumbing: shader loading, uniform structs/padding, texture upload/readback mechanics, render pass, adding a GPU effect | framer-metal-pipeline-reference |
| Which parameters exist per layer, capability flags, preset schemas | framer-config-and-flags |
| A symptom→triage table for "effect looks wrong" | framer-debugging-playbook |
| Full incident stories behind the fixes cited here | framer-failure-archaeology |
| Measuring image differences instead of eyeballing | framer-diagnostics-and-proof |
| Whether the CPU fallback path should exist at all (open question) | framer-architecture-contract |

---

## 1. Color-space conventions

### 1.1 The passthrough contract

Framer does almost NO color management. Pixels are 8-bit sRGB-encoded bytes and stay that way through the whole pipeline:

- **Canonical buffer format**: RGBA8, `CGImageAlphaInfo.premultipliedLast`, device RGB. Every CPU processing stage rasterizes into this layout (e.g. `Sources/FramerCore/Processing/LayerCompositor.swift:58-72`, `Sources/FramerCore/Processing/BorderRenderer.swift:650-672`). GPU uploads are normalized to exactly this format first — `Sources/FramerCore/Effects/GPU/MetalTextureSupport.swift:88`.
- **GPU upload is non-color-managed**: `MTKTextureLoader` is called with `.SRGB: false` (`MetalTextureSupport.swift:63-67`), so a byte value of 186 arrives in the shader as `186/255 ≈ 0.729` — the *encoded* value, not linear light. Shaders therefore operate on **nonlinear sRGB values** unless they explicitly linearize.
- **Readback** goes through a shared `CIContext` with sRGB output color space and a `.downMirrored` orientation fix (`MetalTextureSupport.swift:34-38, 183-195`) — mechanics owned by framer-metal-pipeline-reference.

Practical consequence: math like `base * over` (multiply blend) is being done on gamma-encoded values. That is *deliberate* — it matches Photoshop's default non-linearized blending, and CPU/GPU stay consistent because both skip linearization.

### 1.2 The ONE gamma-correct exception: mono dither

Monochrome dithering converts to linear light before thresholding, in both paths:

- GPU: `sRGBToLinear` (piecewise sRGB EOTF: `c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055, 2.4)`) then Rec.709 linear luminance `dot(rgb, (0.2126, 0.7152, 0.0722))` — `Sources/FramerCore/Effects/Metal/Dither.metal:373-385`.
- CPU: `sRGBToLinearLUT` table + the same 0.2126/0.7152/0.0722 weights — `Sources/FramerCore/Processing/DitherRenderer.swift:38,405`.

Why: without linearization, thresholding at 0.5 on encoded bytes biases output toward white — sRGB byte 186 is perceptual "mid-gray" (≈0.5 linear) but encodes as 0.729. Fixed in commit `a757e67`. Per-channel-levels and palette dither modes **intentionally stay nonlinear** (they quantize the encoded values directly, `Dither.metal:441-501`).

### 1.3 THREE luminance standards coexist — do not mix them

"Luminance"/"luma" = a weighted sum of R,G,B approximating perceived brightness. Framer uses three different weight sets on purpose. Copying a formula from the wrong subsystem produces subtle brightness/threshold drift that survives eyeballing but fails parity tests.

| Standard | Weights (R, G, B) | Space | Used by | Evidence |
|---|---|---|---|---|
| Rec.601 | 0.299, 0.587, 0.114 | nonlinear sRGB | All GPU effects (`luminance()` in ShaderCommon.h), overlay strength masks, CPU shader-layer pixel sort | `Sources/FramerCore/Effects/Metal/ShaderCommon.h:39-41`; `BorderRenderer.swift:786-790`; `ShaderPixelSortRenderer.swift:76-81` |
| Rec.709 (nonlinear) | 0.2126, 0.7152, 0.0722 | nonlinear sRGB | LayerCompositor HSL blend modes (hue/saturation/color/luminosity); CPU bucket pixel-sort sort key | `LayerCompositor.swift:236-239`; `Effects/Renderers/GlitchRenderer.swift:270-271` |
| Rec.709 (linear) | 0.2126, 0.7152, 0.0722 | linear light | Mono dither threshold comparison only | `Dither.metal:383-385`; `DitherRenderer.swift:38,405` |

Why the split exists: Rec.601 is what the Grainrad-derived effect shaders and Kim Asendorf's pixel-sort lineage use; SVG 1.1 §15.7 (the spec LayerCompositor's HSL modes implement) mandates 0.2126/0.7152/0.0722; the linear-dither fix required physically meaningful luminance.

**Known wrinkle** (verified 2026-07-09): the *bucket* pixel-sort CPU fallback scores `.luminance` with Rec.709 (`GlitchRenderer.swift:270-271`) while the GPU shader's default sort key is Rec.601 (`PixelSort.metal:137` → `ShaderCommon.h:39`). The delta is small enough to sit inside the parity-test tolerances, but if you tighten tolerances or chase exact parity, this is a real divergence. The *shader-layer* CPU path (`ShaderPixelSortRenderer.swift:81`) correctly uses Rec.601.

### 1.4 Premultiplied alpha rules

Premultiplied alpha = RGB channels are stored already multiplied by A (a 50%-opaque red stores as (0.5, 0, 0, 0.5)). Framer's canonical `premultipliedLast` means transparent pixels rasterize as **black with alpha 0** — which is why the overlay mask must be gated by the real alpha channel (§4), and why any code that reads RGB from a buffer with meaningful transparency must consider A. LayerCompositor and the overlay blender never modify the alpha channel; they only rewrite RGB (`LayerCompositor.swift:105-106`).

---

## 2. Dithering as implemented

### 2.1 Primer: two families

Dithering = reducing color depth (e.g. to 1-bit black/white or a 16-color palette) while using pixel patterns to simulate intermediate tones.

- **Ordered dithering** compares each pixel against a fixed, tiled threshold matrix (Bayer matrices, clustered-dot halftone screens). Each pixel is independent → trivially parallel → GPU-native.
- **Error diffusion** (Floyd–Steinberg, Atkinson, Stucki, Sierra, Jarvis-Judice-Ninke, Burkes…) quantizes pixels one at a time and pushes each pixel's quantization error onto not-yet-visited neighbours. Every pixel *depends on the pixels processed before it* — a serial data dependency. **This cannot run in a fragment shader**, where all pixels evaluate independently and no pixel can see another's error.

### 2.2 The GPU approximation: Interleaved Gradient Noise (IGN)

The GPU path (`Dither.metal`, fragment `ditherFragment`) approximates each error-diffusion algorithm with a procedural blue-noise-like threshold — Jimenez's IGN function, `fract(52.9829189 * fract(dot(pos, (0.06711056, 0.00583715))))` (`ShaderCommon.h:107-109`). Per algorithm:

```
threshold = clamp(userThreshold + (ign(pixelPos + PHASE) - 0.5) * COEF, 0, 1)
```

Two per-algorithm knobs make the variants actually distinct (`Dither.metal:241-286`):

| Algorithm | COEF (amplitude) | PHASE (x, y) |
|---|---|---|
| floydSteinberg | 0.85 | (7.31, 11.17) |
| stucki | 0.80 | (13.49, 17.83) |
| atkinson | 0.75 | (19.71, 23.59) |
| artisticDrip | 0.65 | (29.13, 31.07) |
| sierra | 0.84 | (37.41, 41.97) |
| sierraTwoRow | 0.74 | (43.27, 47.51) |
| sierraLite | 0.64 | (53.69, 59.13) |
| jarvisJudiceNinke | 0.90 | (61.83, 67.29) |
| burkes | 0.83 | (71.57, 73.93) |
| interleavedGradientNoise | — (pure IGN) | (83.11, 89.47) |

So amplitudes span **0.64–0.90**: bigger COEF → broader noise spread → coarser look, tracking how much error the serial kernel diffuses. Coefficients were eyeballed against the CPU output on representative photos, not derived (file-header comment, `Dither.metal:14-23`).

**Incident** (commit `2a2ecba`): before the PHASE offsets, all IGN variants sampled the noise field at the same position and several algorithms produced **byte-identical output** despite different names. Every new IGN-based algorithm needs its own phase.

**Comment-drift warning**: the ID table in the file header (`Dither.metal:43-61`) lists sierra as 0.85, sierraTwoRow 0.75, sierraLite 0.65, burkes 0.85 — the *switch statement* (lines 267-285) says 0.84/0.74/0.64/0.83. The switch is what executes; the table above transcribes the switch.

Non-IGN algorithms in the same shader: `bayer` (procedural bit-interleave construction, `bayerLevel` 1–4 → matrix size 4/8/16/32, `Dither.metal:133-154`), `halftone` (hard-coded 6×6 clustered-dot matrix, lines 161-172), `whiteNoise` (uncorrelated hash, lines 194-199), `cmykHalftone` (the 6×6 screen rotated per CMYK channel at 15°/75°/0°/45°, lines 174-186 — CPU deliberately degrades to monochrome for this one; accepted divergence, no parity test).

### 2.3 Riemersma is CPU-only, on purpose

Riemersma dithering walks a Hilbert space-filling curve carrying an error history — even less parallelizable than raster error diffusion. The GPU wrapper deliberately throws `MetalEffectError.metalUnavailable` for it (`Sources/FramerCore/Effects/Renderers/DitherGPURenderer.swift:150-153`), which is the one error type that triggers the CPU fallback (`Sources/FramerCore/Processing/ShaderRenderer.swift:76-90`). Do not "fix" this by adding a GPU case; the throw *is* the design.

### 2.4 CPU error diffusion: serpentine scanning

The real error-diffusion implementations live in `Sources/FramerCore/Processing/DitherRenderer.swift`. All of them use **serpentine (boustrophedon) scanning** — alternate rows are traversed right-to-left with the diffusion kernel mirrored — to avoid the diagonal "worm" banding that fixed-direction scanning produces (`DitherRenderer.swift:14-15`, generic driver at line 770).

### 2.5 Threshold contract: higher = brighter

The user-facing Threshold slider (0.1–0.9 after clamping, `DitherGPURenderer.swift:193`) contractually means "higher threshold → brighter output". But the raw comparison `step(t, lum)` yields *fewer* whites as t rises. Consumers resolve this differently (`Dither.metal:211-220`):

- `ditherMono` inverts at the call site: `step(1.0 - threshold, lum)` (`Dither.metal:397`).
- `quantizeChannel` uses `(threshold - 0.5) / steps` as an additive offset, which already matches the contract (`Dither.metal:410-418`).

If you add a threshold consumer, honour the contract; `thresholdForAlgorithm` is deliberately identity-in-identity-out so each consumer applies its own inversion.

### 2.6 Palette mode: a 16-color cap synchronized in THREE places

Max palette size is 16, declared independently and required to move together:

1. `DITHER_MAX_PALETTE = 16` — `Dither.metal:93`
2. `DitherGPURenderer.MAX_PALETTE_COLORS = 16` — `DitherGPURenderer.swift:69`
3. `DitherColorMode.MAX_PALETTE_COLORS = 16` — `Sources/FramerCore/Models/CompositionLayer.swift:577`

Nearest-match is squared Euclidean distance in 0–1 sRGB RGB (`Dither.metal:314-330`). Before matching, the source is jittered per channel by the algorithm's noise (strength 0.10, decorrelated channel offsets (13,7)/(31,19)) so neighbours can pick adjacent palette entries — this is what makes Game Boy/NES palettes look painterly instead of flat-posterized (`Dither.metal:441-479`). `dominantTwoTone` mode resolves its two colors CPU-side via `ColorExtractor` and hands the shader flat fg/bg (`DitherGPURenderer.swift:182-187`).

### 2.7 Pixel-scale contract (chunky pixels)

Both paths: downscale source to work resolution with `.high` interpolation → dither at work resolution → upscale back with `.none` (nearest-neighbour) so dither cells become crisp blocks (`DitherGPURenderer.swift:160-180, 246-251`; CPU equivalent `DitherRenderer.swift:200, 274`). Preview/export agreement comes from rescaling `pixelScale` by `currentMax / previewBaseDimension` (`DitherGPURenderer.swift:161-165`). Break this and preview and export show different-sized dither cells.

---

## 3. Pixel sort mechanics

Pixel sorting = finding runs ("spans") of adjacent pixels along a line that satisfy a predicate, then reordering the pixels within each span by a sort key. Lineage: Kim Asendorf's Processing sketch.

### 3.1 CPU vs GPU strategy

- **CPU** (`Sources/FramerCore/Processing/ShaderPixelSortRenderer.swift` for the shader layer; `Sources/FramerCore/Effects/Renderers/GlitchRenderer.swift` for the bucket): serial sweep per row/column — find span, sort *every* pixel in it exactly.
- **GPU** (`Sources/FramerCore/Effects/Metal/PixelSort.metal`, from Grainrad's per-fragment design): every fragment independently
  1. walks backward then forward along the sort axis to find its enclosing span, bounded by `PIXEL_SORT_MAX_WALK = 1024` steps and the span cap (`PixelSort.metal:31, 196-229`);
  2. samples at most `PIXEL_SORT_SAMPLE_COUNT = 24` evenly-strided positions across the span (`PixelSort.metal:30, 231-254`);
  3. bubble-sorts those ≤24 samples in registers (fixed bounds → fully unrollable, `PixelSort.metal:256-272`);
  4. returns the color at its own proportional rank, blended: `mix(original, sorted, intensity)` where `intensity` is Swift-premultiplied `params.intensity * amount` (`PixelSort.metal:274-288`).

Consequence: spans ≤ 24 px match CPU within float tolerance; **longer spans are sub-sampled and look coarser on GPU** — an accepted approximation. The per-fragment walk is O(span), so span caps exist for performance, not correctness.

### 3.2 Span predicates (spanMode) and sort keys (sortBy) — orthogonal axes

Span predicate — does this pixel belong to a sortable run? (`PixelSort.metal:95-108`, CPU mirror `ShaderPixelSortRenderer.swift:142-151`):

| spanMode | Predicate |
|---|---|
| 0 luminance (default) | `lum601(c) >= threshold` |
| 1 kimBlack | `lum601(c) > threshold * 0.25` |
| 2 kimWhite | `lum601(c) < 1 - threshold * 0.25` |
| 3 kimBright | `maxRGB(c) > threshold` |
| 4 kimDark | `maxRGB(c) < threshold` |

Sort key — what pixels are *ranked* by inside the span (`PixelSort.metal:116-139`):

| sortBy | Definition |
|---|---|
| 0 luminance | Rec.601 luma |
| 1 brightness | `max(r, g, b)` — Kim Asendorf's choice; preserves saturated colors |
| 2 hue | HSV hue sector `h/6`, with negative wrap `h < 0 → h + 1` so the result is in [0, 1) |

**Parity bug history** (the reason those definitions are spelled out in code comments, `GlitchRenderer.swift:251-264`):
- Commit `761fae6`: CPU `.brightness` had returned Rec.709 luminance (identical to `.luminance`), and CPU `.hue` returned the raw HSV sector in [-1, 6) — negative (blue-dominant) scores fell below every threshold and whole hue ranges never sorted. Both now match `psSortValue`.
- Commit `f21a6fe`: CPU had used `amount` as sort-*rank* scaling (amount=0 rendered the darkest 20% of spans!) while the GPU used it as a mix blend factor. CPU was rewritten to shader `mix` semantics. Lesson: for any new effect, CPU-fallback semantic parity is part of the definition of done.

Other conventions that keep CPU/GPU aligned: per-line threshold jitter is the identical recipe on both — `fract(sin(lineCoord * 0.173) * 43758.5453)` (`PixelSort.metal:144-149`); directions are horizontal / vertical / diagonal with `lineCoord = y / x / x - y` (`PixelSort.metal:154-166`); pixel sort uses a **nearest-neighbour** sampler because bilinear filtering would smear the luminance values that span boundaries depend on (`Effects/Renderers/GlitchGPURenderer.swift:137`).

### 3.3 Resolution-relative streak (bucket layer)

Since commit `4cf8ec2`, the Glitch bucket's Streak dial (0–1) maps quadratically to a fraction of the image's sort-axis dimension:

```
spanCap = clamp(streak² × sortAxisDimension, 1, 1024)     // GlitchGPURenderer.swift:163-165
```

(`sortAxisDimension` = width for horizontal, height for vertical.) The square keeps fine control in the low band; the result is that preview and full-res export show the *same proportional* streak lengths. `maxSpanWalk = 1024` (`GlitchGPURenderer.swift:23`) matches `PIXEL_SORT_MAX_WALK` in the shader — keep them in lockstep. The bucket fixes `spanMode = 0`; the richer `.shader`-layer pixel sort exposes all span modes.

---

## 4. Overlay blending (BorderRenderer)

Texture overlays (film frames, dust, light leaks, wet-plate textures) are ordinary JPEG/PNG images that encode their own transparency via **luminance-deviation-from-gray**: mid-gray = invisible, far-from-gray = opaque.

### 4.1 The strength mask, exactly as shipped

Implementation: `BorderRenderer.applyOverlay` → `blendWithAccelerate`, fully vDSP-vectorized over raw Float slabs (`Sources/FramerCore/Processing/BorderRenderer.swift:625-698, 726-823`; raw `UnsafeMutablePointer` slabs avoid ~300–400 MB transient heap on 12 MP images, comment at lines 704-708).

```
L = 0.299·R + 0.587·G + 0.114·B                    (Rec.601, nonlinear — lines 786-790)
α = clamp( max(0, |L − 0.5| − 0.005) × 2 × opacity × overlayAlpha, 0, 1 )   (lines 792-809)
result = base + (blend(base, overlay) − base) × α   (lerp; normal mode: blend = overlay)
```

Two hard-won corrections baked into that formula:

- **The 0.005 deadband** (line 803-804): JPEG-authored overlays store "gray" as byte 128 → L ≈ 0.502, not 0.500. Without the deadband, that 1-byte deviation gave every pixel in a frame's "transparent" window a nonzero α and visibly darkened the whole photo. 0.005 ≈ 1/255 of luminance range; real frame ink sits far outside it.
- **Gating by the real alpha channel** (`lum *= overlay.alpha`, line 807, rationale at 744-752): PNG frames with genuine transparency rasterize transparent pixels as premultiplied black (rgb=0, a=0); the luminance mask reads L=0 as *fully opaque dark*. Multiplying by the overlay's alpha zeroes those out. Grayscale JPEG overlays ship with a=1, so it is a no-op for them.

### 4.2 The four blend modes

`OverlayBlendMode` (`Sources/FramerCore/Models/CompositionLayer.swift:267-291`): `normal` (mask-weighted lerp to the overlay pixel — frames, dust), `screen` (`1−(1−b)(1−o)`, only lightens — light leaks), `softLight` (subtle contrast — wet plate), `multiply` (`b·o`, only darkens — vignettes). ALL modes are attenuated by the same luminance-deviation mask, so gray stays transparent regardless of mode (`BorderRenderer.swift:621-623`). Default mode per overlay kind: frame/dust→normal, lightLeak→screen, wetPlate→softLight.

Categories by filename prefix (`CompositionLayer.swift:246-263`): `frame*`→Frame (fallthrough default), `dirt*`→Dust & Scratches, `leak*`→Light Leak, `plate*`→Wet Plate. Sources: `~/Library/Application Support/Framer/overlays/` and an installed Nik Collection directory.

### 4.3 Doc-of-record note

`docs/overlay-blending.md` describes the *intent* correctly (mid-gray = transparent, categories, authoring guide) but is **stale on the math**: it documents a premultiply-and-composite pipeline with no deadband, no alpha-channel gating, and mentions no blend modes. The code above is ground truth. The staleness ledger lives in framer-docs-and-writing; do not edit the doc from here.

---

## 5. LayerCompositor: 20 Photoshop-parity blend modes

`Sources/FramerCore/Processing/LayerCompositor.swift` composites a visual layer's output back onto the pipeline buffer: `result = base·(1−opacity) + blend(base, over)·opacity`, computed as a **scalar per-pixel loop in SIMD3<Double>, on 0–1 nonlinear sRGB, with NO linearization** (lines 85-107). The alpha channel is never modified (lines 105-106). Fast path: `normal` at opacity ≥ 1.0 returns `over` untouched (lines 54-56) — the common case for every default layer.

The 20 modes (`blend(base:over:mode:)`, lines 120-207):

| Tier | Modes | Notes |
|---|---|---|
| RGB | normal, multiply, screen, overlay, hardLight, softLight, difference, exclusion, darken, lighten, colorDodge, colorBurn | overlay/hardLight share one formula with driver/content swapped (lines 216-221); softLight is the **Pegtop** formulation `(1−2o)b² + 2ob` (line 146); dodge/burn are per-channel with division guards (lines 224-231) |
| HSL | hue, saturation, color, luminosity | SVG 1.1 §15.7 formulas: Rec.709 `lum()` (lines 237-239), saturation = channel span max−min (lines 245-247), `setLum` clips out-of-gamut by pulling toward the luminance axis (lines 254-269), `setSat` rescales (min, mid, max) directly (lines 275-296). Matches Photoshop's layer-panel behaviour |
| Technical | subtract, divide, linearDodge, linearBurn | all clamped to [0,1] (lines 191-205) |

Remember §1.3: this file is the Rec.709-nonlinear island. Do not "harmonize" it to Rec.601 — the SVG spec (and Photoshop parity) requires 0.2126/0.7152/0.0722.

---

## 6. LUT layer (.cube format)

A LUT (Look-Up Table) here is a 3D lattice mapping input RGB → output RGB, loaded from Adobe/Resolve `.cube` text files.

### 6.1 Parser tolerances (`Sources/FramerCore/Processing/CubeFileParser.swift`)

- `LUT_3D_SIZE N` required; N must be 2–256 (lines 145-155).
- `DOMAIN_MIN` / `DOMAIN_MAX` supported (default 0..1); min ≥ max per channel is rejected (lines 170-194, 226-230).
- `TITLE` and `#` comments skipped (lines 137-143).
- **1D shaper tables are parsed and skipped**: `LUT_1D_SIZE N` causes the next N data triplets to be consumed and discarded (lines 158-168, 207-210). A .cube with a shaper loads, but the shaper's tone curve is silently NOT applied — flag this if color accuracy versus a reference tool matters.
- Extra data beyond size³ triplets is truncated (line 232).

### 6.2 Trilinear interpolation is implemented TWICE — they must match

Trilinear = look up the 8 lattice corners surrounding the scaled input coordinate and lerp along r, then g, then b.

1. **CPU**: `LUT3D.apply` (`CubeFileParser.swift:19-86`) — scale by `(size−1)/(domainMax−domainMin)`, clamp, 8 corner fetches with indices `b·size² + g·size + r`, three lerp stages.
2. **GPU**: the `applyLUT` compute kernel embedded as a Swift string in `Sources/FramerCore/Processing/LUTMetalRenderer.swift:24-78` — same math, manual corner reads from an `rgba32Float` `.type3D` texture (lines 328-329); input/output are `rgba8Uint` integer textures (line 376); final `mix(color, lutColor, intensity)`.

If you change interpolation, domain handling, or intensity semantics in one, change the other in the same commit. This LUT stack is architecturally independent of the effects Metal stack (own device/queue/pipeline; see framer-metal-pipeline-reference).

Discovery: bundled `.cube` files from `assets/luts` next to the executable (executable-relative lookup is apparently latent in practice — nothing bundles `assets/luts` next to any binary; confirm intent before "fixing", see framer-run-and-operate), plus `~/Library/Application Support/Framer/luts` (`Sources/FramerCore/Processing/LUTProvider.swift:273, 297-299`).

---

## 7. Upstream reference: Grainrad (external dependency of understanding)

Several shaders explicitly credit **Grainrad** (grainrad.com, @almmaasoglu) as the studied reference for their approach patterns — IGN dither approximation, the per-fragment pixel-sort trick, fullscreen-triangle conventions (`ShaderCommon.h:7-10`; `Dither.metal:4-12`; `PixelSort.metal:7-10`). Code comments reference notes files like `grainrad/notes/dithering.md` and a WGSL source (`pixel-sort__GS__L16326.wgsl`) — **those notes and the Grainrad repo are NOT vendored in this repository** (verified: no grainrad files exist here). The comments state no Grainrad code was copied; the MSL was written fresh against documented designs. If you need the upstream rationale, you need access to those external notes — otherwise treat the in-repo comments as the surviving record. "Grainrad-class quality, verified by measurement" is this project's quality bar — see framer-campaign-gpu-effects-quality and framer-research-frontier.

---

## 8. GPU-only rendering, golden-anchored (CPU path retired 2026-07-09)

The CPU effect implementations were retired per docs/adr/2026-07-09-retire-cpu-effect-path.md — `ShaderRenderer.apply` calls the Metal renderers directly and `MetalEffectError` propagates. Exceptions kept by design: Riemersma dither (sole implementation, dispatched by algorithm in `DitherRenderer.apply`), the hidden legacy bucket variants, and the LUT stack's `applyCPU` (oracle + benchmark baseline). Pixel-level regression anchors to `Tests/FramerCoreTests/EffectGPUGoldenTests.swift` (frozen goldens, per-effect mean/max tolerances; refresh discipline = snapshot-hash discipline) plus `EffectGPUBehaviorTests` invariants. When the pixel math in this skill and a golden disagree after a shader edit, the golden is the regression signal — explain the shift before regenerating. To *measure* a divergence instead of eyeballing it, use framer-diagnostics-and-proof.

---

## Provenance and maintenance

All formulas, constants, and line numbers verified against the working tree at commit `48d85a5` on 2026-07-09 by reading the cited files; commits `4cf8ec2`, `f21a6fe`, `761fae6`, `2a2ecba`, `a757e67` verified via `git log --no-walk`. Line numbers drift — re-verify with:

| Fact | Re-verify |
|---|---|
| Rec.601 luminance in effects | `grep -n '0.299' Sources/FramerCore/Effects/Metal/ShaderCommon.h` |
| Rec.709 in LayerCompositor / mono dither | `grep -rn '0.2126' Sources/FramerCore/Processing/LayerCompositor.swift Sources/FramerCore/Effects/Metal/Dither.metal Sources/FramerCore/Processing/DitherRenderer.swift` |
| CPU bucket sort-key luma wrinkle | `grep -n '0.2126' Sources/FramerCore/Effects/Renderers/GlitchRenderer.swift` |
| Upload passthrough (`SRGB: false`) | `grep -n 'SRGB' Sources/FramerCore/Effects/GPU/MetalTextureSupport.swift` |
| IGN coefficient/phase table | `grep -n 'float2(pos) + float2' Sources/FramerCore/Effects/Metal/Dither.metal` |
| Threshold inversion in mono dither | `grep -n 'step(1.0 - threshold' Sources/FramerCore/Effects/Metal/Dither.metal` |
| Riemersma forced CPU fallback | `grep -n -B2 'metalUnavailable' Sources/FramerCore/Effects/Renderers/DitherGPURenderer.swift` |
| Palette cap ×3 | `grep -rn 'MAX_PALETTE' Sources/FramerCore/Effects/Metal/Dither.metal Sources/FramerCore/Effects/Renderers/DitherGPURenderer.swift Sources/FramerCore/Models/CompositionLayer.swift` |
| Pixel-sort constants 24 / 1024 | `grep -n 'PIXEL_SORT_SAMPLE_COUNT\|PIXEL_SORT_MAX_WALK' Sources/FramerCore/Effects/Metal/PixelSort.metal` |
| Streak² span formula | `grep -n 'streakLength \* params.streakLength' Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift` |
| Overlay deadband + alpha gate | `grep -n 'negDeadband\|overlay.alpha' Sources/FramerCore/Processing/BorderRenderer.swift` |
| 20 blend modes / SVG HSL | `grep -c 'case \.' Sources/FramerCore/Processing/LayerCompositor.swift` and read `blend()` |
| .cube size bounds + 1D skip | `grep -n 'parsedSize >= 2\|LUT_1D_SIZE' Sources/FramerCore/Processing/CubeFileParser.swift` |
| Grainrad still not vendored | `find . -maxdepth 2 -iname '*grainrad*'` (expect only source-comment hits via grep, no files) |
| Golden + behavior suites still green | `swift test --filter EffectGPUGoldenTests` ; `swift test --filter EffectGPUBehaviorTests` (self-skip without Metal) |
