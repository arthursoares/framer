# Caption as Composition Layer - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make caption a `CompositionLayer` variant instead of a special-case post-processing step.

**Architecture:** Add `.caption(CaptionLayerParams)` to `CompositionLayer`. Move all caption/font fields from `ProcessingConfig` into `CaptionLayerParams`. Handle `.caption` in `BorderRenderer.applyLayers` by calling `CaptionRenderer`. Remove the separate caption call from `FrameProcessor`. No backward compatibility needed.

**Tech Stack:** Swift 5.10, CoreGraphics, CoreText, SwiftUI

---

### Task 1: Add CaptionLayerParams and .caption case to CompositionLayer

**Files:**
- Modify: `Sources/FramerCore/Models/CompositionLayer.swift`

**Step 1: Add CaptionLayerParams struct**

Add after `OrientationLayerParams` (line 222):

```swift
public struct CaptionLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var mode: CaptionMode
    public var fontName: String
    public var fontSize: FontSize
    public var fontStyle: FontStyle
    public var fontColor: CodableColor
    public var alignment: CaptionAlignment
    public var position: CaptionPosition
    public var offsetX: Int
    public var offsetY: Int

    public init(
        id: UUID = UUID(),
        mode: CaptionMode = .template(" - {{mon}} '{{year2}} -"),
        fontName: String = "Courier New",
        fontSize: FontSize = .auto,
        fontStyle: FontStyle = [],
        fontColor: CodableColor = try! CodableColor(hex: "#000000"),
        alignment: CaptionAlignment = .center,
        position: CaptionPosition = .bottom,
        offsetX: Int = 0,
        offsetY: Int = 0
    ) {
        self.id = id
        self.mode = mode
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontStyle = fontStyle
        self.fontColor = fontColor
        self.alignment = alignment
        self.position = position
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}
```

**Step 2: Add .caption case to CompositionLayer enum**

Add `case caption(CaptionLayerParams)` after `.orientation` (line 232).

Update `id`, `label`, `iconName` computed properties:
- `id`: `case .caption(let p): return p.id`
- `label`: `case .caption: return "Caption"`
- `iconName`: `case .caption: return "textformat"`

Update `Codable` implementation:
- `init(from:)`: add `case "caption": self = .caption(try container.decode(CaptionLayerParams.self, forKey: .params))`
- `encode(to:)`: add `case .caption(let p): try container.encode("caption", forKey: .type); try container.encode(p, forKey: .params)`

**Step 3: Update defaultLayers()**

Change `defaultLayers()` to include a caption layer at the end:

```swift
public static func defaultLayers() -> [CompositionLayer] {
    [
        .border(BorderLayerParams(thickness: .pixels(20), color: try! CodableColor(hex: "#FFFFFF"))),
        .padding(PaddingLayerParams(thickness: 150, fill: .color(try! CodableColor(hex: "#FFFFFF")))),
        .caption(CaptionLayerParams())
    ]
}
```

**Step 4: Delete fromLegacyConfig() and all legacy helpers**

Remove `fromLegacyConfig()`, `solidLayers()`, `instagramLayers()`, `printLayers()`, `fillFromBackgroundMode()` (lines 322-381).

**Step 5: Run tests**

Run: `swift build`
Expected: Compilation errors in files that reference removed caption fields on ProcessingConfig. That's expected — we fix those in subsequent tasks.

**Step 6: Commit**

```
git commit -m "feat: add CaptionLayerParams and .caption case to CompositionLayer"
```

---

### Task 2: Remove caption/font fields from ProcessingConfig

**Files:**
- Modify: `Sources/FramerCore/Models/ProcessingConfig.swift`

**Step 1: Remove caption/font fields from ProcessingConfig struct**

Remove these fields from the struct (lines 187-204), init, and CodingKeys:
- `captionMode`, `fontName`, `fontSize`, `fontStyle`, `fontColor`
- `captionAlignment`, `captionPosition`, `captionOffsetX`, `captionOffsetY`, `captionPadding`

Keep: `borderStyle`, `borderThickness`, `borderColor`, `padding`, `outputFormat`, `instagramMaxSize`, `postProcess`, `backgroundColor`, `outerPadding`, `noMetadata`, `backgroundMode`, `layers`.

