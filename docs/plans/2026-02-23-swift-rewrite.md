# Swift Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite framer as a native Swift macOS app + Swift CLI, replacing the existing Go codebase, sharing a `FramerCore` library between both targets.

**Architecture:** SPM multi-target monorepo — `FramerCore` (pure Swift library), `FramerCLI` (swift-argument-parser executable), and `FramerApp` (SwiftUI macOS app linked via Xcode). The Go source is deleted once the Swift CLI reaches feature parity.

**Tech Stack:** Swift 5.10+, SwiftUI, Core Image, vImage, ImageIO, CoreText, NSFont, Yams (YAML), swift-argument-parser, XCTest, macOS 14+

---

## Phase 1: Project Foundation

### Task 1: Initialize SPM Package Structure

**Files:**
- Create: `Package.swift`
- Create: `Sources/FramerCore/.gitkeep`
- Create: `Sources/FramerCLI/.gitkeep`
- Delete: `framer.go`, `fonts.go` (Go source — remove after Swift CLI is complete in Task 12)

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "framer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FramerCore", targets: ["FramerCore"]),
        .executable(name: "framer", targets: ["FramerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "FramerCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "FramerCLI",
            dependencies: [
                "FramerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "FramerCoreTests",
            dependencies: ["FramerCore"],
            resources: [.copy("Resources")]
        ),
    ]
)
```

**Step 2: Create directory structure**

```bash
mkdir -p Sources/FramerCore/{Models,Processing,EXIF,Presets}
mkdir -p Sources/FramerCLI
mkdir -p Tests/FramerCoreTests/Resources
touch Sources/FramerCore/Models/.gitkeep
touch Sources/FramerCLI/.gitkeep
```

**Step 3: Resolve dependencies**

```bash
swift package resolve
```
Expected: Dependencies downloaded, `.build/` created, `Package.resolved` generated.

**Step 4: Verify it compiles**

```bash
swift build
```
Expected: Build succeeds (no source files yet, just empty targets).

**Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources/ Tests/
git commit -m "feat: initialize Swift SPM package structure"
```

---

### Task 2: FramerCore — Core Models

**Files:**
- Create: `Sources/FramerCore/Models/ProcessingConfig.swift`
- Create: `Sources/FramerCore/Models/ExifData.swift`
- Create: `Sources/FramerCore/Models/Preset.swift`
- Create: `Tests/FramerCoreTests/ProcessingConfigTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/FramerCoreTests/ProcessingConfigTests.swift
import XCTest
@testable import FramerCore

final class ProcessingConfigTests: XCTestCase {
    func test_defaultConfig_hasSolidBorderStyle() {
        let config = ProcessingConfig.default
        XCTAssertEqual(config.borderStyle, .solid)
    }

    func test_borderColor_roundtripsHex() throws {
        let color = try CodableColor(hex: "#FF5733")
        XCTAssertEqual(color.hex, "#FF5733")
    }

    func test_borderSize_pixels_roundtripsJSON() throws {
        let size = BorderSize.pixels(50)
        let data = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(BorderSize.self, from: data)
        XCTAssertEqual(size, decoded)
    }

    func test_borderSize_percent_roundtripsJSON() throws {
        let size = BorderSize.percent(5.0)
        let data = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(BorderSize.self, from: data)
        XCTAssertEqual(size, decoded)
    }

    func test_processingConfig_roundtripsJSON() throws {
        let config = ProcessingConfig.default
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProcessingConfig.self, from: data)
        XCTAssertEqual(config.borderStyle, decoded.borderStyle)
    }
}
```

**Step 2: Run to verify failure**

```bash
swift test --filter ProcessingConfigTests
```
Expected: FAIL — types not found.

**Step 3: Implement models**

```swift
// Sources/FramerCore/Models/ProcessingConfig.swift
import Foundation

public enum BorderStyle: String, Codable, Equatable {
    case solid
    case instagram
}

public enum BorderSize: Codable, Equatable {
    case pixels(Int)
    case percent(Double)

    // Raw string from YAML: "50" → .pixels(50), "5%" → .percent(5.0)
    public init(string: String) {
        if string.hasSuffix("%"), let v = Double(string.dropLast()) {
            self = .percent(v)
        } else if let v = Int(string) {
            self = .pixels(v)
        } else {
            self = .pixels(20) // fallback default
        }
    }

    public func resolved(relativeTo dimension: Int) -> Int {
        switch self {
        case .pixels(let px): return px
        case .percent(let pct): return Int(Double(dimension) * pct / 100.0)
        }
    }
}

public struct CodableColor: Codable, Equatable {
    public let hex: String

    public init(hex: String) throws {
        let cleaned = hex.hasPrefix("#") ? hex : "#" + hex
        guard cleaned.count == 7,
              cleaned.dropFirst().allSatisfy({ $0.isHexDigit }) else {
            throw FramerError.invalidColor(hex)
        }
        self.hex = cleaned.uppercased()
    }

    public var red: Double { Double(UInt8(hex.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255 }
    public var green: Double { Double(UInt8(hex.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255 }
    public var blue: Double { Double(UInt8(hex.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255 }
}

public enum CaptionMode: Codable, Equatable {
    case template(String)
    case custom(String)
    case none
}

public enum FontSize: Codable, Equatable {
    case auto
    case fixed(Int)
}

public enum OutputFormat: Codable, Equatable {
    case jpeg(quality: Int)
    case png
}

public struct ProcessingConfig: Codable, Equatable {
    public var borderStyle: BorderStyle
    public var borderThickness: BorderSize
    public var borderColor: CodableColor
    public var padding: Int
    public var captionMode: CaptionMode
    public var fontName: String
    public var fontSize: FontSize
    public var fontColor: CodableColor
    public var outputFormat: OutputFormat
    public var instagramMaxSize: Int
    public var postProcess: String?

    public static let `default` = ProcessingConfig(
        borderStyle: .solid,
        borderThickness: .pixels(20),
        borderColor: try! CodableColor(hex: "#FFFFFF"),
        padding: 150,
        captionMode: .template(" - {{mon}} '{{year2}} -"),
        fontName: "Courier New Bold",
        fontSize: .auto,
        fontColor: try! CodableColor(hex: "#000000"),
        outputFormat: .jpeg(quality: 100),
        instagramMaxSize: 1000,
        postProcess: nil
    )
}

public enum FramerError: LocalizedError {
    case invalidColor(String)
    case invalidImage(URL)
    case exifReadFailed(URL)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidColor(let s): return "Invalid color: \(s)"
        case .invalidImage(let u): return "Cannot load image: \(u.path)"
        case .exifReadFailed(let u): return "Cannot read EXIF: \(u.path)"
        case .unsupportedFormat(let s): return "Unsupported format: \(s)"
        }
    }
}
```

```swift
// Sources/FramerCore/Models/ExifData.swift
import Foundation

public struct ExifData {
    public var dateTime: Date?
    public var camera: String?
    public var lens: String?
    public var iso: String?
    public var aperture: String?
    public var shutterSpeed: String?
    public var focalLength: String?

    public init() {}

    /// Resolves a caption template placeholder
    public func resolve(template: String) -> String {
        var result = template
        let cal = Calendar.current
        let date = dateTime ?? Date()
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN",
                          "JUL","AUG","SEP","OCT","NOV","DEC"]
        let mon = month >= 1 && month <= 12 ? monthNames[month-1] : "???"

        result = result.replacingOccurrences(of: "{{year}}", with: String(year))
        result = result.replacingOccurrences(of: "{{year2}}", with: String(format: "%02d", year % 100))
        result = result.replacingOccurrences(of: "{{month}}", with: String(format: "%02d", month))
        result = result.replacingOccurrences(of: "{{mon}}", with: mon)
        result = result.replacingOccurrences(of: "{{day}}", with: String(format: "%02d", day))
        result = result.replacingOccurrences(of: "{{camera}}", with: camera ?? "")
        result = result.replacingOccurrences(of: "{{lens}}", with: lens ?? "")
        result = result.replacingOccurrences(of: "{{iso}}", with: iso.map { "ISO \($0)" } ?? "")
        result = result.replacingOccurrences(of: "{{aperture}}", with: aperture.map { "f/\($0)" } ?? "")
        result = result.replacingOccurrences(of: "{{shutter}}", with: shutterSpeed ?? "")
        result = result.replacingOccurrences(of: "{{focal}}", with: focalLength.map { "\($0)mm" } ?? "")
        return result
    }
}
```

