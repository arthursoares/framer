# Code Patterns

> **Updated:** 2026-02-24

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Types | PascalCase | `ProcessingConfig`, `ExifData` |
| Protocols | PascalCase | `Sendable`, `Codable` |
| Functions/Methods | camelCase | `processImage()`, `loadPreset()` |
| Properties | camelCase | `borderStyle`, `captionTemplate` |
| Constants | camelCase (static let) | `static let defaultQuality = 100` |
| Enum cases | camelCase | `.solid`, `.instagram`, `.print` |
| Test methods | `test_unit_behavior` | `test_solidBorder_increasesCanvasSize` |

## Import Order

```swift
// Apple frameworks
import Foundation
import CoreGraphics
import CoreImage
import AppKit

// Third-party
import Yams
import ArgumentParser

// Local modules
import FramerCore
```

## Struct/Model Pattern

```swift
/// Configuration for image processing
public struct ProcessingConfig: Codable, Sendable {
    public var borderStyle: BorderStyle = .solid
    public var borderThickness: BorderSize = .pixels(20)
    public var captionTemplate: String = " - {{mon}} '{{year2}} -"

    public init() {}
}
```

## Test Pattern

```swift
final class FeatureTests: XCTestCase {
    func test_unitUnderTest_expectedBehavior() {
        // Arrange
        let config = ProcessingConfig()

        // Act
        let result = BorderRenderer.render(image: testImage, config: config)

        // Assert
        XCTAssertEqual(result.width, expectedWidth)
        XCTAssertGreaterThan(result.height, testImage.height)
    }
}
```

## Layer Composition Pattern

```swift
// Layers are applied sequentially to build the final image
let layers: [CompositionLayer] = [
    .canvas(width: 3000, height: 2000),
    .border(thickness: .percent(5), fill: .color("#000000")),
    .orientation(.landscape),
    .caption(template: "{{camera}} {{aperture}}", position: .bottom),
    .overlay(kind: .filmDust, blendMode: .screen, opacity: 0.5),
]
```

## Processing Pipeline Pattern

```swift
// FrameProcessor delegates to specialized renderers
let processor = FrameProcessor()

// Preview (synchronous, reduced resolution)
let preview: NSImage = try await processor.previewImage(
    for: url, config: config, maxDimension: 1200
)

// Export (full resolution, writes to disk)
try await processor.processToFile(
    input: inputURL, output: outputURL, config: config
)
```

## Concurrency Pattern

```swift
// @MainActor for UI state
@MainActor
final class AppState: ObservableObject {
    @Published var config = ProcessingConfig()
}

// Sendable types for cross-isolation passing
public struct ProcessingConfig: Codable, Sendable { ... }

// nonisolated + sending for background work
nonisolated func previewImage(...) async throws -> sending NSImage {
    // Process on background, return value crosses isolation
}
```

## Common Patterns

### Error Handling
```swift
enum FramerError: Error, LocalizedError {
    case invalidImage(URL)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage(let url): "Cannot read image: \(url.path)"
        case .exportFailed(let msg): "Export failed: \(msg)"
        }
    }
}
```

### CGImage Creation (Test Helpers)
```swift
func makeTestImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
```

## Anti-Patterns to Avoid

1. **Don't force-unwrap optionals** - Use guard/if-let or throw errors
2. **Don't block the main thread** - Use async/await for processing
3. **Don't use mutable global state** - Pass config explicitly
4. **Don't ignore Sendable warnings** - Mark types Sendable or isolate properly
5. **Don't mix UI and processing** - Keep FramerCore free of AppKit/SwiftUI imports
6. **Don't hardcode paths** - Use URL and FileManager APIs
