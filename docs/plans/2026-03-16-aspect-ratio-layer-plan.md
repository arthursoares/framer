# Aspect Ratio Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an `aspectRatio` composition layer that crops images to a target aspect ratio with configurable center offset.

**Architecture:** New `AspectRatioLayerParams` struct + `.aspectRatio` enum case in `CompositionLayer`. Crop rect computed from ratio + offset, applied via `CGImage.cropping(to:)` in BorderRenderer. UI provides preset ratios and custom input with offset sliders.

**Tech Stack:** Swift 5.10, CoreGraphics, SwiftUI, XCTest

---

### Task 1: Add AspectRatioLayerParams and CompositionLayer case

**Files:**
- Modify: `Sources/FramerCore/Models/CompositionLayer.swift`
- Test: `Tests/FramerCoreTests/CompositionLayerTests.swift`

**Step 1: Add the params struct**

In `Sources/FramerCore/Models/CompositionLayer.swift`, add before the `// MARK: - CompositionLayer` line (~line 504):

```swift
// MARK: - Aspect Ratio

public struct AspectRatioLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var ratioWidth: Int
    public var ratioHeight: Int
    public var offsetX: Double  // -1.0 (left) to 1.0 (right), 0 = center
    public var offsetY: Double  // -1.0 (bottom) to 1.0 (top), 0 = center

    public init(
        id: UUID = UUID(),
        ratioWidth: Int = 1,
        ratioHeight: Int = 1,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.id = id
        self.ratioWidth = max(1, ratioWidth)
        self.ratioHeight = max(1, ratioHeight)
        self.offsetX = max(-1, min(1, offsetX))
        self.offsetY = max(-1, min(1, offsetY))
    }

    /// Compute the crop rect for a given image size.
    public func cropRect(for imageSize: CGSize) -> CGRect {
        let targetRatio = CGFloat(ratioWidth) / CGFloat(ratioHeight)
        let imageRatio = imageSize.width / imageSize.height

        let cropW: CGFloat
        let cropH: CGFloat

        if targetRatio > imageRatio {
            // Image is taller than target — crop height
            cropW = imageSize.width
            cropH = imageSize.width / targetRatio
        } else {
            // Image is wider than target — crop width
            cropW = imageSize.height * targetRatio
            cropH = imageSize.height
        }

        // Center position
        let maxOffsetX = (imageSize.width - cropW) / 2
        let maxOffsetY = (imageSize.height - cropH) / 2

        // Apply user offset: offset 0 = center, ±1 = full shift
        let cropX = maxOffsetX + offsetX * maxOffsetX
        let cropY = maxOffsetY + offsetY * maxOffsetY

        return CGRect(
            x: cropX.rounded(.down),
            y: cropY.rounded(.down),
            width: cropW.rounded(.down),
            height: cropH.rounded(.down)
        )
    }

    /// Compute output size after cropping (for OutputSizeCalculator).
    public func croppedSize(for imageSize: CGSize) -> CGSize {
        let rect = cropRect(for: imageSize)
        return CGSize(width: rect.width, height: rect.height)
    }
}
```

**Step 2: Add the enum case and update all switches**

In the `CompositionLayer` enum (~line 506), add:
```swift
case aspectRatio(AspectRatioLayerParams)
```

Update every switch in the enum:

`id` (~line 516): add `case .aspectRatio(let p): return p.id`

`label` (~line 529): add `case .aspectRatio: return "Aspect Ratio"`

`iconName` (~line 542): add `case .aspectRatio: return "crop"`

`init(from decoder:)` (~line 561): add case:
```swift
case "aspectRatio":
    self = .aspectRatio(try container.decode(AspectRatioLayerParams.self, forKey: .params))
```

`encode(to encoder:)` (~line 589): add case:
```swift
case .aspectRatio(let p):
    try container.encode("aspectRatio", forKey: .type)
    try container.encode(p, forKey: .params)
```

**Step 3: Write the tests**

In `Tests/FramerCoreTests/CompositionLayerTests.swift`, add:

```swift
// MARK: - Aspect Ratio

func test_aspectRatioLayer_roundtripsJSON() throws {
    let layer = CompositionLayer.aspectRatio(AspectRatioLayerParams(
        ratioWidth: 4, ratioHeight: 5, offsetX: 0.2, offsetY: -0.3
    ))
    let data = try JSONEncoder().encode(layer)
    let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
    XCTAssertEqual(layer, decoded)
}

func test_aspectRatio_cropRect_landscapeToSquare() {
    let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)
    let rect = params.cropRect(for: CGSize(width: 200, height: 100))
    // Should crop width to match height
    XCTAssertEqual(rect.width, 100)
    XCTAssertEqual(rect.height, 100)
    XCTAssertEqual(rect.origin.x, 50) // centered
    XCTAssertEqual(rect.origin.y, 0)
}

func test_aspectRatio_cropRect_portraitToSquare() {
    let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)
    let rect = params.cropRect(for: CGSize(width: 100, height: 200))
    // Should crop height to match width
    XCTAssertEqual(rect.width, 100)
    XCTAssertEqual(rect.height, 100)
    XCTAssertEqual(rect.origin.x, 0)
    XCTAssertEqual(rect.origin.y, 50) // centered
}

func test_aspectRatio_cropRect_alreadyMatchingRatio() {
    let params = AspectRatioLayerParams(ratioWidth: 2, ratioHeight: 1)
    let rect = params.cropRect(for: CGSize(width: 200, height: 100))
    // Already 2:1, no crop needed
    XCTAssertEqual(rect.width, 200)
    XCTAssertEqual(rect.height, 100)
}

func test_aspectRatio_cropRect_withOffset() {
    let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1, offsetX: 1.0)
    let rect = params.cropRect(for: CGSize(width: 200, height: 100))
    // Offset 1.0 shifts crop all the way right
    XCTAssertEqual(rect.width, 100)
    XCTAssertEqual(rect.height, 100)
    XCTAssertEqual(rect.origin.x, 100) // fully right
    XCTAssertEqual(rect.origin.y, 0)
}

func test_aspectRatio_cropRect_4by5() {
    let params = AspectRatioLayerParams(ratioWidth: 4, ratioHeight: 5)
    let rect = params.cropRect(for: CGSize(width: 1000, height: 1000))
    // 4:5 = 0.8, square image → crop width to 800
    XCTAssertEqual(rect.width, 800)
    XCTAssertEqual(rect.height, 1000)
    XCTAssertEqual(rect.origin.x, 100) // centered
}

func test_aspectRatio_croppedSize() {
    let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)
    let size = params.croppedSize(for: CGSize(width: 200, height: 100))
    XCTAssertEqual(size.width, 100)
    XCTAssertEqual(size.height, 100)
}
```

**Step 4: Run tests**

Run: `swift test --filter CompositionLayerTests`
Expected: All pass

**Step 5: Commit**

```bash
git add Sources/FramerCore/Models/CompositionLayer.swift Tests/FramerCoreTests/CompositionLayerTests.swift
git commit -m "feat: add AspectRatioLayerParams and CompositionLayer.aspectRatio case"
```

---

### Task 2: Add BorderRenderer processing

**Files:**
- Modify: `Sources/FramerCore/Processing/BorderRenderer.swift:100-175`

**Step 1: Add the case in the main switch**

In `BorderRenderer.swift`, inside the `switch layer` block (~line 100), add a new case before or after `.resize`:

```swift
case .aspectRatio(let params):
    let imageSize = CGSize(width: current.width, height: current.height)
    let cropRect = params.cropRect(for: imageSize)
    guard cropRect.width > 0, cropRect.height > 0 else { i += 1; continue }
    if let cropped = current.cropping(to: cropRect) {
        current = cropped
    }
```

**Step 2: Write the integration test**

In `Tests/FramerCoreTests/CompositionLayerTests.swift`, add:

```swift
func test_aspectRatio_borderRenderer_cropsImage() throws {
    let image = makeTestImage(width: 200, height: 100)
    let layers: [CompositionLayer] = [
        .aspectRatio(AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1))
    ]
    let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
    XCTAssertEqual(result.image.width, 100)
    XCTAssertEqual(result.image.height, 100)
}

func test_aspectRatio_beforeBorder_affectsOutput() throws {
    let image = makeTestImage(width: 200, height: 100)
    let layers: [CompositionLayer] = [
        .aspectRatio(AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)),
        .border(BorderLayerParams(thickness: .pixels(10), color: .white))
    ]
    let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
    // 100x100 crop + 10px border on each side = 120x120
    XCTAssertEqual(result.image.width, 120)
    XCTAssertEqual(result.image.height, 120)
}
```

**Step 3: Run tests**

Run: `swift test --filter CompositionLayerTests`
Expected: All pass

**Step 4: Commit**

```bash
git add Sources/FramerCore/Processing/BorderRenderer.swift Tests/FramerCoreTests/CompositionLayerTests.swift
git commit -m "feat: add aspect ratio cropping in BorderRenderer"
```

---

### Task 3: Add YAML config support

**Files:**
- Modify: `Sources/FramerCore/Presets/YAMLConfig.swift`

**Step 1: Add fields to YAMLLayerSchema**

In `YAMLLayerSchema` struct (~line 28), add:

```swift
var ratio: String?          // e.g. "4:5"
var offset_x: Double?
var offset_y: Double?
```

**Step 2: Add encode case**

In `encodeLayers()` (~line 179), add:

```swift
case .aspectRatio(let p):
    var schema = YAMLLayerSchema(type: "aspect_ratio")
    schema.ratio = "\(p.ratioWidth):\(p.ratioHeight)"
    schema.offset_x = p.offsetX
    schema.offset_y = p.offsetY
    return schema
```

**Step 3: Add decode case**

In `decodeLayers()` (~line 296), add:

```swift
case "aspect_ratio":
    let (rw, rh) = parseRatio(schema.ratio ?? "1:1")
    return .aspectRatio(AspectRatioLayerParams(
        ratioWidth: rw,
        ratioHeight: rh,
        offsetX: schema.offset_x ?? 0,
        offsetY: schema.offset_y ?? 0
    ))
```

**Step 4: Add the ratio parser helper**

Add near the other private helpers in `YAMLConfig`:

```swift
private static func parseRatio(_ str: String) -> (Int, Int) {
    let parts = str.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return (1, 1) }
    return (parts[0], parts[1])
}
```

**Step 5: Run tests**

Run: `swift test`
Expected: All pass (existing YAML tests still work, new layer type supported)

**Step 6: Commit**

```bash
git add Sources/FramerCore/Presets/YAMLConfig.swift
git commit -m "feat: add aspect_ratio layer YAML config support"
```

---

### Task 4: Add CLI support

**Files:**
- Modify: `Sources/FramerCLI/Commands/ProcessCommand.swift`

**Step 1: Check existing CLI pattern**

Read `Sources/FramerCLI/Commands/ProcessCommand.swift` to see how other layer options (border, padding, etc.) are exposed as CLI flags. Add `--aspect-ratio` option if the CLI supports per-layer flags, or confirm YAML-only is sufficient.

**Step 2: Add the flag (if applicable)**

Add an `--aspect-ratio` option following the existing pattern:

```swift
@Option(name: .long, help: "Crop to aspect ratio (e.g. 4:5, 1:1, 16:9)")
var aspectRatio: String?
```

In the config-building section, parse and prepend the aspect ratio layer:

```swift
if let ratioStr = aspectRatio {
    let (rw, rh) = parseRatio(ratioStr)
    layers.insert(.aspectRatio(AspectRatioLayerParams(ratioWidth: rw, ratioHeight: rh)), at: 0)
}
```

**Step 3: Run build**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/FramerCLI/Commands/ProcessCommand.swift
git commit -m "feat: add --aspect-ratio CLI option"
```

---

### Task 5: Add SwiftUI controls

**Files:**
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`

**Step 1: Add to layer menu**

In `addLayerMenu` (~line 52), add a button before the Canvas button:

```swift
Button {
    addLayer(.aspectRatio(AspectRatioLayerParams()))
} label: {
    Label("Aspect Ratio", systemImage: "crop")
}
```