```swift
// Sources/FramerCore/Models/Preset.swift
import Foundation

public struct Preset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var config: ProcessingConfig
    public var thumbnailData: Data? // PNG thumbnail of the preset applied to a sample

    public init(id: UUID = .init(), name: String, config: ProcessingConfig, thumbnailData: Data? = nil) {
        self.id = id
        self.name = name
        self.config = config
        self.thumbnailData = thumbnailData
    }
}
```

**Step 4: Run tests to verify passing**

```bash
swift test --filter ProcessingConfigTests
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Models/ Tests/FramerCoreTests/ProcessingConfigTests.swift
git commit -m "feat: add FramerCore models (ProcessingConfig, ExifData, Preset)"
```

---

### Task 3: FramerCore — EXIF Reader

**Files:**
- Create: `Sources/FramerCore/EXIF/EXIFReader.swift`
- Create: `Tests/FramerCoreTests/EXIFReaderTests.swift`
- Add: `Tests/FramerCoreTests/Resources/sample.jpg` (copy from `docs/sample.jpg`)

**Step 1: Copy sample image for tests**

```bash
cp docs/sample.jpg Tests/FramerCoreTests/Resources/sample.jpg
```

**Step 2: Write failing tests**

```swift
// Tests/FramerCoreTests/EXIFReaderTests.swift
import XCTest
@testable import FramerCore

final class EXIFReaderTests: XCTestCase {
    var sampleURL: URL {
        Bundle.module.url(forResource: "sample", withExtension: "jpg", subdirectory: "Resources")!
    }

    func test_readExif_returnsData() throws {
        let exif = try EXIFReader.read(from: sampleURL)
        // sample.jpg should have some EXIF — at minimum dateTime or camera
        XCTAssertNotNil(exif)
    }

    func test_readExif_nonexistentFile_throws() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        XCTAssertThrowsError(try EXIFReader.read(from: url))
    }
}
```

**Step 3: Run to verify failure**

```bash
swift test --filter EXIFReaderTests
```
Expected: FAIL — EXIFReader not found.

**Step 4: Implement EXIFReader**

```swift
// Sources/FramerCore/EXIF/EXIFReader.swift
import Foundation
import ImageIO

public enum EXIFReader {
    public static func read(from url: URL) throws -> ExifData {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw FramerError.exifReadFailed(url)
        }

        var data = ExifData()
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        _ = gps // reserved for future use

        // Date
        if let dateStr = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            data.dateTime = Self.parseDate(dateStr)
        } else if let dateStr = tiff?[kCGImagePropertyTIFFDateTime as String] as? String {
            data.dateTime = Self.parseDate(dateStr)
        }

        // Camera
        data.camera = tiff?[kCGImagePropertyTIFFModel as String] as? String

        // Lens
        data.lens = exif?[kCGImagePropertyExifLensModel as String] as? String

        // ISO
        if let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
           let iso = isoArray.first {
            data.iso = String(iso)
        }

        // Aperture
        if let fn = exif?[kCGImagePropertyExifFNumber as String] as? Double {
            data.aperture = String(format: "%.1f", fn)
        }

        // Shutter speed
        if let exp = exif?[kCGImagePropertyExifExposureTime as String] as? Double {
            if exp >= 1 {
                data.shutterSpeed = "\(Int(exp))s"
            } else {
                let denom = Int(round(1.0 / exp))
                data.shutterSpeed = "1/\(denom)"
            }
        }

        // Focal length
        if let fl = exif?[kCGImagePropertyExifFocalLength as String] as? Double {
            data.focalLength = String(format: "%.0f", fl)
        }

        return data
    }

    private static func parseDate(_ string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: string)
    }
}
```

**Step 5: Run tests**

```bash
swift test --filter EXIFReaderTests
```
Expected: All PASS.

**Step 6: Commit**

```bash
git add Sources/FramerCore/EXIF/ Tests/FramerCoreTests/EXIFReaderTests.swift Tests/FramerCoreTests/Resources/
git commit -m "feat: add EXIFReader using ImageIO framework"
```

---

### Task 4: FramerCore — Border Renderer

**Files:**
- Create: `Sources/FramerCore/Processing/BorderRenderer.swift`
- Create: `Tests/FramerCoreTests/BorderRendererTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/FramerCoreTests/BorderRendererTests.swift
import XCTest
import CoreImage
@testable import FramerCore

final class BorderRendererTests: XCTestCase {
    func makeTestImage(width: Int = 100, height: Int = 80) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func test_solidBorder_increasesCanvasSize() throws {
        let image = makeTestImage()
        let config = ProcessingConfig.default // 20px border, 150px padding
        let result = try BorderRenderer.applyBorder(to: image, config: config, style: .solid)
        // Canvas should be larger than original
        XCTAssertGreaterThan(result.width, image.width)
        XCTAssertGreaterThan(result.height, image.height)
    }

    func test_solidBorder_pixelThickness_correctSize() throws {
        let image = makeTestImage(width: 100, height: 100)
        var config = ProcessingConfig.default
        config.borderThickness = .pixels(10)
        config.padding = 0
        let result = try BorderRenderer.applyBorder(to: image, config: config, style: .solid)
        XCTAssertEqual(result.width, 120) // 100 + 2*10
        XCTAssertEqual(result.height, 120)
    }

    func test_instagramBorder_hasFixedAspectRatio() throws {
        let image = makeTestImage(width: 800, height: 600)
        let config = ProcessingConfig.default
        let result = try BorderRenderer.applyBorder(to: image, config: config, style: .instagram)
        // Instagram is 4:5 = 1080x1350 scaled
        let ratio = Double(result.width) / Double(result.height)
        XCTAssertEqual(ratio, 1080.0 / 1350.0, accuracy: 0.01)
    }
}
```

**Step 2: Run to verify failure**

```bash
swift test --filter BorderRendererTests
```
Expected: FAIL — BorderRenderer not found.

**Step 3: Implement BorderRenderer**

```swift
// Sources/FramerCore/Processing/BorderRenderer.swift
import Foundation
import CoreImage
import CoreGraphics

public enum BorderRenderer {
    // Instagram frame constants (4:5)
    static let instagramWidth = 1080
    static let instagramHeight = 1350

    public static func applyBorder(
        to image: CGImage,
        config: ProcessingConfig,
        style: BorderStyle
    ) throws -> CGImage {
        switch style {
        case .solid:
            return try applySolidBorder(to: image, config: config)
        case .instagram:
            return try applyInstagramBorder(to: image, config: config)
        }
    }

    // MARK: - Solid Border

    private static func applySolidBorder(to image: CGImage, config: ProcessingConfig) throws -> CGImage {
        let borderPx = config.borderThickness.resolved(relativeTo: min(image.width, image.height))
        let totalH = image.height + 2 * borderPx + 2 * config.padding
        let totalW = image.width + 2 * borderPx + 2 * config.padding

        let bgColor = config.borderColor.cgColor

        guard let ctx = CGContext(data: nil,
                                  width: totalW,
                                  height: totalH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Fill background
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: totalH))

        // Draw image centered
        let imageX = borderPx + config.padding
        let imageY = borderPx + config.padding
        ctx.draw(image, in: CGRect(x: imageX, y: imageY, width: image.width, height: image.height))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Instagram Border

    private static func applyInstagramBorder(to image: CGImage, config: ProcessingConfig) throws -> CGImage {
        let maxSize = config.instagramMaxSize

        // Scale image to fit within maxSize
        let scale = min(Double(maxSize) / Double(image.width), Double(maxSize) / Double(image.height))
        let scaledW = Int(Double(image.width) * scale)
        let scaledH = Int(Double(image.height) * scale)

        // Canvas is Instagram 4:5 ratio, scaled to fit maxSize
        let canvasScale = Double(maxSize) / Double(max(instagramWidth, instagramHeight))
        let canvasW = Int(Double(instagramWidth) * canvasScale)
        let canvasH = Int(Double(instagramHeight) * canvasScale)

        let bgColor = config.borderColor.cgColor

        guard let ctx = CGContext(data: nil,
                                  width: canvasW,
                                  height: canvasH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Fill background
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        // Center image
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        let drawW = scaledW - 2 * borderPx
        let drawH = scaledH - 2 * borderPx
        let drawX = (canvasW - drawW) / 2
        let drawY = (canvasH - drawH) / 2

        ctx.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }
}

// MARK: - CodableColor → CGColor

extension CodableColor {
    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
```