Also remove `CaptionMode`, `CaptionAlignment`, `CaptionPosition`, `FontStyle`, `FontSize` type definitions ONLY IF they are not used elsewhere. They ARE used — `CaptionLayerParams` references them — so keep the type definitions, just remove the fields from ProcessingConfig.

**Step 2: Update ProcessingConfig.default**

Remove caption/font default values from the init.

**Step 3: Update Codable implementation**

Remove caption/font keys from `CodingKeys` and `init(from:)`.

**Step 4: Commit**

```
git commit -m "refactor: remove caption/font fields from ProcessingConfig"
```

---

### Task 3: Update CaptionRenderer to work as a layer

**Files:**
- Modify: `Sources/FramerCore/Processing/CaptionRenderer.swift`

**Step 1: Change signature to accept CaptionLayerParams + ExifData**

Replace the current signature:
```swift
public static func renderCaption(
    on image: CGImage,
    config: ProcessingConfig,
    exif: ExifData,
    imageOrigin: CGPoint? = nil,
    imageSize: CGSize? = nil
) throws -> CGImage
```

With:
```swift
public static func renderCaption(
    on image: CGImage,
    params: CaptionLayerParams,
    exif: ExifData
) throws -> CGImage
```

**Step 2: Update implementation to use params instead of config**

- `params.mode` instead of `config.captionMode`
- `params.fontName` instead of `config.fontName`
- `params.fontSize` instead of `config.fontSize`
- `params.fontStyle` instead of `config.fontStyle`
- `params.fontColor` instead of `config.fontColor`
- `params.alignment` instead of `config.captionAlignment`
- `params.position` instead of `config.captionPosition`
- `params.offsetX` instead of `config.captionOffsetX`
- `params.offsetY` instead of `config.captionOffsetY`

**Step 3: Simplify positioning — remove imageOrigin/imageSize logic**

For auto font size, use a percentage of the image height instead of legacy borderPx:
```swift
let fontSize: CGFloat
switch params.fontSize {
case .fixed(let pts):
    fontSize = CGFloat(pts)
case .auto:
    fontSize = max(CGFloat(min(image.width, image.height)) * 0.02, 10)
}
```

For positioning, use margins from the image edges:
- Bottom: `y = fontSize * 1.5 + descent`
- Top: `y = CGFloat(image.height) - fontSize * 1.5`
- Left: `x = textMargin`
- Center: `x = CTLineGetPenOffsetForFlush(line, 0.5, Double(image.width))`
- Right: `x = CTLineGetPenOffsetForFlush(line, 1.0, Double(image.width)) - textMargin`

Remove captionSpacing / captionPadding references.

**Step 4: Commit**

```
git commit -m "refactor: simplify CaptionRenderer to accept CaptionLayerParams"
```

---

### Task 4: Handle .caption in BorderRenderer.applyLayers and update FrameProcessor

**Files:**
- Modify: `Sources/FramerCore/Processing/BorderRenderer.swift`
- Modify: `Sources/FramerCore/Processing/FrameProcessor.swift`

**Step 1: Add exif parameter to applyLayers**

Change signature from:
```swift
public static func applyLayers(_ layers: [CompositionLayer], to image: CGImage, sourceImage: CGImage) throws -> BorderResult
```
To:
```swift
public static func applyLayers(_ layers: [CompositionLayer], to image: CGImage, sourceImage: CGImage, exif: ExifData) throws -> BorderResult
```

**Step 2: Handle .caption case in the layer loop**

In the `switch layer` block (around line 97), add:
```swift
case .caption(let params):
    current = try CaptionRenderer.renderCaption(on: current, params: params, exif: exif)
```

**Step 3: Update FrameProcessor.previewImage and process**

In both methods, remove the separate `CaptionRenderer.renderCaption` call. Pass `exif` to `applyLayers`:

```swift
let borderResult: BorderResult
if let layers = config.layers {
    borderResult = try BorderRenderer.applyLayers(layers, to: cgImage, sourceImage: cgImage, exif: exif)
} else {
    borderResult = try BorderRenderer.applyLayers(CompositionLayer.defaultLayers(), to: cgImage, sourceImage: cgImage, exif: exif)
}
// Remove: let captioned = try CaptionRenderer.renderCaption(...)
// Use borderResult.image directly
```

Remove the `let captioned = ...` lines and use `borderResult.image` where `captioned` was used.

**Step 4: Commit**

```
git commit -m "feat: render caption as layer in composition pipeline"
```

---

