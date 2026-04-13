# GPU Effects — parameter matrix per variant

Reference for the per-variant UI pruning work. For each of the 11 user-facing `.gpuEffect` bucket variants, lists exactly which parameters the GPU shader reads (keep in UI) vs which are silently ignored (hide from UI).

Derived by reading every Metal shader + renderer wrapper at branch tip `7a72800`.

## Bucket-system status at time of writing

**User-facing variants** (`GPUEffectKind.userFacingCases`):
- TextCell bucket: `dots`, `blockify`, `matrixRain`
- PrintSampling bucket: `threshold`, `crosshatch`
- EdgeField bucket: `edgeDetection`, `contour`, `waveLines`, `voronoi`, `noiseField`
- Glitch bucket: `vhs`

**Hidden from picker** (duplicates of `.shader` / `.dither` layers): `ascii`, `halftone`, `pixelSort`, `dithering`.

**GPU-accelerated**: dots, blockify, threshold, crosshatch, edgeDetection, contour, waveLines, voronoi, noiseField.
**Still CPU only**: matrixRain, vhs.

---

## The global control blocks

Every variant is rendered through `GPUEffectParameters.<bucket>(common, geometry, color, payload)`. The UI today exposes all three of the shared blocks (common, geometry, color) for every variant. This table tells you whether a given shader actually reads each block's fields.

| Block | Fields | Read by any GPU-ported bucket variant? |
|---|---|---|
| `common` | brightness, contrast, saturation, hueRotation, sharpness, gamma | **No** — none of the bucket shaders apply these. The `.shader` family uses them (Crimewave / CRT / Kuwahara / etc.) but the bucket shaders were designed as standalone pattern generators. |
| `geometry` | scale, spacing, outputWidth | **Partial** — scale+spacing used by TextCell.dots + TextCell.blockify only. outputWidth never read. |
| `color` | mode, backgroundIntensity, foregroundRGBA, backgroundRGBA | **Partial** — mode + fg/bg used by TextCell.dots, TextCell.blockify, PrintSampling.threshold, PrintSampling.crosshatch. backgroundIntensity used by EdgeField variants as a general "paper level". |

Net recommendation: **hide the entire `common` block for every bucket variant** unless/until shaders are extended to consume it. Hide `geometry.outputWidth` everywhere. Keep scale+spacing only on TextCell variants. Keep color block only on variants that render an fg/bg mask (the ones listed above).

---

## TextCell bucket

Pipeline: `textCellFragment` (one pipeline, variant branch inside). Payload: `TextCellParameters`.

### dots (variant=0, GPU)

**Used** (keep in UI):
- `geometry.spacing` → cell pitch
- `geometry.scale` → cell pitch multiplier (wired 7a72800)
- `color.mode` → flat-fg-vs-per-cell-source colour
- `color.foregroundRGBA`, `color.backgroundRGBA`, `color.backgroundIntensity`
- `params.dotShape` (circle / square / diamond)
- `params.gridType` (square / hex)
- `params.intensity` (blend with original)
- `params.invert`
- `params.foreground`, `params.background` (override color block)

**Ignored** (hide from UI when kind == .dots):
- Everything in `common` (brightness / contrast / saturation / hue / sharpness / gamma)
- `geometry.outputWidth`
- `params.characterSet` (ASCII-specific)
- `params.speed`, `params.trailLength`, `params.direction`, `params.glow`, `params.backgroundOpacity`, `params.threshold`, `params.rainColor` (MatrixRain-specific)
- `params.blockStyle`, `params.borderWidth`, `params.borderColor` (Blockify-specific)

### blockify (variant=1, GPU)

**Used**:
- `geometry.spacing`, `geometry.scale` (wired 7a72800)
- `color.mode`, `color.foregroundRGBA`, `color.backgroundRGBA`
- `params.blockStyle` (solid / outlined)
- `params.borderWidth`
- `params.intensity`
- `params.foreground`, `params.background`

**Ignored**: everything in `common`, `geometry.outputWidth`, `params.characterSet`, MatrixRain fields, Dots `dotShape`/`gridType`, `params.invert` (not currently read but could be), `params.borderColor` (the shader uses `color.backgroundRGBA` as the border rim, not `params.borderColor`).

### matrixRain (variant=3, CPU only — stub)