**Step 2: Add controls view**

Add a new `AspectRatioLayerControls` struct (follow the pattern of `ResizeLayerControls` at ~line 680):

```swift
struct AspectRatioLayerControls: View {
    var params: AspectRatioLayerParams
    var onChange: (AspectRatioLayerParams) -> Void

    private let presets: [(String, Int, Int)] = [
        ("1:1", 1, 1),
        ("4:5", 4, 5),
        ("5:4", 5, 4),
        ("3:2", 3, 2),
        ("2:3", 2, 3),
        ("16:9", 16, 9),
        ("9:16", 9, 16),
    ]

    private var isCustom: Bool {
        !presets.contains { $0.1 == params.ratioWidth && $0.2 == params.ratioHeight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preset picker
            HStack {
                Text("Ratio")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: ratioBinding) {
                    ForEach(presets, id: \.0) { preset in
                        Text(preset.0).tag("\(preset.1):\(preset.2)")
                    }
                    Text("Custom").tag("custom")
                }
                .labelsHidden()
            }

            // Custom ratio fields
            if isCustom {
                HStack {
                    Text("Custom")
                        .frame(width: 80, alignment: .leading)
                    TextField("W", value: Binding(
                        get: { params.ratioWidth },
                        set: { update { $0.ratioWidth = max(1, $1) } }
                    ), format: .number)
                    .frame(width: 50)
                    Text(":")
                    TextField("H", value: Binding(
                        get: { params.ratioHeight },
                        set: { update { $0.ratioHeight = max(1, $1) } }
                    ), format: .number)
                    .frame(width: 50)
                }
            }

            // Offset sliders
            HStack {
                Text("Offset X")
                    .frame(width: 80, alignment: .leading)
                Slider(value: Binding(
                    get: { params.offsetX },
                    set: { update { $0.offsetX = $1 } }
                ), in: -1...1)
                Text(String(format: "%.1f", params.offsetX))
                    .monospacedDigit()
                    .frame(width: 30)
            }

            HStack {
                Text("Offset Y")
                    .frame(width: 80, alignment: .leading)
                Slider(value: Binding(
                    get: { params.offsetY },
                    set: { update { $0.offsetY = $1 } }
                ), in: -1...1)
                Text(String(format: "%.1f", params.offsetY))
                    .monospacedDigit()
                    .frame(width: 30)
            }
        }
    }

    private var ratioBinding: Binding<String> {
        Binding(
            get: {
                if isCustom { return "custom" }
                return "\(params.ratioWidth):\(params.ratioHeight)"
            },
            set: { newValue in
                if newValue == "custom" { return }
                if let preset = presets.first(where: { "\($0.1):\($0.2)" == newValue }) {
                    var p = params
                    p.ratioWidth = preset.1
                    p.ratioHeight = preset.2
                    onChange(p)
                }
            }
        )
    }

    private func update(_ transform: (inout AspectRatioLayerParams, _ val: some Any) -> Void) -> (some Any) -> Void {
        // This won't work as a generic — use the direct Binding pattern shown above
        fatalError()
    }

    private func update(_ transform: (inout AspectRatioLayerParams) -> Void) {
        var p = params
        transform(&p)
        onChange(p)
    }
}
```

**Step 3: Wire into LayerRow**

In `layerControls` (~line 268), add:

```swift
case .aspectRatio(let params):
    AspectRatioLayerControls(params: params) { layer = .aspectRatio($0) }
```

In `layerSummary` (~line 289), add:

```swift
case .aspectRatio(let p):
    return "\(p.ratioWidth):\(p.ratioHeight)"
```

**Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add Sources/FramerApp/Editor/LayerListSection.swift
git commit -m "feat: add aspect ratio layer UI controls with presets and offset sliders"
```

---

### Task 6: Final validation

**Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 2: Build check**

Run: `swift build`
Expected: Clean build

**Step 3: Regenerate Xcode project**

Run: `xcodegen generate`

**Step 4: Final commit if any remaining changes**

```bash
git add -A
git commit -m "chore: regenerate Xcode project for aspect ratio layer"
```