### Task 5: Update YAMLConfig for caption layer

**Files:**
- Modify: `Sources/FramerCore/Presets/YAMLConfig.swift`

**Step 1: Add caption fields to YAMLLayerSchema**

```swift
var caption_mode: String?       // "template", "custom", "none"
var caption_text: String?       // template or custom text
var font_name: String?
var font_size: String?          // "auto" or number
var font_bold: Bool?
var font_italic: Bool?
var font_color: String?
var caption_alignment: String?
var caption_position: String?
var caption_offset_x: Int?
var caption_offset_y: Int?
```

**Step 2: Add .caption case to encodeLayers()**

```swift
case .caption(let p):
    var schema = YAMLLayerSchema(type: "caption")
    switch p.mode {
    case .template(let t):
        schema.caption_mode = "template"
        schema.caption_text = t
    case .custom(let s):
        schema.caption_mode = "custom"
        schema.caption_text = s
    case .none:
        schema.caption_mode = "none"
    }
    schema.font_name = p.fontName
    switch p.fontSize {
    case .auto: schema.font_size = "auto"
    case .fixed(let s): schema.font_size = String(s)
    }
    if p.fontStyle.contains(.bold) { schema.font_bold = true }
    if p.fontStyle.contains(.italic) { schema.font_italic = true }
    schema.font_color = p.fontColor.hex
    schema.caption_alignment = p.alignment.rawValue
    schema.caption_position = p.position.rawValue
    if p.offsetX != 0 { schema.caption_offset_x = p.offsetX }
    if p.offsetY != 0 { schema.caption_offset_y = p.offsetY }
    return schema
```

**Step 3: Add "caption" case to decodeLayers()**

```swift
case "caption":
    let mode: CaptionMode
    switch schema.caption_mode {
    case "custom": mode = .custom(schema.caption_text ?? "")
    case "none": mode = .none
    default: mode = .template(schema.caption_text ?? " - {{mon}} '{{year2}} -")
    }
    var fontStyle: FontStyle = []
    if schema.font_bold == true { fontStyle.insert(.bold) }
    if schema.font_italic == true { fontStyle.insert(.italic) }
    let fontSize: FontSize
    if let fs = schema.font_size, let i = Int(fs) {
        fontSize = .fixed(i)
    } else {
        fontSize = .auto
    }
    return .caption(CaptionLayerParams(
        mode: mode,
        fontName: schema.font_name ?? "Courier New",
        fontSize: fontSize,
        fontStyle: fontStyle,
        fontColor: (schema.font_color.flatMap { try? CodableColor(hex: $0) }) ?? (try! CodableColor(hex: "#000000")),
        alignment: schema.caption_alignment.flatMap { CaptionAlignment(rawValue: $0) } ?? .center,
        position: schema.caption_position.flatMap { CaptionPosition(rawValue: $0) } ?? .bottom,
        offsetX: schema.caption_offset_x ?? 0,
        offsetY: schema.caption_offset_y ?? 0
    ))
```

**Step 4: Remove caption/font fields from YAMLSchema top-level encode/decode**

Remove the caption/font encoding lines from `encode()` (lines 77-107 that reference `config.captionMode`, `config.fontName`, etc).

Remove the caption/font decoding lines from `decode()` (lines 136-182 that set `config.captionMode`, `config.fontName`, etc).

Remove the corresponding fields from `YAMLSchema` struct: `caption`, `caption_template`, `no_caption`, `font_name`, `font_size`, `font_bold`, `font_italic`, `font_color`, `caption_padding`, `caption_alignment`, `caption_position`, `caption_offset_x`, `caption_offset_y`.

**Step 5: Commit**

```
git commit -m "refactor: update YAMLConfig for caption layer"
```

---

### Task 6: Update CLI ProcessCommand

**Files:**
- Modify: `Sources/FramerCLI/Commands/ProcessCommand.swift`

**Step 1: Change CLI caption flags to build a caption layer**

Keep the CLI flags (`--caption`, `--caption-template`, `--no-caption`, `--font-name`, etc) but instead of setting them on `ProcessingConfig`, build a `CaptionLayerParams` and insert it into the layers:

After all config overrides are applied, add:

