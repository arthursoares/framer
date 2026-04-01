# LUT Layer — Implementation Plan

> **Status:** Planned
> **Branch:** `feat/lut-layer`
> **Scope:** New `.lut` composition layer for 3D .cube LUT color grading

---

## Overview

Add a new composition layer type that applies 3D LUT color transformations to the image. Users can select from bundled film emulation presets or import their own `.cube` files. The LUT layer follows the same composable pattern as all other layers — it can be placed anywhere in the stack.

---

## 1. .cube File Format

The `.cube` file format (Adobe/Iridas standard) defines a 3D lookup table:

```
TITLE "Portra 400"
LUT_3D_SIZE 33
0.0 0.0 0.0
0.01 0.0 0.0
...
1.0 1.0 1.0
```

- `LUT_3D_SIZE N` — cube dimension (typically 17, 33, or 65)
- `N³` lines of `R G B` float triplets (0.0–1.0)
- Optional: `DOMAIN_MIN` / `DOMAIN_MAX` for non-standard ranges
- Optional: 1D LUT section (`LUT_1D_SIZE`) — we'll parse but ignore initially

Parsing is straightforward: read the size, then read N³ RGB triplets into a flat array.

---

## 2. Model Changes

### CompositionLayer

```swift
// New case in CompositionLayer enum
case lut(LUTLayerParams)

// New params struct
public struct LUTLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var lutName: String          // Display name (e.g., "Portra 400")
    public var lutFileName: String      // File identifier (e.g., "portra_400.cube")
    public var intensity: Double        // 0.0–1.0, default 1.0 (blend with original)
    
    public init(
        id: UUID = .init(),
        lutName: String = "",
        lutFileName: String = "",
        intensity: Double = 1.0
    ) { ... }
}
```

### Layer metadata