**Step 4: Run tests**

```bash
swift test --filter BorderRendererTests
```
Expected: All PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/BorderRenderer.swift Tests/FramerCoreTests/BorderRendererTests.swift
git commit -m "feat: add BorderRenderer (solid and instagram styles)"
```

---

### Task 5: FramerCore — Caption Renderer

**Files:**
- Create: `Sources/FramerCore/Processing/CaptionRenderer.swift`
- Create: `Tests/FramerCoreTests/CaptionRendererTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/FramerCoreTests/CaptionRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class CaptionRendererTests: XCTestCase {
    func makeTestImage(width: Int = 400, height: Int = 500) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func test_renderCaption_doesNotChangeImageSize() throws {
        let image = makeTestImage()
        var config = ProcessingConfig.default
        config.captionMode = .custom("TEST CAPTION")
        config.fontName = "Courier New"
        config.fontSize = .fixed(20)
        let result = try CaptionRenderer.renderCaption(on: image, config: config, exif: ExifData())
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_renderCaption_noneMode_returnsOriginal() throws {
        let image = makeTestImage()
        var config = ProcessingConfig.default
        config.captionMode = .none
        let result = try CaptionRenderer.renderCaption(on: image, config: config, exif: ExifData())
        // Same dimensions
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }
}
```

**Step 2: Run to verify failure**

```bash
swift test --filter CaptionRendererTests
```
Expected: FAIL.

**Step 3: Implement CaptionRenderer**

```swift
// Sources/FramerCore/Processing/CaptionRenderer.swift
import Foundation
import CoreGraphics
import CoreText
import AppKit

public enum CaptionRenderer {
    public static func renderCaption(
        on image: CGImage,
        config: ProcessingConfig,
        exif: ExifData
    ) throws -> CGImage {
        // Resolve caption text
        let text: String
        switch config.captionMode {
        case .none:
            return image
        case .custom(let s):
            text = s
        case .template(let t):
            text = exif.resolve(template: t)
        }

        guard let ctx = CGContext(data: nil,
                                  width: image.width,
                                  height: image.height,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Draw base image
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // Resolve font size
        let borderPx = config.borderThickness.resolved(relativeTo: min(image.width, image.height))
        let fontSize: CGFloat
        switch config.fontSize {
        case .fixed(let pts):
            fontSize = CGFloat(pts)
        case .auto:
            fontSize = autoFontSize(borderPx: borderPx)
        }

        // Build attributed string
        let font = NSFont(name: config.fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: config.fontColor.cgColor) ?? .black,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        // Measure text
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        // Position: centered horizontally, in bottom border area
        let x = (CGFloat(image.width) - bounds.width) / 2
        let y = (CGFloat(borderPx) - bounds.height) / 2

        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    private static func autoFontSize(borderPx: Int) -> CGFloat {
        switch borderPx {
        case ..<40: return CGFloat(borderPx) * 0.5
        case 40..<80: return CGFloat(borderPx) * 0.7
        default: return CGFloat(borderPx) * 0.9
        }
    }
}
```

**Step 4: Run tests**

```bash
swift test --filter CaptionRendererTests
```
Expected: All PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/CaptionRenderer.swift Tests/FramerCoreTests/CaptionRendererTests.swift
git commit -m "feat: add CaptionRenderer using CoreText and system fonts"
```

---

### Task 6: FramerCore — Frame Processor (Pipeline)

**Files:**
- Create: `Sources/FramerCore/Processing/FrameProcessor.swift`
- Create: `Tests/FramerCoreTests/FrameProcessorTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/FramerCoreTests/FrameProcessorTests.swift
import XCTest
@testable import FramerCore

final class FrameProcessorTests: XCTestCase {
    var sampleURL: URL {
        Bundle.module.url(forResource: "sample", withExtension: "jpg", subdirectory: "Resources")!
    }

    func test_previewImage_returnsNSImage() async throws {
        let processor = FrameProcessor()
        let result = try await processor.previewImage(for: sampleURL, config: .default)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result.size.width, 0)
    }

    func test_previewImage_maxDimension1200() async throws {
        let processor = FrameProcessor()
        let result = try await processor.previewImage(for: sampleURL, config: .default)
        let maxDim = max(result.size.width, result.size.height)
        XCTAssertLessThanOrEqual(maxDim, 1200)
    }

    func test_processToFile_createsOutputFile() async throws {
        let processor = FrameProcessor()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer_test_\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await processor.process(input: sampleURL, output: outputURL, config: .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
```

**Step 2: Run to verify failure**

```bash
swift test --filter FrameProcessorTests
```
Expected: FAIL.

**Step 3: Implement FrameProcessor**

```swift
// Sources/FramerCore/Processing/FrameProcessor.swift
import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Orchestrates the full image processing pipeline.
/// Runs on a background actor to keep the main thread free.
public actor FrameProcessor {
    public init() {}

    // MARK: - Preview (downscaled, no disk I/O)

    public func previewImage(for url: URL, config: ProcessingConfig) throws -> NSImage {
        let cgImage = try loadImage(from: url)
        let exif = (try? EXIFReader.read(from: url)) ?? ExifData()

        let framed = try BorderRenderer.applyBorder(to: cgImage, config: config, style: config.borderStyle)
        let captioned = try CaptionRenderer.renderCaption(on: framed, config: config, exif: exif)
        let preview = downscale(captioned, maxDimension: 1200)

        return NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
    }

    // MARK: - Full Export

    public func process(input: URL, output: URL, config: ProcessingConfig) throws {
        let cgImage = try loadImage(from: input)
        let exif = (try? EXIFReader.read(from: input)) ?? ExifData()

        let framed = try BorderRenderer.applyBorder(to: cgImage, config: config, style: config.borderStyle)
        let captioned = try CaptionRenderer.renderCaption(on: framed, config: config, exif: exif)

        try encode(captioned, to: output, format: config.outputFormat)
    }

    // MARK: - Helpers

    private func loadImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FramerError.invalidImage(url)
        }
        return image
    }

    private func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let w = image.width, h = image.height
        guard max(w, h) > maxDimension else { return image }
        let scale = Double(maxDimension) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    private func encode(_ image: CGImage, to url: URL, format: OutputFormat) throws {
        let utType: CFString
        var options: [CFString: Any] = [:]

        switch format {
        case .jpeg(let quality):
            utType = "public.jpeg" as CFString
            options[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100.0
        case .png:
            utType = "public.png" as CFString
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw FramerError.invalidImage(url)
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FramerError.invalidImage(url)
        }
    }
}
```

**Step 4: Run tests**

```bash
swift test --filter FrameProcessorTests
```
Expected: All PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/FrameProcessor.swift Tests/FramerCoreTests/FrameProcessorTests.swift
git commit -m "feat: add FrameProcessor pipeline (preview + export)"
```

---

### Task 7: FramerCore — Preset Store (YAML + iCloud)

**Files:**
- Create: `Sources/FramerCore/Presets/PresetStore.swift`
- Create: `Sources/FramerCore/Presets/YAMLConfig.swift`
- Create: `Tests/FramerCoreTests/PresetStoreTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/FramerCoreTests/PresetStoreTests.swift
import XCTest
@testable import FramerCore

final class PresetStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer_preset_test_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_saveAndLoad_preset() throws {
        let store = PresetStore(directory: tempDir)
        let preset = Preset(name: "My Preset", config: .default)
        try store.save(preset)

        let loaded = try store.load(id: preset.id)
        XCTAssertEqual(loaded.name, preset.name)
        XCTAssertEqual(loaded.config.borderStyle, preset.config.borderStyle)
    }

    func test_listPresets_returnsAll() throws {
        let store = PresetStore(directory: tempDir)
        let p1 = Preset(name: "A", config: .default)
        let p2 = Preset(name: "B", config: .default)
        try store.save(p1)
        try store.save(p2)

        let all = try store.list()
        XCTAssertEqual(all.count, 2)
    }

    func test_deletePreset_removesIt() throws {
        let store = PresetStore(directory: tempDir)
        let preset = Preset(name: "Delete Me", config: .default)
        try store.save(preset)
        try store.delete(id: preset.id)

        XCTAssertThrowsError(try store.load(id: preset.id))
    }

    func test_yamlConfig_roundtrips() throws {
        let config = ProcessingConfig.default
        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)
        XCTAssertEqual(config.borderStyle, decoded.borderStyle)
        XCTAssertEqual(config.padding, decoded.padding)
    }
}
```

**Step 2: Run to verify failure**

```bash
swift test --filter PresetStoreTests
```
Expected: FAIL.

**Step 3: Implement PresetStore and YAMLConfig**

```swift
// Sources/FramerCore/Presets/PresetStore.swift
import Foundation

public final class PresetStore {
    private let directory: URL

    /// Default initializer — uses ~/Library/Application Support/Framer/presets/
    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Framer/presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(directory: dir)
    }

    /// Testable initializer with custom directory
    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ preset: Preset) throws {
        let url = directory.appendingPathComponent("\(preset.id.uuidString).json")
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url)
    }

    public func load(id: UUID) throws -> Preset {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Preset.self, from: data)
    }

    public func list() throws -> [Preset] {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    public func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }
}
```

```swift
// Sources/FramerCore/Presets/YAMLConfig.swift
import Foundation
import Yams