```swift
// Build caption layer from CLI flags
var captionMode: CaptionMode = .template(" - {{mon}} '{{year2}} -")
if noCaption { captionMode = .none }
else if let t = captionTemplate { captionMode = .template(t) }
else if let c = caption { captionMode = .custom(c) }

var captionFontStyle: FontStyle = []
if fontBold { captionFontStyle.insert(.bold) }
if fontItalic { captionFontStyle.insert(.italic) }

let captionParams = CaptionLayerParams(
    mode: captionMode,
    fontName: fontName ?? "Courier New",
    fontSize: fontSize.map { .fixed($0) } ?? .auto,
    fontStyle: captionFontStyle,
    fontColor: (fontColor.flatMap { try? CodableColor(hex: $0) }) ?? (try! CodableColor(hex: "#000000")),
    alignment: .center,
    position: .bottom
)

// Ensure layers exist and add caption
if cfg.layers == nil {
    cfg.layers = CompositionLayer.defaultLayers()
}
// Remove any existing caption layers, then append
cfg.layers?.removeAll { if case .caption = $0 { return true }; return false }
if case .none = captionMode {} else {
    cfg.layers?.append(.caption(captionParams))
}
```

**Step 2: Remove lines that set caption/font directly on cfg**

Remove lines 74-81 and 87 that set `cfg.captionMode`, `cfg.fontName`, `cfg.fontSize`, `cfg.fontStyle`, `cfg.fontColor`, `cfg.captionPadding`.

**Step 3: Commit**

```
git commit -m "refactor: update CLI to build caption as layer"
```

---

### Task 7: Update UI — move caption controls into LayerListSection

**Files:**
- Modify: `Sources/FramerApp/Editor/SettingsPanel.swift`
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`

**Step 1: Remove Caption and Font sections from SettingsPanel**

Remove the `Section("Caption")` block and `Section("Font")` block. Keep Output section.

Move `TemplateTokenBar`, `TemplateToken`, and `FlowLayout` from SettingsPanel.swift into LayerListSection.swift (or a shared file).

**Step 2: Add CaptionLayerControls to LayerListSection**

Add a new view in LayerListSection.swift:

```swift
struct CaptionLayerControls: View {
    var params: CaptionLayerParams
    var onChange: (CaptionLayerParams) -> Void