CPU-only today. When ported to GPU, will need a time uniform + per-column state buffer. **Used fields** that the CPU path reads:
- `geometry.spacing`, `geometry.scale` (cell size)
- `color.*`
- `params.direction`, `params.speed`, `params.trailLength`, `params.glow`, `params.backgroundOpacity`, `params.threshold`, `params.rainColor`
- `params.intensity`

**Ignored**: `common.*`, `params.characterSet`, `dotShape`, `gridType`, `blockStyle`, `borderWidth`, `borderColor`, `invert`.

---

## PrintSampling bucket

Pipeline: `printSamplingFragment`. Payload: `PrintSamplingParameters`.

### threshold (variant=0, GPU)

**Used**:
- `color.foregroundRGBA`, `color.backgroundRGBA` (ink / paper)
- `params.threshold` (cutoff)
- `params.thresholdLevels` (2..32 quantization)
- `params.thresholdDither` (bool — 2×2 checkerboard phase)
- `params.invert`
- `params.foreground`, `params.background`

**Ignored**:
- `common.*` entirely
- `geometry.*` entirely (per-pixel, no cell grid)
- `color.mode`, `color.backgroundIntensity` (uses fg/bg directly)
- `params.sampleDensity`, `params.modulation`, `params.sharpen`, `params.chromaticAberration` (dithering-specific)
- `params.algorithm` (dithering-specific)
- `params.halftoneShape`, `params.halftoneAngle` (halftone-specific, hidden)
- `params.hatchDensity`, `params.hatchLayers`, `params.hatchAngle`, `params.hatchLineWidth`, `params.hatchRandomness` (crosshatch-specific)

### crosshatch (variant=1, GPU)

**Used**:
- `color.foregroundRGBA`, `color.backgroundRGBA`
- `params.threshold` (luminance cutoff for inking)
- `params.hatchAngle` (primary angle)
- `params.hatchDensity` (line spacing)
- `params.hatchLineWidth`
- `params.hatchLayers` (1..3 — 1=one axis, 2=cross, 3=cross+diagonal)
- `params.hatchRandomness` (noise-toggle)
- `params.invert`
- `params.foreground`, `params.background`

**Ignored**: `common.*`, `geometry.*`, `color.mode`, `color.backgroundIntensity`, `thresholdLevels`, `thresholdDither`, halftone fields, dithering fields, `sharpen`, `modulation`, `chromaticAberration`.

---

## EdgeField bucket

Pipeline: `edgeFieldFragment`. Payload: `EdgeFieldParameters`.

### edgeDetection (variant=0, GPU)

**Used**:
- `color.mode` (affects R/B channel split)
- `color.backgroundIntensity`
- `params.lineStrength`
- `params.thickness`
- `params.edgeThreshold`
- `params.edgeAlgorithm` (sobel vs laplacian)
- `params.invert`
- `params.edgeColor` (optional ink tint)

**Ignored**: `common.*`, `geometry.*`, `color.foregroundRGBA`, `color.backgroundRGBA`, `params.fieldIntensity`, `params.lineCount`, `params.amplitude`, `params.frequency`, `params.direction`, `params.animate`, `params.noiseType`, `params.octaves`, `params.speed`, `params.distortOnly`, `params.contourFillMode`, `params.contourLevels`, `params.cellSize`, `params.edgeWidth`, `params.randomize`.

### contour (variant=1, GPU)

**Used**:
- `color.backgroundIntensity`
- `params.lineStrength`, `params.thickness` (line width)
- `params.invert`
- `params.fieldIntensity` (band modulation)
- `params.contourLevels` (2..32 bands)
- `params.contourFillMode` (linesOnly vs filledBands)
- `params.edgeColor`

**Ignored**: `common.*`, `geometry.*`, `color.mode`, `color.fg/bgRGBA`, edge-detection / waveLines / voronoi / noiseField fields.

### waveLines (variant=2, GPU)

**Used**:
- `color.backgroundIntensity`
- `params.lineStrength`, `params.thickness`
- `params.invert`
- `params.direction` (horizontal / vertical)
- `params.amplitude` (phase-modulation strength)
- `params.frequency` (spatial phase multiplier)
- `params.lineCount` (reserved — not currently consumed by shader, would modulate density)
- `params.edgeColor`
- `geometry.spacing`, `geometry.scale` (indirectly — `spacing` pre-computed Swift-side as `spacing + scale * 2`)

**Ignored**: `common.*`, `geometry.outputWidth`, `color.mode`, `color.fg/bgRGBA`, contour / edgeDetection / voronoi / noiseField fields.