/// Reads and writes .framer.yaml config files — compatible with the Go CLI schema.
public enum YAMLConfig {
    struct YAMLSchema: Codable {
        var border_style: String?
        var border_thickness: String?
        var border_color: String?
        var padding: Int?
        var caption: String?
        var caption_template: String?
        var no_caption: Bool?
        var font_name: String?
        var font_size: String?
        var font_color: String?
        var jpeg_quality: Int?
        var output_format: String?
        var instagram_max_size: Int?
        var post_process: String?
    }

    public static func encode(_ config: ProcessingConfig) throws -> String {
        var schema = YAMLSchema()
        schema.border_style = config.borderStyle.rawValue
        switch config.borderThickness {
        case .pixels(let px): schema.border_thickness = String(px)
        case .percent(let pct): schema.border_thickness = "\(pct)%"
        }
        schema.border_color = config.borderColor.hex
        schema.padding = config.padding
        switch config.captionMode {
        case .template(let t): schema.caption_template = t
        case .custom(let s): schema.caption = s
        case .none: schema.no_caption = true
        }
        schema.font_name = config.fontName
        switch config.fontSize {
        case .auto: break
        case .fixed(let s): schema.font_size = String(s)
        }
        schema.font_color = config.fontColor.hex
        switch config.outputFormat {
        case .jpeg(let q):
            schema.output_format = "jpeg"
            schema.jpeg_quality = q
        case .png:
            schema.output_format = "png"
        }
        schema.instagram_max_size = config.instagramMaxSize
        schema.post_process = config.postProcess
        return try Yams.dump(object: schema)
    }

    public static func decode(_ yaml: String) throws -> ProcessingConfig {
        let schema = try Yams.load(yaml: yaml, as: YAMLSchema.self)
        var config = ProcessingConfig.default

        if let s = schema?.border_style { config.borderStyle = BorderStyle(rawValue: s) ?? .solid }
        if let t = schema?.border_thickness { config.borderThickness = BorderSize(string: t) }
        if let c = schema?.border_color { config.borderColor = (try? CodableColor(hex: c)) ?? config.borderColor }
        if let p = schema?.padding { config.padding = p }
        if schema?.no_caption == true {
            config.captionMode = .none
        } else if let t = schema?.caption_template {
            config.captionMode = .template(t)
        } else if let s = schema?.caption {
            config.captionMode = .custom(s)
        }
        if let fn = schema?.font_name { config.fontName = fn }
        if let fs = schema?.font_size, let i = Int(fs) { config.fontSize = .fixed(i) }
        if let fc = schema?.font_color { config.fontColor = (try? CodableColor(hex: fc)) ?? config.fontColor }
        if let q = schema?.jpeg_quality { config.outputFormat = .jpeg(quality: q) }
        if schema?.output_format == "png" { config.outputFormat = .png }
        if let m = schema?.instagram_max_size { config.instagramMaxSize = m }
        config.postProcess = schema?.post_process

        return config
    }

    /// Loads config from a file URL
    public static func load(from url: URL) throws -> ProcessingConfig {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try decode(yaml)
    }

    /// Finds and loads .framer.yaml using priority order (same as Go CLI)
    public static func loadDefault(configPath: URL? = nil, preset: String? = nil) -> ProcessingConfig {
        // 1. Explicit --config path
        if let path = configPath, let config = try? load(from: path) { return config }

        // 2. --preset from ~/Library/Application Support/Framer/presets/<name>.yaml
        if let name = preset {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let presetURL = appSupport.appendingPathComponent("Framer/presets/\(name).yaml")
            if let config = try? load(from: presetURL) { return config }
        }

        // 3. ./.framer.yaml (current directory)
        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".framer.yaml")
        if let config = try? load(from: localURL) { return config }

        // 4. ~/.config/framer/default.yaml
        let homeConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/framer/default.yaml")
        if let config = try? load(from: homeConfig) { return config }

        return .default
    }
}
```

**Step 4: Run tests**

```bash
swift test --filter PresetStoreTests
```
Expected: All PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Presets/ Tests/FramerCoreTests/PresetStoreTests.swift
git commit -m "feat: add PresetStore and YAMLConfig (YAML read/write, CLI-compatible schema)"
```

---

## Phase 2: FramerCLI

### Task 8: FramerCLI — Process Command

**Files:**
- Create: `Sources/FramerCLI/main.swift`
- Create: `Sources/FramerCLI/Commands/ProcessCommand.swift`
- Create: `Sources/FramerCLI/Commands/PresetsCommand.swift`
- Create: `Sources/FramerCLI/Commands/FontsCommand.swift`

**Step 1: Implement main.swift**

```swift
// Sources/FramerCLI/main.swift
import ArgumentParser

@main
struct Framer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "framer",
        abstract: "Add borders and captions to photos",
        subcommands: [ProcessCommand.self, PresetsCommand.self, FontsCommand.self],
        defaultSubcommand: ProcessCommand.self
    )
}
```

**Step 2: Implement ProcessCommand**

