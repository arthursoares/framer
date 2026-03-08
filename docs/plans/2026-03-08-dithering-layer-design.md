# Dithering Layer — Design

**Goal:** Add a `.dither` composition layer that applies classic dithering algorithms to photos, supporting 1-bit B&W, two-tone, and full-color quantization modes.

**Architecture:** New `DitherLayerParams` + `DitherRenderer` following the existing layer pattern. Operates on `CGImage` in-place within `BorderRenderer.applyLayers`. All algorithms work in linear RGB to avoid brightness bias.

---

## Model

New case on `CompositionLayer`: `.dither(DitherLayerParams)`

```swift
public struct DitherLayerParams: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var algorithm: DitherAlgorithm
    public var colorMode: DitherColorMode
    public var bayerLevel: Int  // 1-4, only meaningful when algorithm == .bayer
    public var pixelScale: Int  // 1-8, downscale by N before dithering, upscale back with nearest-neighbor
}

public enum DitherAlgorithm: String, Codable, Sendable, CaseIterable {
    case bayer
    case floydSteinberg
    case atkinson
    case blueNoise
    case artisticDrip
}

public enum DitherColorMode: Codable, Equatable, Sendable {
    case bw
    case twoTone(foreground: CodableColor, background: CodableColor)
    case color(levels: Int)  // 2-8 per channel
}
```

Defaults: `algorithm: .atkinson`, `colorMode: .bw`, `bayerLevel: 2`, `pixelScale: 1`

---

## Algorithms

All algorithms convert sRGB → linear RGB before processing and linear → sRGB after.

### Bayer (Ordered Dithering)
- Precomputed threshold matrices: level 1 = 4×4, level 2 = 8×8, level 3 = 16×16, level 4 = 32×32
- Recursively defined: `M(n+1) = (1/4) * [[4*M(n), 4*M(n)+2], [4*M(n)+3, 4*M(n)+1]]`
- Tiled across image, each pixel compared against normalized threshold
- Parallelizable per-pixel — can use vDSP/Accelerate for the threshold comparison

### Floyd-Steinberg
- Sequential raster scan (left-to-right, top-to-bottom)
- Error diffusion weights: right=7/16, below-left=3/16, below=5/16, below-right=1/16
- Classic error diffusion look — good detail preservation

### Atkinson
- Sequential raster scan
- Error diffusion to 6 neighbors, each at 1/8 (only 75% of error propagated)
- Higher perceived contrast — darks stay dark, lights stay light
- The classic Macintosh look

### Blue Noise
- Bundled 64×64 blue noise threshold texture (precomputed, tiled seamlessly)
- Applied identically to Bayer — threshold comparison per pixel
- Organic, natural appearance — no visible structure
- Gold standard for aesthetic quality

### Artistic Drip
- Custom error diffusion kernel inspired by jdobr.es experiments
- Pushes error primarily downward with slight negative lateral weight
- Creates a distinctive directional "dripping paint" artifact
- Kernel (1/8 normalization): `[0, 0, 0] / [0, *, 1] / [-1, 3, 3] / [0, 2, 0]`
  (exact weights TBD during implementation — perceptual tuning needed)

---

## Color Modes

### B&W (default)
- Convert pixel to luminance: `L = 0.2126*R + 0.7152*G + 0.0722*B` (in linear space)
- Quantize to 0 or 1 using the selected algorithm
- Output: black (0,0,0) or white (255,255,255)

### Two-Tone
- Same 1-bit luminance quantization as B&W
- Map 0 → user-selected background color, 1 → user-selected foreground color
- Default: foreground = black, background = white
- Enables Game Boy green, amber CRT, sepia, blueprint aesthetics

### Color
- Apply dithering independently per R, G, B channel
- Quantize each channel to N evenly-spaced levels (2-8)
- 2 levels = 8 total colors, 4 levels = 64 colors, 8 levels = 512 colors
- Error diffusion algorithms: compute and diffuse error per channel independently
- Threshold algorithms: quantize each channel against the threshold independently