    // Same cachedMonospacedFonts as was in SettingsPanel
    private static let cachedMonospacedFonts: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
            .sorted()
    }()

    var body: some View {
        // Mode picker (Template / Custom / None)
        Picker("Mode", selection: captionModeIndex) {
            Text("Template").tag(0)
            Text("Custom").tag(1)
            Text("None").tag(2)
        }
        .pickerStyle(.segmented)

        // Template/custom text field
        switch params.mode {
        case .template:
            TextField("Template", text: templateTextBinding)
                .font(.system(.body, design: .monospaced))
            TemplateTokenBar(text: templateTextBinding)
        case .custom:
            TextField("Caption text", text: customTextBinding)
        case .none:
            EmptyView()
        }

        if captionEnabled {
            // Position & Alignment
            Picker("Position", selection: positionBinding) {
                Text("Bottom").tag(CaptionPosition.bottom)
                Text("Top").tag(CaptionPosition.top)
            }
            .pickerStyle(.segmented)

            Picker("Alignment", selection: alignmentBinding) {
                Text("Left").tag(CaptionAlignment.left)
                Text("Center").tag(CaptionAlignment.center)
                Text("Right").tag(CaptionAlignment.right)
            }
            .pickerStyle(.segmented)

            // Font picker
            Picker("Font", selection: fontNameBinding) {
                ForEach(Self.cachedMonospacedFonts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            // Font style toggles
            HStack(spacing: 8) {
                Text("Style")
                Spacer()
                Toggle(isOn: fontBoldBinding) { Text("B").bold() }
                    .toggleStyle(.button)
                Toggle(isOn: fontItalicBinding) { Text("I").italic() }
                    .toggleStyle(.button)
            }

            // Font color
            ColorPickerWithHex("Color", selection: fontColorBinding)
        }
    }

    // ... bindings that call onChange with modified params
}
```

**Step 3: Wire .caption in LayerRow.layerControls**

```swift
case .caption(let params):
    CaptionLayerControls(params: params) { layer = .caption($0) }
```

**Step 4: Update LayerRow.layerSummary for .caption**

```swift
case .caption(let p):
    switch p.mode {
    case .template: return "Template"
    case .custom: return "Custom"
    case .none: return "Off"
    }
```

**Step 5: Add caption to the addLayerMenu**

```swift
Button {
    addLayer(.caption(CaptionLayerParams()))
} label: {
    Label("Caption", systemImage: "textformat")
}
```

**Step 6: Update ExifInfoBar caption display**

In `LivePreviewPanel.swift`, `ExifInfoBar` currently reads `config.captionMode`. Update it to find the first caption layer in `config.layers` instead:

```swift
var captionText: String {
    guard let layers = config.layers,
          let captionLayer = layers.first(where: { if case .caption = $0 { return true }; return false }),
          case .caption(let params) = captionLayer else {
        return "(no caption)"
    }
    switch params.mode {
    case .template(let t): return exif.resolve(template: t)
    case .custom(let s): return s
    case .none: return "(no caption)"
    }
}
```

**Step 7: Commit**

```
git commit -m "feat: caption layer UI controls in LayerListSection"
```

---

### Task 8: Update tests

**Files:**
- Modify: `Tests/FramerCoreTests/CaptionRendererTests.swift`
- Modify: `Tests/FramerCoreTests/CompositionLayerTests.swift`
- Modify: `Tests/FramerCoreTests/ProcessingConfigTests.swift`
- Modify: `Tests/FramerCoreTests/BorderRendererTests.swift`
- Modify: `Tests/FramerCoreTests/FrameProcessorTests.swift`

**Step 1: Update CaptionRendererTests**

Change tests to use new `CaptionLayerParams` signature:

```swift
func test_renderCaption_doesNotChangeImageSize() throws {
    let image = makeTestImage()
    let params = CaptionLayerParams(
        mode: .custom("TEST CAPTION"),
        fontName: "Courier New",
        fontSize: .fixed(20)
    )
    let result = try CaptionRenderer.renderCaption(on: image, params: params, exif: ExifData())
    XCTAssertEqual(result.width, image.width)
    XCTAssertEqual(result.height, image.height)
}

func test_renderCaption_noneMode_returnsOriginal() throws {
    let image = makeTestImage()
    let params = CaptionLayerParams(mode: .none)
    let result = try CaptionRenderer.renderCaption(on: image, params: params, exif: ExifData())
    XCTAssertEqual(result.width, image.width)
    XCTAssertEqual(result.height, image.height)
}
```

Remove `test_renderCaption_printStyle_doesNotChangeImageSize` (no more imageOrigin/imageSize params).

**Step 2: Add caption layer round-trip test to CompositionLayerTests**

```swift
func test_captionLayer_roundtripsJSON() throws {
    let layer = CompositionLayer.caption(CaptionLayerParams(
        mode: .template("{{camera}} - {{mon}} '{{year2}}"),
        fontName: "Courier New",
        fontSize: .fixed(24),
        fontColor: try CodableColor(hex: "#FF0000")
    ))
    let data = try JSONEncoder().encode(layer)
    let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
    XCTAssertEqual(layer, decoded)
}
```

**Step 3: Fix ProcessingConfigTests**

Remove any tests that reference removed fields (`captionMode`, `fontName`, etc). Update `test_processingConfig_roundtripsJSON` and `test_processingConfig_decodesWithMissingNewFields` to not include caption fields.

**Step 4: Fix BorderRendererTests and FrameProcessorTests**

Update any calls to `BorderRenderer.applyLayers` to pass `exif: ExifData()`.
Update any `ProcessingConfig` construction that sets caption/font fields.

**Step 5: Run all tests**

Run: `swift test`
Expected: 102 tests pass (minus removed tests, plus new caption layer test).

**Step 6: Commit**

```
git commit -m "test: update tests for caption-as-layer refactor"
```

---

### Task 9: Final cleanup and validation

**Step 1: Run full build and test**

```
swift build && swift test
```

**Step 2: Build and launch the app**

```
xcodegen generate
xcodebuild -project Framer.xcodeproj -scheme Framer -configuration Debug -derivedDataPath /tmp/framer-build build
open /tmp/framer-build/Build/Products/Debug/Framer.app
```

**Step 3: Manual test**

- Add a photo
- Verify caption layer appears in default layers
- Edit caption template, font, alignment
- Reorder caption layer (before/after overlay)
- Delete caption layer, verify no caption rendered
- Add new caption layer, verify it works
- Export and verify caption in output file

**Step 4: Commit**

```
git commit -m "chore: caption-as-layer refactor complete"
```
