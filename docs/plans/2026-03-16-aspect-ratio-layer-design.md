# Aspect Ratio Layer — Design

## Goal

Add a new `aspectRatio` composition layer that crops images to a target aspect ratio with configurable center offset.

## Behavior

- Crops the image to the largest rectangle matching the target ratio that fits within the source dimensions
- Center-cropped by default, with optional X/Y offset to shift the crop window
- No-op if image already matches the target ratio
- Always crops, never pads (existing canvas/padding layers handle padding)
- Pure geometry — no pixel manipulation beyond clipping

## Data Model

```swift
public struct AspectRatioLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var ratioWidth: Int    // e.g. 1, 5, 16
    public var ratioHeight: Int   // e.g. 1, 4, 9
    public var offsetX: Double    // -1.0 (left) to 1.0 (right), 0 = center
    public var offsetY: Double    // -1.0 (bottom) to 1.0 (top), 0 = center
}
```

New enum case: `.aspectRatio(AspectRatioLayerParams)`

## Processing

### Crop Rect Calculation

```
targetRatio = ratioWidth / ratioHeight
imageRatio = imageWidth / imageHeight

if targetRatio > imageRatio:
    // Image is taller than target — crop height
    cropW = imageWidth
    cropH = imageWidth / targetRatio
else:
    // Image is wider than target — crop width
    cropW = imageHeight * targetRatio
    cropH = imageHeight

// Center + offset
cropX = (imageWidth - cropW) / 2 + offsetX * (imageWidth - cropW) / 2
cropY = (imageHeight - cropH) / 2 + offsetY * (imageHeight - cropH) / 2

// Clamp to image bounds
```

### Pipeline Integration

- **GPU (CIFilterPipeline):** `canProcessOnGPU = true`. Uses `CIImage.cropped(to: cropRect)`.
- **CPU (BorderRenderer):** Uses `CGImage.cropping(to: cropRect)`.
- **OutputSizeCalculator:** Computes cropped dimensions without rendering.

## UI

- Preset ratio picker: 1:1, 4:5, 5:4, 3:2, 2:3, 16:9, 9:16, Custom
- Custom: two integer fields for width:height
- Two sliders for offsetX and offsetY (-1.0 to 1.0)
- Added to layer menu in LayerListSection

## YAML Support

```yaml
aspect_ratio:
  ratio: "4:5"
  offset_x: 0.0
  offset_y: 0.0
```

## Layer Order

Typically early in the stack (before borders/padding/caption) so subsequent layers operate on the cropped dimensions.