```swift
// Sources/FramerCLI/Commands/ProcessCommand.swift
import ArgumentParser
import Foundation
import FramerCore

struct ProcessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Process one or more images"
    )

    @Option(name: .shortAndLong, help: "Input image or directory") var input: String
    @Option(name: .shortAndLong, help: "Output directory") var output: String?
    @Option(name: [.long, .customShort("f")], help: "Output file path (single file only)") var outputFile: String?
    @Option(help: "Border style: solid or instagram") var borderStyle: String?
    @Option(name: [.long, .customShort("t")], help: "Border thickness (e.g. 20 or 5%)") var borderThickness: String?
    @Option(help: "Border color (hex, e.g. #FFFFFF)") var borderColor: String?
    @Option(help: "Padding in pixels") var padding: Int?
    @Option(help: "Caption text") var caption: String?
    @Option(help: "Caption template with {{field}} placeholders") var captionTemplate: String?
    @Flag(help: "Disable caption") var noCaption = false
    @Option(help: "Font name") var fontName: String?
    @Option(help: "Font size in pixels") var fontSize: Int?
    @Option(help: "Font color (hex)") var fontColor: String?
    @Option(name: [.long, .customShort("q")], help: "JPEG quality (60-100)") var quality: Int?
    @Option(help: "Output format: jpeg or png") var outputFormat: String?
    @Option(help: "Config YAML file path") var config: String?
    @Option(help: "Preset name") var preset: String?
    @Option(name: [.long, .customShort("w")], help: "Number of workers") var workers: Int?
    @Option(help: "Post-process command ({file} = output path)") var postProcess: String?

    mutating func run() async throws {
        // Build config with priority: CLI flags → config file → preset → .framer.yaml → defaults
        let configURL = config.map { URL(fileURLWithPath: $0) }
        var cfg = YAMLConfig.loadDefault(configPath: configURL, preset: preset)

        // Apply CLI overrides
        if let s = borderStyle { cfg.borderStyle = BorderStyle(rawValue: s) ?? cfg.borderStyle }
        if let t = borderThickness { cfg.borderThickness = BorderSize(string: t) }
        if let c = borderColor, let color = try? CodableColor(hex: c) { cfg.borderColor = color }
        if let p = padding { cfg.padding = p }
        if noCaption { cfg.captionMode = .none }
        else if let t = captionTemplate { cfg.captionMode = .template(t) }
        else if let c = caption { cfg.captionMode = .custom(c) }
        if let fn = fontName { cfg.fontName = fn }
        if let fs = fontSize { cfg.fontSize = .fixed(fs) }
        if let fc = fontColor, let color = try? CodableColor(hex: fc) { cfg.fontColor = color }
        if let q = quality { cfg.outputFormat = .jpeg(quality: q) }
        if outputFormat == "png" { cfg.outputFormat = .png }
        if let pp = postProcess { cfg.postProcess = pp }

        let inputURL = URL(fileURLWithPath: input)
        let isDir = inputURL.hasDirectoryPath

        let processor = FrameProcessor()
        let workerCount = workers ?? ProcessInfo.processInfo.processorCount

        if isDir {
            try await batchProcess(directory: inputURL, outputDir: output!, config: cfg, workers: workerCount)
        } else {
            let outURL: URL
            if let f = outputFile {
                outURL = URL(fileURLWithPath: f)
            } else {
                let outDir = URL(fileURLWithPath: output!)
                outURL = outputName(for: inputURL, in: outDir, style: cfg.borderStyle, format: cfg.outputFormat)
            }
            try await processor.process(input: inputURL, output: outURL, config: cfg)
            try runPostProcess(cfg.postProcess, file: outURL)
            print("✓ \(outURL.path)")
        }
    }

    private func batchProcess(directory: URL, outputDir: String, config: ProcessingConfig, workers: Int) async throws {
        let fm = FileManager.default
        let outDir = URL(fileURLWithPath: outputDir)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let images = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["jpg","jpeg","png","tiff","heic"].contains($0.pathExtension.lowercased()) }

        let total = images.count
        var done = 0
        let lock = NSLock()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = images.makeIterator()
            for _ in 0..<min(workers, total) {
                if let url = pending.next() {
                    group.addTask {
                        let outURL = outputName(for: url, in: outDir, style: config.borderStyle, format: config.outputFormat)
                        let processor = FrameProcessor()
                        try await processor.process(input: url, output: outURL, config: config)
                        try runPostProcess(config.postProcess, file: outURL)
                        lock.lock(); done += 1; let d = done; lock.unlock()
                        print("[\(d)/\(total)] \(url.lastPathComponent)")
                    }
                }
            }
            for try await _ in group {
                if let url = pending.next() {
                    group.addTask {
                        let outURL = outputName(for: url, in: outDir, style: config.borderStyle, format: config.outputFormat)
                        let processor = FrameProcessor()
                        try await processor.process(input: url, output: outURL, config: config)
                        try runPostProcess(config.postProcess, file: outURL)
                        lock.lock(); done += 1; let d = done; lock.unlock()
                        print("[\(d)/\(total)] \(url.lastPathComponent)")
                    }
                }
            }
        }
    }

    private func outputName(for input: URL, in dir: URL, style: BorderStyle, format: OutputFormat) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let ext = format == .png ? "png" : "jpg"
        let suffix = style == .instagram ? "_instagram" : "_solid"
        return dir.appendingPathComponent("\(stem)\(suffix).\(ext)")
    }
}

private func runPostProcess(_ command: String?, file: URL) throws {
    guard let cmd = command, !cmd.isEmpty else { return }
    let quoted = file.path.contains(" ") ? "\"\(file.path)\"" : file.path
    let resolved = cmd.replacingOccurrences(of: "{file}", with: quoted)
    let proc = Process()
    proc.launchPath = "/bin/sh"
    proc.arguments = ["-c", resolved]
    try proc.run()
    proc.waitUntilExit()
}
```

**Step 3: Implement PresetsCommand and FontsCommand**

```swift
// Sources/FramerCLI/Commands/PresetsCommand.swift
import ArgumentParser
import Foundation
import FramerCore

struct PresetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "presets",
        abstract: "Manage presets",
        subcommands: [ListPresets.self, ApplyPreset.self]
    )

    struct ListPresets: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        func run() throws {
            let store = PresetStore()
            let presets = try store.list()
            if presets.isEmpty { print("No presets saved."); return }
            for p in presets { print("  \(p.name) (\(p.id))") }
        }
    }

    struct ApplyPreset: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "apply")
        @Argument var name: String
        @Option(name: .shortAndLong) var input: String
        @Option(name: .shortAndLong) var output: String?
        func run() async throws {
            var cmd = ProcessCommand()
            cmd.input = input
            cmd.output = output ?? "."
            cmd.preset = name
            try await cmd.run()
        }
    }
}
```

```swift
// Sources/FramerCLI/Commands/FontsCommand.swift
import ArgumentParser
import AppKit

struct FontsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fonts",
        abstract: "List available system fonts"
    )
    @Flag(help: "Show all fonts, not just monospaced") var all = false

    func run() {
        let fonts = NSFontManager.shared.availableFontFamilies
        let filtered = all ? fonts : fonts.filter { isMonospaced($0) }
        filtered.sorted().forEach { print($0) }
    }

    private func isMonospaced(_ family: String) -> Bool {
        guard let font = NSFont(name: family, size: 12) else { return false }
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.fixedPitchFontMask)
    }
}
```

**Step 4: Build and smoke-test**

```bash
swift build -c release 2>&1 | tail -5
.build/release/framer --help
.build/release/framer fonts | head -10
```
Expected: Help text shown, font list appears.

**Step 5: Test against a real image**

```bash
.build/release/framer process -i docs/sample.jpg -o /tmp/framer-test/
ls /tmp/framer-test/
```
Expected: `sample_solid.jpg` created in `/tmp/framer-test/`.

**Step 6: Remove the Go source files**

```bash
git rm framer.go fonts.go fonts_data/*.ttf fonts_data/*.otf 2>/dev/null || true
git rm -r fonts_data/ 2>/dev/null || true
```

**Step 7: Commit**

```bash
git add Sources/FramerCLI/
git commit -m "feat: add FramerCLI replacing Go CLI (process, presets, fonts commands)"
```

---

## Phase 3: FramerApp — macOS SwiftUI App

### Task 9: App Shell + Xcode Project Setup

**Files:**
- Create: `FramerApp.xcodeproj` via Xcode (manual step)
- Create: `Sources/FramerApp/App/FramerApp.swift`
- Create: `Sources/FramerApp/App/AppState.swift`

**Step 1: Create Xcode project**

In Xcode:
1. File → New → Project → macOS → App
2. Product Name: `Framer`, Bundle ID: `com.arthursoares.Framer`
3. Interface: SwiftUI, Language: Swift
4. Save into the existing `framer/` repo directory
5. In project settings → Package Dependencies → add local package (the repo root)
6. Add `FramerCore` as a linked framework to the app target

**Step 2: App entry point**

```swift
// Sources/FramerApp/App/FramerApp.swift
import SwiftUI

@main
struct FramerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            FramerCommands()
        }

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
```

**Step 3: AppState (shared observable state)**