Add to `CompositionLayer` extension:
- `label` → `"LUT"`
- `iconName` → `"photo.artframe"` (SF Symbol - NOT `"camera.filters"` which doesn't exist)
- `layerSummary` → `lutName` (e.g., `"Portra 400"`) for badge display

---

## 3. LUT Storage & Discovery

### Directory structure

```
assets/luts/                          # Bundled LUTs (in app resources)
  ├── film/
  │   ├── portra_400.cube
  │   ├── portra_800.cube
  │   ├── kodak_gold_200.cube
  │   ├── fuji_pro_400h.cube
  │   ├── kodak_tri_x.cube
  │   ├── ilford_hp5.cube
  │   └── fuji_velvia_50.cube
  └── creative/
      ├── warm_sunset.cube
      ├── cool_shadows.cube
      └── bleach_bypass.cube

~/Library/Application Support/Framer/luts/   # User-imported LUTs (macOS)
<app container>/luts/                         # User-imported LUTs (iOS)
```

### LUTProvider (new, similar to TextureFrameProvider)

```swift
public enum LUTProvider {
    // Discovery
    static func availableLUTs() -> [LUTInfo]
    static func luts(inCategory: String) -> [LUTInfo]
    
    // Loading
    static func loadLUT(named: String) -> LUT3D?
    
    // User management
    static func importLUT(from url: URL) throws -> LUTInfo
    static func userLUTDirectory() -> URL?
    
    struct LUTInfo: Identifiable, Equatable, Hashable {
        let id: String          // filename without extension
        let displayName: String // parsed from TITLE or filename
        let category: String    // subdirectory name
        let url: URL
    }
}
```

Thread safety: Use `NSLock` + `NSCache< String, LUT3D>` for parsed LUT caching, same pattern as `TextureFrameProvider`.

### LUT3D (parsed cube data)

```swift
public struct LUT3D: Sendable {
    let size: Int               // cube dimension (17, 33, 65)
    let data: [Float]           // R,G,B triplets, size³×3 entries
    
    // Trilinear interpolation lookup
    func apply(r: Float, g: Float, b: Float) -> (Float, Float, Float)
}
```

---

## 4. Processing (LUTRenderer)

### Core algorithm: trilinear interpolation

For each pixel:
1. Scale input R,G,B from 0–255 to 0–(size-1)
2. Find the 8 surrounding cube vertices
3. Trilinear interpolation between the 8 vertices
4. Blend with original based on `intensity`: `output = lerp(original, lut_output, intensity)`

```swift
public enum LUTRenderer {
    public static func apply(
        to image: CGImage,
        lut: LUT3D,
        intensity: Double,
        previewBaseDimension: Int? = nil
    ) throws -> CGImage
}
```

### Performance considerations

- **Trilinear interpolation** is 8 lookups + 7 lerps per pixel — fast for CPU
- For a 4000×3000 image: 12M pixels × ~30 FP ops = ~360M ops — similar cost to dithering
- A 33³ LUT is only 33×33×33×3×4 = ~430KB — fits comfortably in L2 cache
- Could move to Metal later (same pattern as dither plan) but CPU should be fast enough for v1

### Integration in BorderRenderer

In `applyLayers()`, handle `.lut` like other per-pixel layers:

```swift
case .lut(let params):
    guard let lut = LUTProvider.loadLUT(named: params.lutFileName) else {
        throw FramerError.unsupportedFormat("LUT not found: \(params.lutFileName)")
    }
    current = try LUTRenderer.apply(to: current, lut: lut, intensity: params.intensity, previewBaseDimension: previewBaseDimension)
```

Note: `previewBaseDimension` is passed for performance optimization (renders at preview resolution, not full resolution).

---

## 5. .cube File Parser

```swift
public enum CubeFileParser {
    public static func parse(from url: URL) throws -> LUT3D
    public static func parse(string: String) throws -> LUT3D
    
    enum ParseError: LocalizedError {
        case missingSize
        case invalidSize(Int)
        case insufficientData(expected: Int, got: Int)
        case invalidLine(String)
    }
}
```

Parsing rules:
- Lines starting with `#` are comments
- `TITLE "name"` is optional metadata
- `LUT_3D_SIZE N` is required (N must be 2–256)
- `DOMAIN_MIN r g b` and `DOMAIN_MAX r g b` define the input range (default 0.0–1.0)
- Remaining lines are `R G B` float triplets
- Exactly N³ data lines are expected

---

## 5b. YAML Schema Changes

In `YAMLLayerSchema`, add new fields:

```swift
struct YAMLLayerSchema: Codable {
    // ... existing fields ...
    var lut_name: String?
    var lut_filename: String?
    var intensity: Double?
}
```

In `encodeLayers()`:
```swift
case .lut(let p):
    var schema = YAMLLayerSchema(type: "lut")
    schema.lut_name = p.lutName
    schema.lut_filename = p.lutFileName
    schema.intensity = p.intensity
    return schema
```

In `decodeLayers()`:
```swift
case "lut":
    return .lut(LUTLayerParams(
        lutName: schema.lut_name ?? "",
        lutFileName: schema.lut_filename ?? "",
        intensity: schema.intensity ?? 1.0
    ))
```

---

## 6. UI — macOS (LayerListSection)

### LUT layer controls

```
[LUT icon] LUT                    [Portra 400]  ×
  ┌──────────────────────────────────────────┐
  │ Category: [Film ▾]                       │
  │                                          │
  │ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐     │
  │ │    │ │    │ │    │ │    │ │    │     │
  │ │Port│ │Port│ │Gold│ │Fuji│ │TriX│     │
  │ │ 400│ │ 800│ │ 200│ │400H│ │    │     │
  │ └────┘ └────┘ └────┘ └────┘ └────┘     │
  │                                          │
  │ Intensity ━━━━━━━━━━━━━━━━━●━━━  85%    │
  │                                          │
  │ [Import .cube file...]                   │
  └──────────────────────────────────────────┘
```

Components:
- **Category picker** — segmented picker (like `OverlayLayerControls`), NOT dropdown: Film, Creative, User
- **LUT grid** — thumbnail previews of each LUT applied to the current photo (like preset grid, but smaller — 4 columns)
- **Intensity slider** — 0–100%, default 100%
- **Import button** — opens file picker for .cube files, copies to user LUT directory

### LUT thumbnail previews

Same approach as preset thumbnails: render a small preview of the current photo with each LUT applied. Cache in `[String: NSImage]`. Cancel on photo change. These are fast since LUT application is ~15ms even at preview resolution.

---

## 7. UI — iOS (LayerDetailView)

Same controls adapted for touch:
- Category as segmented picker or `.menu` picker
- Horizontal scroll strip of LUT previews (like PresetStrip)
- Intensity slider with value readout
- Import via `.fileImporter` for .cube files

---

## 8. Files to Create

| File | Purpose |
|------|---------|
| `Sources/FramerCore/Processing/CubeFileParser.swift` | Parse .cube files into LUT3D |
| `Sources/FramerCore/Processing/LUTRenderer.swift` | Apply 3D LUT to CGImage |
| `Sources/FramerCore/Processing/LUTProvider.swift` | Discover bundled + user LUTs (thread-safe with NSLock) |
| `assets/luts/` | **NEW** - Create directory structure |
| `assets/luts/film/*.cube` | Bundled film emulation LUTs |
| `assets/luts/creative/*.cube` | Bundled creative LUTs |

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/FramerCore/Models/CompositionLayer.swift` | Add `.lut(LUTLayerParams)` case, `layerSummary`, iconName |
| `Sources/FramerCore/Processing/BorderRenderer.swift` | Handle `.lut` in `applyLayers` with error propagation |
| `Sources/FramerApp/Editor/LayerListSection.swift` | Add `case .lut` in `layerControls` switch, add `LUTLayerControls` view |
| `Sources/FramerApp/Editor/LayerRow.swift` | Add `case .lut` in `layerSummary` switch |
| `Sources/FramerMobile/Layers/LayerDetailView.swift` | Add `case .lut` in `layerControls` switch, add `LUTControls` view |
| `Sources/FramerMobile/Layers/LayerRow.swift` | Add `case .lut` in `layerSummary` switch |
| `Sources/FramerMobile/Layers/LayerStrip.swift` | Add LUT to add-layer menu |
| `project.yml` | Create `assets/luts/` directory and add as folder resource for both targets |
| `Sources/FramerCore/Presets/YAMLConfig.swift` | Add `lut_name`, `lut_filename`, `intensity` fields to `YAMLLayerSchema`; encode/decode `.lut` case |

---

## 9. Bundled LUTs

Source film emulation LUTs from open-source/Creative Commons packs. Popular free sources:
- **RawTherapee Film Simulation** pack (CC-BY-SA) — includes Portra, Velvia, Tri-X emulations
- **Lutify.me free pack** — several film looks
- Custom-created using color science tools

Target: 7–10 film emulations + 3–5 creative looks for the initial release.

---

## 10. Implementation Order

1. **CubeFileParser** — parse .cube files, unit tests with sample data
2. **LUT3D + LUTRenderer** — trilinear interpolation, apply to CGImage, unit tests
3. **LUTProvider** — scan bundled + user directories, caching, thread-safe (NSLock)
4. **CompositionLayer.lut** — model, encoding/decoding, update BorderRenderer
5. **Create assets/luts/** — directory structure, add .cube files, update project.yml
6. **YAML config** — encode/decode for CLI compatibility
7. **macOS UI** — LUTLayerControls with category picker, thumbnail grid, intensity slider, LayerRow.lut case
8. **iOS UI** — LUTControls in LayerDetailView, LayerRow.lut case, LayerStrip menu item
9. **Import** — file picker on both platforms, copy to user LUT directory
10. **Polish** — thumbnail caching, empty states, error handling

Each step is a separate commit. The app remains functional throughout.

---

## 11. Testing

| Test | Description |
|------|-------------|
| `test_cubeParser_validFile` | Parse a minimal .cube file |
| `test_cubeParser_withTitle` | Parse TITLE and DOMAIN_MIN/MAX |
| `test_cubeParser_invalidSize` | Reject size < 2 or > 256 |
| `test_cubeParser_insufficientData` | Reject files with wrong line count |
| `test_lutRenderer_identity` | Identity LUT (output == input) |
| `test_lutRenderer_intensity0` | Intensity 0 returns original |
| `test_lutRenderer_intensity1` | Intensity 1 returns full LUT |
| `test_lutProvider_bundled` | Find bundled LUTs |
| `test_lutLayer_roundtripsJSON` | Encode/decode LUTLayerParams |
| `test_lutLayer_roundtripsYAML` | YAML encode/decode roundtrip for CLI |