---

## Pixel Scale

When `pixelScale > 1`, the renderer:
1. Downscales the image by N using bilinear interpolation (e.g., 4000×3000 → 1000×750 at scale 4)
2. Applies the dithering algorithm at the reduced resolution
3. Upscales back to original dimensions using **nearest-neighbor interpolation** (preserves hard pixel edges)

This produces the chunky retro look where each dithered "pixel" becomes a visible N×N block. At scale 1 (default), dithering operates at full resolution for fine-grained output.

Range: 1-8. Higher values = bigger pixels = more retro.

---

## Processing Integration

In `BorderRenderer.applyLayers`, add a new case:

```swift
case .dither(let params):
    current = try DitherRenderer.apply(to: current, params: params)
```

No special positioning — works like any other layer wherever the user places it.

---

## File: DitherRenderer.swift

Location: `Sources/FramerCore/Processing/DitherRenderer.swift`

Public API:
```swift
public enum DitherRenderer {
    public static func apply(to image: CGImage, params: DitherLayerParams) throws -> CGImage
}
```

Internal structure:
- `sRGBToLinear(_:)` / `linearToSRGB(_:)` — gamma conversion helpers
- `applyBayer(to:level:colorMode:)` — threshold map approach
- `applyBlueNoise(to:colorMode:)` — threshold map with bundled texture
- `applyFloydSteinberg(to:colorMode:)` — error diffusion
- `applyAtkinson(to:colorMode:)` — error diffusion with 75% propagation
- `applyArtisticDrip(to:colorMode:)` — custom kernel error diffusion
- `quantize(_:levels:)` — shared quantization helper

Blue noise texture: embedded as a static `[Float]` array (64×64 = 4096 values), generated offline. No runtime asset loading needed.

---

## UI

New layer row in `LayerListSection.swift` / `SettingsPanel.swift`:

| Control | Type | Condition |
|---------|------|-----------|
| Algorithm | Picker (dropdown) | Always |
| Color Mode | Segmented (B&W / Two-tone / Color) | Always |
| Foreground Color | ColorPicker | Two-tone mode |
| Background Color | ColorPicker | Two-tone mode |
| Color Levels | Stepper (2-8) | Color mode |
| Bayer Level | Stepper (1-4) | Bayer algorithm |
| Pixel Scale | Stepper (1-8) | Always |

---

## Testing

File: `Tests/FramerCoreTests/DitherRendererTests.swift`

| Test | Assertion |
|------|-----------|
| Output dimensions match input | width/height preserved for all algorithms |
| B&W produces only black/white | Every pixel is (0,0,0) or (255,255,255) |
| Two-tone produces only specified colors | Pixel set == {fg, bg} |
| Color mode respects level count | Unique values per channel <= N |
| Bayer level changes output | Level 1 output != level 4 output |
| Gamma correction applied | 50% sRGB gray dithers to ~74% white pixels (linear midpoint), not 50% |
| Each algorithm produces different output | Hash comparison across all 5 algorithms |
| Artistic drip has vertical bias | More error visible below source than above |
| Pixel scale produces blocky output | Scale 4 output has 4×4 identical pixel blocks |
| Pixel scale preserves dimensions | Output size == input size regardless of scale |

---

## YAML/JSON Encoding

```yaml
layers:
  - dither:
      algorithm: atkinson
      colorMode: bw
      bayerLevel: 2
      pixelScale: 1
```

```yaml
layers:
  - dither:
      algorithm: bayer
      colorMode:
        twoTone:
          foreground: "#000000"
          background: "#C4CFA1"
      bayerLevel: 3
      pixelScale: 4
```

```yaml
layers:
  - dither:
      algorithm: floydSteinberg
      colorMode:
        color:
          levels: 4
      bayerLevel: 2
      pixelScale: 2
```