```swift
// Sources/FramerApp/App/AppState.swift
import SwiftUI
import FramerCore

@Observable
final class AppState {
    var library: [PhotoItem] = []
    var selectedItems: Set<PhotoItem.ID> = []
    var currentConfig: ProcessingConfig = .default
    var presets: [Preset] = []
    var presetStore = PresetStore()
    var exportQueue: [ExportJob] = []
    var isExporting = false

    init() {
        loadPresets()
    }

    func loadPresets() {
        presets = (try? presetStore.list()) ?? []
    }
}

struct PhotoItem: Identifiable, Hashable {
    let id: UUID = .init()
    let url: URL
    var thumbnail: NSImage?
}

struct ExportJob: Identifiable {
    let id: UUID = .init()
    let items: [PhotoItem]
    let config: ProcessingConfig
    let outputDirectory: URL
    var progress: Double = 0
    var status: JobStatus = .queued

    enum JobStatus { case queued, running, done, failed(Error) }
}
```

**Step 4: Run in Xcode**

Open `FramerApp.xcodeproj`, select the `Framer` scheme, press ⌘R.
Expected: App launches, blank window.

**Step 5: Commit**

```bash
git add Sources/FramerApp/App/
git commit -m "feat: add FramerApp shell and AppState"
```

---

### Task 10: Library Sidebar

**Files:**
- Create: `Sources/FramerApp/Library/LibrarySidebar.swift`
- Create: `Sources/FramerApp/Library/PhotoThumbnailView.swift`
- Create: `Sources/FramerApp/ContentView.swift`

**Step 1: ContentView with NavigationSplitView**

```swift
// Sources/FramerApp/ContentView.swift
import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
        } content: {
            LivePreviewPanel()
        } detail: {
            SettingsPanel()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 700)
    }
}
```

**Step 2: Library sidebar with drag-and-drop**

```swift
// Sources/FramerApp/Library/LibrarySidebar.swift
import SwiftUI
import FramerCore

struct LibrarySidebar: View {
    @Environment(AppState.self) var appState
    @State private var isTargeted = false

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedItems },
            set: { appState.selectedItems = $0 }
        )) {
            if appState.library.isEmpty {
                emptyState
            } else {
                ForEach(appState.library) { item in
                    PhotoThumbnailView(item: item)
                        .tag(item.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Button(action: openFilePicker) {
                    Label("Add Photos", systemImage: "plus")
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
                .padding(4)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drop photos here")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) { addURLs(urls) }
        return true
    }

    private func addURLs(_ urls: [URL]) {
        let imageExts = ["jpg","jpeg","png","tiff","tif","heic"]
        var allFiles: [URL] = []
        for url in urls {
            if url.hasDirectoryPath {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)
                ) ?? []
                allFiles += files.filter { imageExts.contains($0.pathExtension.lowercased()) }
            } else if imageExts.contains(url.pathExtension.lowercased()) {
                allFiles.append(url)
            }
        }
        let newItems = allFiles.map { PhotoItem(url: $0) }
        appState.library.append(contentsOf: newItems)
    }
}
```

**Step 3: Photo thumbnail view**

```swift
// Sources/FramerApp/Library/PhotoThumbnailView.swift
import SwiftUI

struct PhotoThumbnailView: View {
    let item: PhotoItem

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(item.url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
```

**Step 4: Build and test in Xcode**

Run with ⌘R. Drag some JPEG files into the sidebar.
Expected: Files appear as list items, drag highlight works.

**Step 5: Commit**

```bash
git add Sources/FramerApp/Library/ Sources/FramerApp/ContentView.swift
git commit -m "feat: add library sidebar with drag-and-drop and folder support"
```

---

### Task 11: Live Preview Panel

**Files:**
- Create: `Sources/FramerApp/Editor/LivePreviewPanel.swift`
- Create: `Sources/FramerApp/Editor/PreviewViewModel.swift`

**Step 1: PreviewViewModel with debounced rendering**

```swift
// Sources/FramerApp/Editor/PreviewViewModel.swift
import SwiftUI
import Combine
import FramerCore

@Observable
final class PreviewViewModel {
    var previewImage: NSImage?
    var isLoading = false
    var error: String?
    var exifData: ExifData?

    private var renderTask: Task<Void, Never>?
    private let processor = FrameProcessor()

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig) {
        guard let item else {
            previewImage = nil
            exifData = nil
            return
        }
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            // Debounce: wait 150ms before rendering
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            isLoading = true
            error = nil

            do {
                let exif = try? await Task.detached { try EXIFReader.read(from: item.url) }.value
                exifData = exif

                let image = try await processor.previewImage(for: item.url, config: config)
                previewImage = image
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
```

**Step 2: Live preview panel**

```swift
// Sources/FramerApp/Editor/LivePreviewPanel.swift
import SwiftUI
import FramerCore

struct LivePreviewPanel: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()

    var selectedItem: PhotoItem? {
        appState.selectedItems.first.flatMap { id in
            appState.library.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview image
            ZStack {
                Color(nsColor: .controlBackgroundColor)

                if viewModel.isLoading {
                    ProgressView()
                } else if let img = viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(20)
                } else if selectedItem == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("Select a photo to preview")
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = viewModel.error {
                    Text(err)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // EXIF + caption info bar
            if let exif = viewModel.exifData {
                ExifInfoBar(exif: exif, config: appState.currentConfig)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
        }
        .onChange(of: appState.selectedItems) { updatePreview() }
        .onChange(of: appState.currentConfig) { updatePreview() }
        .onAppear { updatePreview() }
    }

    private func updatePreview() {
        viewModel.updatePreview(for: selectedItem, config: appState.currentConfig)
    }
}

struct ExifInfoBar: View {
    let exif: ExifData
    let config: ProcessingConfig
    @State private var showingInspector = false

    var captionText: String {
        switch config.captionMode {
        case .template(let t): return exif.resolve(template: t)
        case .custom(let s): return s
        case .none: return "(no caption)"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let camera = exif.camera {
                    Text(camera)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    exifChip(exif.iso.map { "ISO \($0)" })
                    exifChip(exif.aperture.map { "f/\($0)" })
                    exifChip(exif.shutterSpeed)
                    exifChip(exif.focalLength.map { "\($0)mm" })
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Caption:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(captionText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Button(action: { showingInspector.toggle() }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInspector) {
                EXIFInspectorPopover(exif: exif)
            }
        }
    }

    @ViewBuilder
    private func exifChip(_ value: String?) -> some View {
        if let v = value {
            Text(v)
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }
}

struct EXIFInspectorPopover: View {
    let exif: ExifData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXIF Data").font(.headline).padding(.bottom, 4)
            row("Camera", exif.camera)
            row("Lens", exif.lens)
            row("ISO", exif.iso)
            row("Aperture", exif.aperture.map { "f/\($0)" })
            row("Shutter", exif.shutterSpeed)
            row("Focal Length", exif.focalLength.map { "\($0)mm" })
            if let date = exif.dateTime {
                row("Date", DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
            }
        }
        .padding(16)
        .frame(minWidth: 200)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
            Text(value ?? "—")
        }
        .font(.caption)
    }
}
```

**Step 3: Build and test in Xcode**

Select a photo in the sidebar → live preview should appear within ~200ms.
Expected: Preview image shown with EXIF bar at bottom, caption text visible.

**Step 4: Commit**

```bash
git add Sources/FramerApp/Editor/
git commit -m "feat: add live preview panel with debounced rendering and EXIF inspector"
```

---

### Task 12: Settings Panel

**Files:**
- Create: `Sources/FramerApp/Editor/SettingsPanel.swift`