### voronoi (variant=3, GPU)

**Used**:
- `color.backgroundIntensity`
- `params.lineStrength`
- `params.invert`
- `params.cellSize`
- `params.edgeWidth`
- `params.randomize`
- `params.fieldIntensity`
- `params.edgeColor`

**Ignored**: `common.*`, `geometry.*`, `color.mode`, `color.fg/bgRGBA`, other EdgeField variants' fields.

### noiseField (variant=4, GPU)

**Used**:
- `color.backgroundIntensity`
- `params.lineStrength`
- `params.invert`
- `params.amplitude` (noise scale)
- `params.fieldIntensity`
- `params.edgeColor`

**Ignored**: `common.*`, `geometry.*`, `color.mode`, `color.fg/bgRGBA`, `params.noiseType` (shader hardcodes IGN), `params.octaves` (shader caps at 1 implicitly — was meant to loop 1..4), `params.direction`, `params.frequency`, `params.animate`, `params.speed`, `params.distortOnly`, other EdgeField variants' fields.

---

## Glitch bucket

### vhs (variant=1, CPU only — no GPU shader yet)

Would use `params.amount`, `params.threshold`, `params.distortion`, `params.colorBleed`, `params.scanlines`, `params.trackingError`, `params.intensity`. Ignored: `params.sortMode`, `params.streakLength`, `params.randomness`, `params.reverse`, `params.direction` (all PixelSort-specific).

---

## Proposed UI pruning

**Hide everywhere** (across all 11 user-facing variants):
- Entire `common` block (brightness / contrast / saturation / hue / sharpness / gamma)
- `geometry.outputWidth`

**Show only on TextCell variants** (dots, blockify, matrixRain):
- `geometry.scale`
- `geometry.spacing`

**Show only where indicated** per the matrices above:
- `color.mode`: dots, blockify, edgeDetection
- `color.backgroundIntensity`: all EdgeField variants
- `color.foregroundRGBA` / `color.backgroundRGBA`: dots, blockify, threshold, crosshatch (via `color.mode != .source`, or via `params.foreground/background` overrides)

**Per-variant parameter sections** (shown only for their variant):
- **dots**: dotShape, gridType, intensity, invert, foreground, background
- **blockify**: blockStyle, borderWidth, intensity, foreground, background
- **matrixRain**: direction, speed, trailLength, glow, backgroundOpacity, threshold, rainColor, intensity
- **threshold**: threshold, thresholdLevels, thresholdDither, invert, foreground, background
- **crosshatch**: threshold, hatchAngle, hatchDensity, hatchLineWidth, hatchLayers, hatchRandomness, invert, foreground, background
- **edgeDetection**: lineStrength, thickness, edgeThreshold, edgeAlgorithm, invert, edgeColor
- **contour**: lineStrength, thickness, invert, fieldIntensity, contourLevels, contourFillMode, edgeColor
- **waveLines**: lineStrength, thickness, invert, direction, amplitude, frequency, edgeColor
- **voronoi**: lineStrength, invert, cellSize, edgeWidth, randomize, fieldIntensity, edgeColor
- **noiseField**: lineStrength, invert, amplitude, fieldIntensity, edgeColor
- **vhs** (still CPU): amount, threshold, distortion, colorBleed, scanlines, trackingError, intensity

---

## Two ways to close the gap

**Prune** (recommended): update `GPUEffectLayerControls` (macOS) + `LayerDetailView` (iOS) to conditionally render each control based on the current `kind`. Total UI changes: ~200 LOC across the two files. No shader work. Matches current behaviour — users only see controls that actually do something.

**Extend shaders** (optional): wire `common` adjustments (brightness / contrast / saturation / hue / sharpness / gamma) into every bucket shader by calling `applyBrightnessContrast` + `applyGamma` from `ShaderCommon.h` as a pre-pass before the variant-specific code. Makes the common block meaningful everywhere. Total shader changes: ~20 LOC per `.metal` file × 3 files = ~60 LOC. After this work, unhide the common block in the pruning pass.

Recommendation: **prune first, extend selectively later**. Most bucket effects are pattern generators where brightness/contrast shouldn't meaningfully change the output (a threshold line is a line regardless of ±0.2 brightness); adjusting the source pre-effect, if desired, can be achieved by chaining a shader-style colour grade layer above the `.gpuEffect` layer in the stack.