```swift
// Sources/FramerApp/Editor/SettingsPanel.swift
import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState

    var config: Binding<ProcessingConfig> {
        Binding(get: { appState.currentConfig }, set: { appState.currentConfig = $0 })
    }

    var body: some View {
        Form {
            // Border
            Section("Border") {
                Picker("Style", selection: config.borderStyle) {
                    Text("Solid").tag(BorderStyle.solid)
                    Text("Instagram (4:5)").tag(BorderStyle.instagram)
                }
                .pickerStyle(.segmented)

                BorderThicknessRow(thickness: config.borderThickness)
                ColorPickerRow("Border Color", color: config.borderColor)

                if appState.currentConfig.borderStyle == .solid {
                    LabeledContent("Padding") {
                        Slider(value: Binding(
                            get: { Double(appState.currentConfig.padding) },
                            set: { appState.currentConfig.padding = Int($0) }
                        ), in: 0...400, step: 10)
                        Text("\(appState.currentConfig.padding)px")
                            .monospacedDigit()
                            .frame(width: 50)
                    }
                }
            }

            // Caption
            Section("Caption") {
                CaptionModeRow(captionMode: config.captionMode)
            }

            // Font
            Section("Font") {
                FontPickerRow(fontName: config.fontName, fontSize: config.fontSize)
                ColorPickerRow("Font Color", color: config.fontColor)
            }

            // Output
            Section("Output") {
                Picker("Format", selection: Binding(
                    get: { appState.currentConfig.outputFormat == .png ? "png" : "jpeg" },
                    set: { appState.currentConfig.outputFormat = $0 == "png" ? .png : .jpeg(quality: 100) }
                )) {
                    Text("JPEG").tag("jpeg")
                    Text("PNG").tag("png")
                }
                if case .jpeg(let q) = appState.currentConfig.outputFormat {
                    LabeledContent("Quality") {
                        Slider(value: Binding(
                            get: { Double(q) },
                            set: { appState.currentConfig.outputFormat = .jpeg(quality: Int($0)) }
                        ), in: 60...100, step: 5)
                        Text("\(q)%").monospacedDigit().frame(width: 40)
                    }
                }
            }

            // Actions
            Divider()
            HStack {
                Button("Export Selected") { exportSelected() }
                    .disabled(appState.selectedItems.isEmpty)
                Button("Export All") { exportAll() }
                    .disabled(appState.library.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 260)
    }

    private func exportSelected() {
        let items = appState.library.filter { appState.selectedItems.contains($0.id) }
        queueExport(items: items)
    }

    private func exportAll() {
        queueExport(items: appState.library)
    }

    private func queueExport(items: [PhotoItem]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let job = ExportJob(items: items, config: appState.currentConfig, outputDirectory: dir)
        appState.exportQueue.append(job)
        // Trigger processing
        Task { await runExportJob(job) }
    }

    private func runExportJob(_ job: ExportJob) async {
        let processor = FrameProcessor()
        let total = job.items.count
        for (i, item) in job.items.enumerated() {
            let outURL = job.outputDirectory
                .appendingPathComponent(item.url.deletingPathExtension().lastPathComponent + "_framed")
                .appendingPathExtension(job.config.outputFormat == .png ? "png" : "jpg")
            try? await processor.process(input: item.url, output: outURL, config: job.config)
            let progress = Double(i + 1) / Double(total)
            await MainActor.run {
                if let idx = appState.exportQueue.firstIndex(where: { $0.id == job.id }) {
                    appState.exportQueue[idx].progress = progress
                }
            }
        }
    }
}

// MARK: - Sub-components

struct ColorPickerRow: View {
    let label: String
    @Binding var color: CodableColor

    init(_ label: String, color: Binding<CodableColor>) {
        self.label = label
        self._color = color
    }

    var body: some View {
        ColorPicker(label, selection: Binding(
            get: { Color(nsColor: NSColor(cgColor: color.cgColor) ?? .white) },
            set: { newColor in
                if let cgColor = NSColor(newColor).cgColor.converted(
                    to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
                   let comps = cgColor.components, comps.count >= 3 {
                    let r = Int(comps[0] * 255)
                    let g = Int(comps[1] * 255)
                    let b = Int(comps[2] * 255)
                    let hex = String(format: "#%02X%02X%02X", r, g, b)
                    color = (try? CodableColor(hex: hex)) ?? color
                }
            }
        ))
    }
}

struct CaptionModeRow: View {
    @Binding var captionMode: CaptionMode
    @State private var templateText = ""
    @State private var customText = ""
    @State private var modeIndex = 0

    var body: some View {
        Picker("Mode", selection: $modeIndex) {
            Text("Template").tag(0)
            Text("Custom").tag(1)
            Text("None").tag(2)
        }
        .pickerStyle(.segmented)
        .onChange(of: modeIndex) { updateMode() }
        .onAppear { syncFromBinding() }

        if modeIndex == 0 {
            TextField("Template", text: $templateText)
                .font(.system(.body, design: .monospaced))
                .onChange(of: templateText) { captionMode = .template(templateText) }
        } else if modeIndex == 1 {
            TextField("Caption text", text: $customText)
                .onChange(of: customText) { captionMode = .custom(customText) }
        }
    }

    private func syncFromBinding() {
        switch captionMode {
        case .template(let t): modeIndex = 0; templateText = t
        case .custom(let s): modeIndex = 1; customText = s
        case .none: modeIndex = 2
        }
    }

    private func updateMode() {
        switch modeIndex {
        case 0: captionMode = .template(templateText.isEmpty ? " - {{mon}} '{{year2}} -" : templateText)
        case 1: captionMode = .custom(customText)
        default: captionMode = .none
        }
    }
}

struct BorderThicknessRow: View {
    @Binding var thickness: BorderSize

    var body: some View {
        LabeledContent("Thickness") {
            Slider(value: Binding(
                get: {
                    switch thickness {
                    case .pixels(let px): return Double(px)
                    case .percent(let p): return p * 10
                    }
                },
                set: { thickness = .pixels(Int($0)) }
            ), in: 0...300, step: 5)
            Text(thicknessLabel).monospacedDigit().frame(width: 55)
        }
    }

    var thicknessLabel: String {
        switch thickness {
        case .pixels(let px): return "\(px)px"
        case .percent(let p): return "\(String(format: "%.1f", p))%"
        }
    }
}

struct FontPickerRow: View {
    @Binding var fontName: String
    @Binding var fontSize: FontSize

    var body: some View {
        HStack {
            Picker("Font", selection: $fontName) {
                ForEach(availableMonospacedFonts(), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            Spacer()
            switch fontSize {
            case .auto:
                Text("Auto").foregroundStyle(.secondary)
            case .fixed(let s):
                Stepper("\(s)pt", value: Binding(
                    get: { s },
                    set: { fontSize = .fixed($0) }
                ), in: 8...200)
            }
        }
    }

    private func availableMonospacedFonts() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
            .sorted()
    }
}
```

**Step 2: Build and test in Xcode**

Run app, verify all controls appear and adjusting them triggers a preview update.

**Step 3: Commit**

```bash
git add Sources/FramerApp/Editor/SettingsPanel.swift
git commit -m "feat: add settings panel with live controls (border, caption, font, output)"
```

---

### Task 13: Preset Manager UI

**Files:**
- Create: `Sources/FramerApp/Presets/PresetManagerView.swift`
- Create: `Sources/FramerApp/Presets/PresetThumbnailView.swift`

**Step 1: Implement PresetManagerView**

```swift
// Sources/FramerApp/Presets/PresetManagerView.swift
import SwiftUI
import FramerCore

struct PresetManagerView: View {
    @Environment(AppState.self) var appState
    @State private var selectedPreset: Preset.ID?
    @State private var isCreating = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Presets")
                .font(.headline)
                .padding([.horizontal, .top])

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(appState.presets) { preset in
                        PresetThumbnailView(
                            preset: preset,
                            isSelected: selectedPreset == preset.id
                        )
                        .onTapGesture {
                            selectedPreset = preset.id
                            appState.currentConfig = preset.config
                        }
                        .contextMenu {
                            Button("Apply") { appState.currentConfig = preset.config }
                            Divider()
                            Button("Delete", role: .destructive) { deletePreset(preset) }
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button(action: { isCreating = true }) {
                    Label("Save Current as Preset", systemImage: "plus")
                }
                .padding()
                Spacer()
            }
        }
        .sheet(isPresented: $isCreating) {
            SavePresetSheet(isPresented: $isCreating)
        }
    }

    private func deletePreset(_ preset: Preset) {
        try? appState.presetStore.delete(id: preset.id)
        appState.loadPresets()
    }
}

struct SavePresetSheet: View {
    @Environment(AppState.self) var appState
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Preset").font(.headline)
            TextField("Preset name", text: $name)
                .frame(width: 200)
            HStack {
                Button("Cancel") { isPresented = false }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
            }
        }
        .padding(24)
    }

    private func save() {
        let preset = Preset(name: name, config: appState.currentConfig)
        try? appState.presetStore.save(preset)
        appState.loadPresets()
        isPresented = false
    }
}
```

**Step 2: Preset thumbnail view**

```swift
// Sources/FramerApp/Presets/PresetThumbnailView.swift
import SwiftUI
import FramerCore

struct PresetThumbnailView: View {
    let preset: Preset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let thumbData = preset.thumbnailData,
                   let nsImage = NSImage(data: thumbData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 85)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text(preset.name)
                .font(.caption)
                .lineLimit(1)
        }
    }
}
```

**Step 3: Wire into app via keyboard shortcut ⌘2**

Add to `ContentView.swift`:
```swift
// In the ContentView toolbar or tab navigation, add:
.keyboardShortcut("2", modifiers: .command) // navigate to presets panel
```

The full navigation integration uses a `@State private var selectedTab` pattern in ContentView, which splits between `.library`, `.presets`, and `.queue` views.

**Step 4: Commit**

```bash
git add Sources/FramerApp/Presets/
git commit -m "feat: add preset manager with thumbnail grid, save/apply/delete"
```

---

### Task 14: Export Queue View

**Files:**
- Create: `Sources/FramerApp/Queue/ExportQueueView.swift`

```swift
// Sources/FramerApp/Queue/ExportQueueView.swift
import SwiftUI

struct ExportQueueView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Queue")
                .font(.headline)
                .padding([.horizontal, .top])

            if appState.exportQueue.isEmpty {
                Spacer()
                Text("No exports in queue")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(appState.exportQueue) { job in
                    ExportJobRow(job: job)
                }
            }
        }
    }
}

struct ExportJobRow: View {
    let job: ExportJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(job.items.count) photo\(job.items.count == 1 ? "" : "s")")
                    .fontWeight(.medium)
                Spacer()
                statusBadge
            }
            Text(job.outputDirectory.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if case .running = job.status {
                ProgressView(value: job.progress)
            } else if case .done = job.status {
                ProgressView(value: 1.0)
                    .tint(.green)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var statusBadge: some View {
        switch job.status {
        case .queued:
            Text("Queued").foregroundStyle(.secondary).font(.caption)
        case .running:
            Text("\(Int(job.progress * 100))%").font(.caption.monospacedDigit())
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption)
        }
    }
}
```

**Commit:**

```bash
git add Sources/FramerApp/Queue/
git commit -m "feat: add export queue view with job progress tracking"
```

---

### Task 15: Preferences Window + CLI Install

**Files:**
- Create: `Sources/FramerApp/App/PreferencesView.swift`

```swift
// Sources/FramerApp/App/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @AppStorage("defaultOutputFormat") var defaultOutputFormat = "jpeg"
    @AppStorage("jpegQuality") var jpegQuality = 100
    @AppStorage("iCloudSyncEnabled") var iCloudSyncEnabled = true
    @State private var cliInstallStatus = CLIInstallStatus.unknown

    var body: some View {
        Form {
            Section("Output Defaults") {
                Picker("Format", selection: $defaultOutputFormat) {
                    Text("JPEG").tag("jpeg")
                    Text("PNG").tag("png")
                }
                if defaultOutputFormat == "jpeg" {
                    Slider(value: Binding(
                        get: { Double(jpegQuality) },
                        set: { jpegQuality = Int($0) }
                    ), in: 60...100, step: 5) {
                        Text("Quality: \(jpegQuality)%")
                    }
                }
            }

            Section("Sync") {
                Toggle("Sync presets via iCloud Drive", isOn: $iCloudSyncEnabled)
            }

            Section("Command Line Tools") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Install `framer` CLI")
                        Text("Symlinks the CLI tool to /usr/local/bin/framer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch cliInstallStatus {
                    case .installed:
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .notInstalled:
                        Button("Install") { installCLI() }
                            .buttonStyle(.bordered)
                    case .unknown:
                        Button("Check") { checkCLIStatus() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear { checkCLIStatus() }
    }

    private func checkCLIStatus() {
        let fm = FileManager.default
        cliInstallStatus = fm.fileExists(atPath: "/usr/local/bin/framer") ? .installed : .notInstalled
    }

    private func installCLI() {
        guard let bundleCLI = Bundle.main.url(forAuxiliaryExecutable: "framer") else { return }
        let dest = URL(fileURLWithPath: "/usr/local/bin/framer")
        // Use AuthorizationServices for privileged install in production
        // For direct download build, use SMJobBless or a helper tool
        let script = """
        do shell script "ln -sf '\(bundleCLI.path)' '\(dest.path)'" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        checkCLIStatus()
    }

    enum CLIInstallStatus { case unknown, installed, notInstalled }
}
```

**Commit:**

```bash
git add Sources/FramerApp/App/PreferencesView.swift
git commit -m "feat: add preferences window with output defaults, iCloud toggle, CLI install"
```

---

### Task 16: App Menu Commands + Keyboard Shortcuts

**Files:**
- Create: `Sources/FramerApp/App/FramerCommands.swift`

```swift
// Sources/FramerApp/App/FramerCommands.swift
import SwiftUI

struct FramerCommands: Commands {
    @Environment(AppState.self) var appState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Photos...") {
                NotificationCenter.default.post(name: .openPhotos, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Export") {
            Button("Export Selected") {
                NotificationCenter.default.post(name: .exportSelected, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(appState.selectedItems.isEmpty)

            Button("Export All") {
                NotificationCenter.default.post(name: .exportAll, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.library.isEmpty)
        }
    }
}

extension Notification.Name {
    static let openPhotos = Notification.Name("framer.openPhotos")
    static let exportSelected = Notification.Name("framer.exportSelected")
    static let exportAll = Notification.Name("framer.exportAll")
}
```

**Commit:**

```bash
git add Sources/FramerApp/App/FramerCommands.swift
git commit -m "feat: add app menu commands and keyboard shortcuts"
```

---

### Task 17: Distribution Build Configurations

**Files:**
- Modify: `FramerApp.xcodeproj` (via Xcode — no direct file edit)
- Create: `FramerApp/Framer-AppStore.entitlements`
- Create: `FramerApp/Framer-DirectDownload.entitlements`

**Step 1: App Store entitlements**

```xml
<!-- Framer-AppStore.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.files.downloads.read-write</key><true/>
    <key>com.apple.ubiquity.kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)com.arthursoares.Framer</string>
</dict></plist>
```

**Step 2: Direct download entitlements (hardened runtime)**

```xml
<!-- Framer-DirectDownload.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.app-sandbox</key><false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><false/>
    <key>com.apple.ubiquity.kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)com.arthursoares.Framer</string>
</dict></plist>
```

**Step 3: Add build flag for App Store**

In Xcode → Build Settings → `Other Swift Flags`:
- App Store scheme: `-DAPP_STORE`
- Direct download scheme: *(empty)*

In code, gate post-process shell execution:
```swift
#if !APP_STORE
    try runPostProcess(config.postProcess, file: outURL)
#endif
```

**Step 4: Commit**

```bash
git add FramerApp/Framer-AppStore.entitlements FramerApp/Framer-DirectDownload.entitlements
git commit -m "chore: add App Store and direct download entitlements"
```

---

## Summary

| Phase | Tasks | Key deliverable |
|---|---|---|
| Foundation | 1-2 | SPM package, models |
| FramerCore | 3-7 | EXIF, rendering, presets, YAML |
| FramerCLI | 8 | Swift CLI replacing Go binary |
| FramerApp | 9-16 | Full macOS SwiftUI app |
| Distribution | 17 | App Store + direct download builds |

**Run all tests at any point:**
```bash
swift test
```

**Build CLI release:**
```bash
swift build -c release
.build/release/framer --help
```

**Open app in Xcode:**
```bash
open FramerApp.xcodeproj
```
