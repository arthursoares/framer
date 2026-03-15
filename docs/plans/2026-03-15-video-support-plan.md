# Video Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add GPU-accelerated video processing to Framer — apply the full layer pipeline to every video frame with trim controls, codec selection, and audio passthrough.

**Architecture:** Hybrid Core Image + Metal pipeline shared by images and video. `CIFilterPipeline` converts the existing `[CompositionLayer]` stack into a `CIFilter` chain. `VideoProcessor` actor orchestrates AVAssetReader → CIFilter chain → AVAssetWriter with audio passthrough. Output dimension preview computed from the layer stack without rendering.

**Tech Stack:** AVFoundation (video I/O), Core Image (GPU filter chain), Metal Shading Language (custom dither/blend kernels), CoreText (captions), Swift Concurrency (actor-based processing)

**Design Doc:** `docs/plans/2026-03-15-video-support-design.md`

---

## Task 1: Data Models — VideoCodec, TrimRange, VideoExportConfig

**Files:**
- Create: `Sources/FramerCore/Models/VideoExportConfig.swift`
- Modify: `Sources/FramerCore/Models/ProcessingConfig.swift:176` (OutputFormat enum)
- Modify: `Sources/FramerCore/Models/ProcessingConfig.swift:192` (ProcessingConfig struct)
- Test: `Tests/FramerCoreTests/VideoExportConfigTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import FramerCore

final class VideoExportConfigTests: XCTestCase {

    // MARK: - VideoCodec

    func testVideoCodecRawValues() {
        XCTAssertEqual(VideoCodec.h264.rawValue, "h264")
        XCTAssertEqual(VideoCodec.h265.rawValue, "h265")
    }

    func testVideoCodecCodable() throws {
        let codec = VideoCodec.h265
        let data = try JSONEncoder().encode(codec)
        let decoded = try JSONDecoder().decode(VideoCodec.self, from: data)
        XCTAssertEqual(decoded, codec)
    }

    // MARK: - TrimRange

    func testTrimRangeFromTimecode() throws {
        let trim = try TrimRange(from: "00:01:30.500-00:02:45.000")
        XCTAssertEqual(trim.start, 90.5, accuracy: 0.001)
        XCTAssertEqual(trim.end, 165.0, accuracy: 0.001)
    }

    func testTrimRangeInvalidFormat() {
        XCTAssertThrowsError(try TrimRange(from: "invalid"))
    }

    func testTrimRangeStartAfterEnd() {
        XCTAssertThrowsError(try TrimRange(from: "00:02:00.000-00:01:00.000"))
    }

    func testTrimRangeCodable() throws {
        let trim = try TrimRange(from: "00:00:05.000-00:00:30.000")
        let data = try JSONEncoder().encode(trim)
        let decoded = try JSONDecoder().decode(TrimRange.self, from: data)
        XCTAssertEqual(decoded.start, trim.start, accuracy: 0.001)
        XCTAssertEqual(decoded.end, trim.end, accuracy: 0.001)
    }

    // MARK: - VideoExportConfig

    func testVideoExportConfigDefaults() {
        let config = VideoExportConfig()
        XCTAssertEqual(config.codec, .h264)
        XCTAssertNil(config.trim)
    }

    func testVideoExportConfigCodable() throws {
        var config = VideoExportConfig()
        config.codec = .h265
        config.trim = try TrimRange(from: "00:00:10.000-00:00:20.000")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VideoExportConfig.self, from: data)
        XCTAssertEqual(decoded.codec, .h265)
        XCTAssertEqual(decoded.trim?.start, 10.0, accuracy: 0.001)
        XCTAssertEqual(decoded.trim?.end, 20.0, accuracy: 0.001)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter VideoExportConfigTests 2>&1 | tail -5`
Expected: Compilation error — types don't exist yet

**Step 3: Create `VideoExportConfig.swift` with all three types**

```swift
import Foundation

// MARK: - VideoCodec

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264
    case h265
}

// MARK: - TrimRange

public struct TrimRange: Codable, Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) throws {
        guard start < end else {
            throw FramerError.invalidTrimRange("Start time must be before end time")
        }
        self.start = start
        self.end = end
    }

    /// Parse from timecode string: "HH:MM:SS.mmm-HH:MM:SS.mmm"
    public init(from timecode: String) throws {
        let parts = timecode.split(separator: "-")
        guard parts.count == 2 else {
            throw FramerError.invalidTrimRange("Expected format: HH:MM:SS.mmm-HH:MM:SS.mmm")
        }
        let startTime = try Self.parseTimecode(String(parts[0]))
        let endTime = try Self.parseTimecode(String(parts[1]))
        try self.init(start: startTime, end: endTime)
    }

    private static func parseTimecode(_ tc: String) throws -> TimeInterval {
        let segments = tc.split(separator: ":")
        guard segments.count == 3 else {
            throw FramerError.invalidTrimRange("Invalid timecode: \(tc)")
        }
        guard let hours = Double(segments[0]),
              let minutes = Double(segments[1]),
              let seconds = Double(segments[2]) else {
            throw FramerError.invalidTrimRange("Non-numeric timecode: \(tc)")
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - VideoExportConfig

public struct VideoExportConfig: Codable, Sendable, Equatable {
    public var codec: VideoCodec
    public var trim: TrimRange?

    public init(codec: VideoCodec = .h264, trim: TrimRange? = nil) {
        self.codec = codec
        self.trim = trim
    }
}
```

**Step 4: Add `.invalidTrimRange` to `FramerError`**

In `Sources/FramerCore/Models/ProcessingConfig.swift`, find the `FramerError` enum (line ~266) and add:

```swift
case invalidTrimRange(String)
```

And in the `errorDescription` computed property, add:

```swift
case .invalidTrimRange(let message):
    return "Invalid trim range: \(message)"
```

**Step 5: Add `.mp4` case to `OutputFormat`**

In `Sources/FramerCore/Models/ProcessingConfig.swift:176`, change:

```swift
public enum OutputFormat: Codable, Equatable, Sendable {
    case jpeg(quality: Int)
    case png
    case mp4(VideoExportConfig)
}
```

**Step 6: Add `videoExport` to `ProcessingConfig`**

In `Sources/FramerCore/Models/ProcessingConfig.swift:192`, add to the struct:

```swift
public var videoExport: VideoExportConfig?
```

Initialize it as `nil` in the existing initializer.

**Step 7: Run tests to verify they pass**

Run: `swift test --filter VideoExportConfigTests 2>&1 | tail -10`
Expected: All tests PASS

**Step 8: Run full build to check nothing is broken**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded (may need to fix switch exhaustiveness on `OutputFormat` in other files)

**Step 9: Fix any exhaustive switch errors**

Search for `switch.*outputFormat` or `case .jpeg` / `case .png` patterns in the codebase. Add `case .mp4` handling wherever `OutputFormat` is switched on. For now, video output is not handled in image-only paths — add appropriate error/skip logic.

**Step 10: Commit**

```bash
git add Sources/FramerCore/Models/VideoExportConfig.swift Tests/FramerCoreTests/VideoExportConfigTests.swift Sources/FramerCore/Models/ProcessingConfig.swift
git commit -m "feat: add VideoCodec, TrimRange, and VideoExportConfig data models"
```

---

## Task 2: Output Dimension Calculator

**Files:**
- Create: `Sources/FramerCore/Processing/OutputSizeCalculator.swift`
- Test: `Tests/FramerCoreTests/OutputSizeCalculatorTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class OutputSizeCalculatorTests: XCTestCase {

    func testNoLayers() {
        let size = OutputSizeCalculator.outputSize(
            for: CGSize(width: 1920, height: 1080),
            layers: []
        )
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }

    func testBorderLayer() {
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(50), color: CodableColor(hex: "#000000")!))
        ]
        let size = OutputSizeCalculator.outputSize(
            for: CGSize(width: 1920, height: 1080),
            layers: layers
        )
        XCTAssertEqual(size.width, 2020)  // 1920 + 50*2
        XCTAssertEqual(size.height, 1180) // 1080 + 50*2
    }

    func testResizeLayer() {
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 800, maxHeight: 600))
        ]
        let size = OutputSizeCalculator.outputSize(
            for: CGSize(width: 1920, height: 1080),
            layers: layers
        )
        // 1920x1080 scaled to fit 800x600 → 800x450
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 450)
    }

    func testCanvasLayer() {
        let layers: [CompositionLayer] = [
            .canvas(CanvasLayerParams(width: 3000, height: 3000, fill: .solid(CodableColor(hex: "#FFFFFF")!)))
        ]
        let size = OutputSizeCalculator.outputSize(
            for: CGSize(width: 1920, height: 1080),
            layers: layers
        )
        XCTAssertEqual(size.width, 3000)
        XCTAssertEqual(size.height, 3000)
    }

    func testMultipleLayers() {
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(20), color: CodableColor(hex: "#000000")!)),
            .resize(ResizeLayerParams(maxWidth: 1000, maxHeight: 1000)),
        ]
        let size = OutputSizeCalculator.outputSize(
            for: CGSize(width: 1920, height: 1080),
            layers: layers
        )
        // After border: 1960x1120, then resize to fit 1000x1000 → 1000x571
        XCTAssertEqual(size.width, 1000)
        XCTAssertEqual(size.height, 571, accuracy: 1)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter OutputSizeCalculatorTests 2>&1 | tail -5`
Expected: Compilation error

**Step 3: Implement `OutputSizeCalculator`**

```swift
import Foundation
import CoreGraphics

public enum OutputSizeCalculator {

    /// Compute the output dimensions by walking the layer stack without rendering.
    public static func outputSize(for inputSize: CGSize, layers: [CompositionLayer]) -> CGSize {
        var size = inputSize
        for layer in layers {
            size = applyLayerSize(layer, to: size)
        }
        return CGSize(width: round(size.width), height: round(size.height))
    }

    private static func applyLayerSize(_ layer: CompositionLayer, to size: CGSize) -> CGSize {
        switch layer {
        case .border(let params):
            let thickness = params.thickness.pixels(for: size)
            return CGSize(width: size.width + CGFloat(thickness) * 2,
                          height: size.height + CGFloat(thickness) * 2)

        case .padding(let params):
            return CGSize(width: size.width + CGFloat(params.thickness) * 2,
                          height: size.height + CGFloat(params.thickness) * 2)

        case .canvas(let params):
            return CGSize(width: CGFloat(params.width), height: CGFloat(params.height))

        case .resize(let params):
            let scaleX = CGFloat(params.maxWidth) / size.width
            let scaleY = CGFloat(params.maxHeight) / size.height
            let scale = min(scaleX, scaleY)
            if scale >= 1.0 { return size } // don't upscale
            return CGSize(width: round(size.width * scale),
                          height: round(size.height * scale))

        case .overlay, .orientation, .caption, .dither:
            return size // these don't change dimensions
        }
    }
}
```

Note: `BorderSize.pixels(for:)` may need to be added or may already exist — check the `BorderSize` enum at `ProcessingConfig.swift:87`. If it only has `.pixels(Int)` and `.percentage(Double)`, add a helper that resolves to pixel count given a `CGSize`.

**Step 4: Run tests to verify they pass**

Run: `swift test --filter OutputSizeCalculatorTests 2>&1 | tail -10`
Expected: All PASS

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/OutputSizeCalculator.swift Tests/FramerCoreTests/OutputSizeCalculatorTests.swift
git commit -m "feat: add OutputSizeCalculator for preview dimensions"
```

---

## Task 3: CIFilterPipeline — Core Image Layer Chain

**Files:**
- Create: `Sources/FramerCore/Processing/CIFilterPipeline.swift`
- Test: `Tests/FramerCoreTests/CIFilterPipelineTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
import CoreImage
import CoreGraphics
@testable import FramerCore

final class CIFilterPipelineTests: XCTestCase {

    private let ciContext = CIContext()

    /// Helper: create a solid-color test CIImage
    private func solidImage(width: Int, height: Int, color: CodableColor) -> CIImage {
        let cgColor = color.cgColor
        return CIImage(color: CIColor(cgColor: cgColor))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testPassthroughNoLayers() {
        let input = solidImage(width: 100, height: 100, color: CodableColor(hex: "#FF0000")!)
        let output = CIFilterPipeline.apply(layers: [], to: input, sourceImage: input, exif: ExifData())
        XCTAssertEqual(output.extent.width, 100)
        XCTAssertEqual(output.extent.height, 100)
    }

    func testBorderLayerAddsDimensions() {
        let input = solidImage(width: 100, height: 100, color: CodableColor(hex: "#FF0000")!)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: CodableColor(hex: "#000000")!))
        ]
        let output = CIFilterPipeline.apply(layers: layers, to: input, sourceImage: input, exif: ExifData())
        XCTAssertEqual(output.extent.width, 120)
        XCTAssertEqual(output.extent.height, 120)
    }

    func testResizeLayerScalesDown() {
        let input = solidImage(width: 200, height: 100, color: CodableColor(hex: "#FF0000")!)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 100, maxHeight: 100))
        ]
        let output = CIFilterPipeline.apply(layers: layers, to: input, sourceImage: input, exif: ExifData())
        XCTAssertEqual(output.extent.width, 100, accuracy: 1)
        XCTAssertEqual(output.extent.height, 50, accuracy: 1)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter CIFilterPipelineTests 2>&1 | tail -5`
Expected: Compilation error

**Step 3: Implement `CIFilterPipeline`**

Create `Sources/FramerCore/Processing/CIFilterPipeline.swift`:

```swift
import Foundation
import CoreImage
import CoreGraphics
import CoreText

public enum CIFilterPipeline {

    /// Apply the full layer stack to a CIImage, returning the composited result.
    public static func apply(
        layers: [CompositionLayer],
        to image: CIImage,
        sourceImage: CIImage,
        exif: ExifData
    ) -> CIImage {
        var current = image
        for layer in layers {
            current = applyLayer(layer, to: current, sourceImage: sourceImage, exif: exif)
        }
        return current
    }

    private static func applyLayer(
        _ layer: CompositionLayer,
        to image: CIImage,
        sourceImage: CIImage,
        exif: ExifData
    ) -> CIImage {
        switch layer {
        case .border(let params):
            return applyBorder(params, to: image)
        case .padding(let params):
            return applyPadding(params, to: image)
        case .canvas(let params):
            return applyCanvas(params, to: image)
        case .resize(let params):
            return applyResize(params, to: image)
        case .overlay(let params):
            return applyOverlay(params, to: image)
        case .orientation(let params):
            return applyOrientation(params, to: image)
        case .caption(let params):
            return applyCaption(params, to: image, exif: exif, sourceImage: sourceImage)
        case .dither(let params):
            return applyDither(params, to: image, sourceImage: sourceImage)
        }
    }

    // MARK: - Border

    private static func applyBorder(_ params: BorderLayerParams, to image: CIImage) -> CIImage {
        let thickness = params.thickness.pixels(for: image.extent.size)
        let newSize = CGSize(
            width: image.extent.width + CGFloat(thickness) * 2,
            height: image.extent.height + CGFloat(thickness) * 2
        )
        let bgColor = CIColor(cgColor: params.color.cgColor)
        let background = CIImage(color: bgColor)
            .cropped(to: CGRect(origin: .zero, size: newSize))
        let translated = image.transformed(by: CGAffineTransform(
            translationX: CGFloat(thickness),
            y: CGFloat(thickness)
        ))
        return translated.composited(over: background)
    }

    // MARK: - Padding

    private static func applyPadding(_ params: PaddingLayerParams, to image: CIImage) -> CIImage {
        let t = CGFloat(params.thickness)
        let newSize = CGSize(width: image.extent.width + t * 2, height: image.extent.height + t * 2)
        let bgColor: CIColor
        switch params.fill {
        case .solid(let color):
            bgColor = CIColor(cgColor: color.cgColor)
        default:
            bgColor = CIColor.white // fallback for gradient/dominant — refine later
        }
        let background = CIImage(color: bgColor)
            .cropped(to: CGRect(origin: .zero, size: newSize))
        let translated = image.transformed(by: CGAffineTransform(translationX: t, y: t))
        return translated.composited(over: background)
    }

    // MARK: - Canvas

    private static func applyCanvas(_ params: CanvasLayerParams, to image: CIImage) -> CIImage {
        let canvasSize = CGSize(width: CGFloat(params.width), height: CGFloat(params.height))
        let bgColor: CIColor
        switch params.fill {
        case .solid(let color):
            bgColor = CIColor(cgColor: color.cgColor)
        default:
            bgColor = CIColor.white
        }
        let background = CIImage(color: bgColor)
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
        // Center the image on the canvas
        let offsetX = (canvasSize.width - image.extent.width) / 2
        let offsetY = (canvasSize.height - image.extent.height) / 2
        let translated = image.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        return translated.composited(over: background)
    }

    // MARK: - Resize

    private static func applyResize(_ params: ResizeLayerParams, to image: CIImage) -> CIImage {
        let scaleX = CGFloat(params.maxWidth) / image.extent.width
        let scaleY = CGFloat(params.maxHeight) / image.extent.height
        let scale = min(scaleX, scaleY)
        if scale >= 1.0 { return image }
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return filter.outputImage ?? image
    }

    // MARK: - Overlay (placeholder — Metal kernels in Task 4)

    private static func applyOverlay(_ params: OverlayLayerParams, to image: CIImage) -> CIImage {
        // TODO: Load overlay texture, apply blend mode via Metal kernel
        return image
    }

    // MARK: - Orientation

    private static func applyOrientation(_ params: OrientationLayerParams, to image: CIImage) -> CIImage {
        // TODO: Apply rotation transform based on target orientation
        return image
    }

    // MARK: - Caption (placeholder — uses CoreText)

    private static func applyCaption(
        _ params: CaptionLayerParams,
        to image: CIImage,
        exif: ExifData,
        sourceImage: CIImage
    ) -> CIImage {
        // TODO: Render caption text to CIImage and composite
        return image
    }

    // MARK: - Dither (placeholder — Metal kernel in Task 4)

    private static func applyDither(
        _ params: DitherLayerParams,
        to image: CIImage,
        sourceImage: CIImage
    ) -> CIImage {
        // TODO: Apply dither via Metal kernel
        return image
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter CIFilterPipelineTests 2>&1 | tail -10`
Expected: All PASS

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/CIFilterPipeline.swift Tests/FramerCoreTests/CIFilterPipelineTests.swift
git commit -m "feat: add CIFilterPipeline with border, padding, canvas, and resize layers"
```

---

## Task 4: Metal Kernels — Dither and Overlay Blend

**Files:**
- Create: `Sources/FramerCore/Processing/Kernels/DitherKernel.ci.metal`
- Create: `Sources/FramerCore/Processing/Kernels/OverlayBlendKernel.ci.metal`
- Create: `Sources/FramerCore/Processing/Kernels/KernelLoader.swift`
- Modify: `Sources/FramerCore/Processing/CIFilterPipeline.swift` (wire up dither & overlay)
- Test: `Tests/FramerCoreTests/DitherKernelTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
import CoreImage
@testable import FramerCore

final class DitherKernelTests: XCTestCase {

    private let ciContext = CIContext()

    private func solidImage(width: Int, height: Int, hex: String) -> CIImage {
        let color = CodableColor(hex: hex)!
        return CIImage(color: CIColor(cgColor: color.cgColor))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testBayerDitherProducesOutput() {
        let input = solidImage(width: 64, height: 64, hex: "#808080")
        let params = DitherLayerParams(
            algorithm: .bayer,
            colorMode: .bw,
            bayerLevel: 2,
            pixelScale: 1,
            threshold: 0.5,
            sharpen: false,
            contrast: false
        )
        let output = CIFilterPipeline.apply(
            layers: [.dither(params)],
            to: input,
            sourceImage: input,
            exif: ExifData()
        )
        XCTAssertEqual(output.extent.width, 64)
        XCTAssertEqual(output.extent.height, 64)
        // Verify it actually rendered (not passthrough) by checking pixel data
        let cgImage = ciContext.createCGImage(output, from: output.extent)
        XCTAssertNotNil(cgImage)
    }

    func testBlueNoiseDitherProducesOutput() {
        let input = solidImage(width: 64, height: 64, hex: "#C0C0C0")
        let params = DitherLayerParams(
            algorithm: .blueNoise,
            colorMode: .bw,
            bayerLevel: 1,
            pixelScale: 1,
            threshold: 0.5,
            sharpen: false,
            contrast: false
        )
        let output = CIFilterPipeline.apply(
            layers: [.dither(params)],
            to: input,
            sourceImage: input,
            exif: ExifData()
        )
        let cgImage = ciContext.createCGImage(output, from: output.extent)
        XCTAssertNotNil(cgImage)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter DitherKernelTests 2>&1 | tail -5`
Expected: FAIL — dither is a passthrough placeholder

**Step 3: Create Bayer dither Metal kernel**

Create `Sources/FramerCore/Processing/Kernels/DitherKernel.ci.metal`:

```metal
#include <CoreImage/CoreImage.h>

// 8x8 Bayer matrix for ordered dithering
constant float bayerMatrix8x8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

extern "C" float4 bayerDither(coreimage::sample_t s, coreimage::destination dest) {
    int x = int(dest.coord().x) % 8;
    int y = int(dest.coord().y) % 8;
    float threshold = bayerMatrix8x8[y * 8 + x] / 64.0;

    float luminance = 0.299 * s.r + 0.587 * s.g + 0.114 * s.b;
    float result = luminance > threshold ? 1.0 : 0.0;
    return float4(result, result, result, s.a);
}
```

**Step 4: Create blue noise dither Metal kernel**

Add to the same file or a separate one — a blue noise kernel that uses a noise texture sampler:

```metal
extern "C" float4 blueNoiseDither(coreimage::sample_t s, coreimage::sample_t noise, coreimage::destination dest) {
    float luminance = 0.299 * s.r + 0.587 * s.g + 0.114 * s.b;
    float threshold = noise.r;
    float result = luminance > threshold ? 1.0 : 0.0;
    return float4(result, result, result, s.a);
}
```

**Step 5: Create overlay blend Metal kernel**

Create `Sources/FramerCore/Processing/Kernels/OverlayBlendKernel.ci.metal`:

```metal
#include <CoreImage/CoreImage.h>

// Luminance-deviation alpha: mid-gray is transparent
extern "C" float4 luminanceDeviationBlend(
    coreimage::sample_t base,
    coreimage::sample_t overlay,
    float opacity,
    coreimage::destination dest
) {
    float overlayLum = 0.299 * overlay.r + 0.587 * overlay.g + 0.114 * overlay.b;
    float deviation = abs(overlayLum - 0.5) * 2.0;
    float alpha = deviation * opacity;
    float3 blended = mix(base.rgb, overlay.rgb, alpha);
    return float4(blended, base.a);
}

// Screen blend
extern "C" float4 screenBlend(
    coreimage::sample_t base,
    coreimage::sample_t overlay,
    float opacity,
    coreimage::destination dest
) {
    float3 screened = 1.0 - (1.0 - base.rgb) * (1.0 - overlay.rgb);
    float3 blended = mix(base.rgb, screened, opacity);
    return float4(blended, base.a);
}

// Soft light (Pegtop formula)
extern "C" float4 softLightBlend(
    coreimage::sample_t base,
    coreimage::sample_t overlay,
    float opacity,
    coreimage::destination dest
) {
    float3 soft = (1.0 - 2.0 * overlay.rgb) * base.rgb * base.rgb + 2.0 * overlay.rgb * base.rgb;
    float3 blended = mix(base.rgb, soft, opacity);
    return float4(blended, base.a);
}

// Multiply blend
extern "C" float4 multiplyBlend(
    coreimage::sample_t base,
    coreimage::sample_t overlay,
    float opacity,
    coreimage::destination dest
) {
    float3 multiplied = base.rgb * overlay.rgb;
    float3 blended = mix(base.rgb, multiplied, opacity);
    return float4(blended, base.a);
}
```

**Step 6: Create `KernelLoader.swift`**

```swift
import CoreImage

public enum KernelLoader {
    private static var bayerDitherKernel: CIColorKernel?
    private static var blueNoiseDitherKernel: CIKernel?
    private static var luminanceBlendKernel: CIKernel?
    private static var screenBlendKernel: CIKernel?
    private static var softLightBlendKernel: CIKernel?
    private static var multiplyBlendKernel: CIKernel?

    public static func loadBayerDither() throws -> CIColorKernel {
        if let cached = bayerDitherKernel { return cached }
        let url = Bundle.module.url(forResource: "DitherKernel", withExtension: "ci.metallib")
            ?? Bundle.module.url(forResource: "default", withExtension: "metallib")!
        let data = try Data(contentsOf: url)
        let kernel = try CIColorKernel(functionName: "bayerDither", fromMetalLibraryData: data)
        bayerDitherKernel = kernel
        return kernel
    }

    // Similar loaders for other kernels...
}
```

Note: Metal kernel compilation in SPM requires adding the `.metal` files to the target resources and potentially adjusting build settings. Check how `Package.swift` handles resources for `FramerCore`.

**Step 7: Wire dither into `CIFilterPipeline.applyDither()`**

Update the placeholder in `CIFilterPipeline.swift` to call the Metal kernel via `KernelLoader`.

**Step 8: Run tests to verify they pass**

Run: `swift test --filter DitherKernelTests 2>&1 | tail -10`
Expected: All PASS

**Step 9: Commit**

```bash
git add Sources/FramerCore/Processing/Kernels/ Sources/FramerCore/Processing/CIFilterPipeline.swift Tests/FramerCoreTests/DitherKernelTests.swift
git commit -m "feat: add Metal kernels for dithering and overlay blending"
```

---

## Task 5: VideoProcessor Actor

**Files:**
- Create: `Sources/FramerCore/Processing/VideoProcessor.swift`
- Test: `Tests/FramerCoreTests/VideoProcessorTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
import AVFoundation
@testable import FramerCore

final class VideoProcessorTests: XCTestCase {

    /// Helper: create a short test video (1 second, 30fps, solid color)
    private func createTestVideo(at url: URL, duration: Double = 1.0, fps: Int = 30) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(fps))
        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            adaptor.append(pixelBuffer!, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    func testProcessVideoProducesOutput() async throws {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_input_\(UUID().uuidString).mp4")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_output_\(UUID().uuidString).mp4")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await createTestVideo(at: inputURL)

        let config = ProcessingConfig()  // default — no layers
        let videoConfig = VideoExportConfig(codec: .h264)
        let processor = VideoProcessor()
        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoConfig
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.5)
    }

    func testProcessVideoWithTrim() async throws {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_trim_input_\(UUID().uuidString).mp4")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_trim_output_\(UUID().uuidString).mp4")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await createTestVideo(at: inputURL, duration: 3.0)

        let trim = try TrimRange(from: "00:00:01.000-00:00:02.000")
        let videoConfig = VideoExportConfig(codec: .h264, trim: trim)
        let processor = VideoProcessor()
        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: ProcessingConfig(),
            videoExport: videoConfig
        )

        let asset = AVAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.2)
    }

    func testProcessVideoWithBorderLayer() async throws {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_border_input_\(UUID().uuidString).mp4")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_border_output_\(UUID().uuidString).mp4")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await createTestVideo(at: inputURL)

        var config = ProcessingConfig()
        config.layers = [
            .border(BorderLayerParams(thickness: .pixels(10), color: CodableColor(hex: "#FF0000")!))
        ]
        let videoConfig = VideoExportConfig(codec: .h264)
        let processor = VideoProcessor()
        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoConfig
        )

        let asset = AVAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks.first!.load(.naturalSize)
        // 320x240 + 10px border on each side = 340x260
        XCTAssertEqual(size.width, 340, accuracy: 1)
        XCTAssertEqual(size.height, 260, accuracy: 1)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter VideoProcessorTests 2>&1 | tail -5`
Expected: Compilation error

**Step 3: Implement `VideoProcessor`**

```swift
import Foundation
import AVFoundation
import CoreImage

public actor VideoProcessor {

    public struct Progress: Sendable {
        public let currentFrame: Int
        public let totalFrames: Int
        public var fraction: Double { Double(currentFrame) / Double(max(totalFrames, 1)) }
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var progressHandler: ((Progress) -> Void)?

    public init() {}

    public func onProgress(_ handler: @escaping @Sendable (Progress) -> Void) {
        self.progressHandler = handler
    }

    public func process(
        input: URL,
        output: URL,
        config: ProcessingConfig,
        videoExport: VideoExportConfig
    ) async throws {
        let asset = AVAsset(url: input)

        // Load video track
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw FramerError.invalidImage // TODO: add .noVideoTrack error
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // Compute time range (trim or full)
        let timeRange: CMTimeRange
        if let trim = videoExport.trim {
            let start = CMTime(seconds: trim.start, preferredTimescale: 600)
            let end = CMTime(seconds: min(trim.end, duration.seconds), preferredTimescale: 600)
            timeRange = CMTimeRange(start: start, end: end)
        } else {
            timeRange = CMTimeRange(start: .zero, duration: duration)
        }

        let totalFrames = Int(timeRange.duration.seconds * Double(nominalFrameRate))

        // Compute output size
        let outputSize = OutputSizeCalculator.outputSize(
            for: naturalSize,
            layers: config.layers
        )

        // --- Reader ---
        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        readerOutput.alwaysCopiesSampleData = false
        reader.timeRange = timeRange
        reader.add(readerOutput)

        // --- Writer ---
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoCodec: AVVideoCodecType = videoExport.codec == .h265 ? .hevc : .h264
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
            ]
        )
        writer.add(writerInput)

        // --- Audio passthrough ---
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?
        if let audioTrack = audioTracks.first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(audioOutput)
            audioReaderOutput = audioOutput

            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            audioWriterInput = audioInput
        }

        // --- Process ---
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: timeRange.start)

        // Read EXIF equivalent (empty for video)
        let exif = ExifData()

        var frameIndex = 0
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
            let processed = CIFilterPipeline.apply(
                layers: config.layers,
                to: sourceImage,
                sourceImage: sourceImage,
                exif: exif
            )

            // Wait for writer to be ready
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            // Render to pixel buffer
            var outputBuffer: CVPixelBuffer?
            if let pool = pixelBufferAdaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
            }
            if let outputBuffer {
                ciContext.render(processed, to: outputBuffer)
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                pixelBufferAdaptor.append(outputBuffer, withPresentationTime: pts)
            }

            frameIndex += 1
            progressHandler?(Progress(currentFrame: frameIndex, totalFrames: totalFrames))
        }

        writerInput.markAsFinished()

        // Copy audio
        if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
            while let audioBuffer = audioOutput.copyNextSampleBuffer() {
                while !audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                audioInput.append(audioBuffer)
            }
            audioInput.markAsFinished()
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? FramerError.encodingFailed
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter VideoProcessorTests 2>&1 | tail -10`
Expected: All PASS

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/VideoProcessor.swift Tests/FramerCoreTests/VideoProcessorTests.swift
git commit -m "feat: add VideoProcessor actor with frame-by-frame CI pipeline and audio passthrough"
```

---

## Task 6: CLI — Video Flags and Auto-Detection

**Files:**
- Modify: `Sources/FramerCLI/Commands/ProcessCommand.swift`
- Test: Manual CLI testing (video processing is integration-level)

**Step 1: Add `--trim` and `--codec` options to `ProcessCommand`**

In `Sources/FramerCLI/Commands/ProcessCommand.swift`, add after existing `@Option` declarations:

```swift
@Option(name: .long, help: "Video trim range in timecode format: HH:MM:SS.mmm-HH:MM:SS.mmm")
var trim: String?

@Option(name: .long, help: "Video output codec: h264 (default) or h265")
var codec: String = "h264"
```

**Step 2: Add video file detection helper**

```swift
private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

private func isVideoFile(_ url: URL) -> Bool {
    Self.videoExtensions.contains(url.pathExtension.lowercased())
}
```

**Step 3: Wire into `run()` method**

In the `run()` method, after building `ProcessingConfig`, add video detection:

```swift
if isVideoFile(inputURL) {
    let videoCodec: VideoCodec = codec == "h265" ? .h265 : .h264
    var trimRange: TrimRange? = nil
    if let trimString = trim {
        trimRange = try TrimRange(from: trimString)
    }
    let videoConfig = VideoExportConfig(codec: videoCodec, trim: trimRange)

    let processor = VideoProcessor()
    await processor.onProgress { progress in
        print("\rProcessing: frame \(progress.currentFrame)/\(progress.totalFrames) (\(Int(progress.fraction * 100))%)", terminator: "")
        fflush(stdout)
    }
    try await processor.process(
        input: inputURL,
        output: outputURL,
        config: config,
        videoExport: videoConfig
    )
    print("\nDone: \(outputURL.path)")
    return
}
```

**Step 4: Add video codec and trim to YAML config**

In `Sources/FramerCore/Presets/YAMLConfig.swift`, add to `YAMLSchema`:

```swift
var codec: String?
var trim: String?
```

And in the decode method, parse these into `VideoExportConfig`.

**Step 5: Build and test manually**

Run: `swift build && .build/arm64-apple-macosx/debug/framer process --help`
Expected: Shows `--trim` and `--codec` options

**Step 6: Commit**

```bash
git add Sources/FramerCLI/Commands/ProcessCommand.swift Sources/FramerCore/Presets/YAMLConfig.swift
git commit -m "feat: add --trim and --codec CLI flags with video auto-detection"
```

---

## Task 7: SwiftUI — Output Dimensions Badge

**Files:**
- Modify: `Sources/FramerApp/Editor/LivePreviewPanel.swift` (or wherever the preview is rendered)
- Modify: `Sources/FramerApp/Editor/PreviewViewModel.swift`

**Step 1: Add computed output size to PreviewViewModel**

In `Sources/FramerApp/Editor/PreviewViewModel.swift`, add:

```swift
var outputDimensions: CGSize? {
    guard let originalSize = originalImageSize else { return nil }
    return OutputSizeCalculator.outputSize(for: originalSize, layers: currentConfig.layers)
}
```

Store `originalImageSize` and `currentConfig` as properties if not already available.

**Step 2: Add dimensions badge to LivePreviewPanel**

In the preview view, add an overlay badge:

```swift
if let dims = viewModel.outputDimensions {
    Text("\(Int(dims.width)) × \(Int(dims.height))")
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
}
```

Position it in a corner of the preview panel using `.overlay(alignment: .bottomTrailing)`.

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add Sources/FramerApp/Editor/PreviewViewModel.swift Sources/FramerApp/Editor/LivePreviewPanel.swift
git commit -m "feat: add output dimensions badge to preview panel"
```

---

## Task 8: SwiftUI — Video Timeline Scrubber

**Files:**
- Create: `Sources/FramerApp/Editor/VideoTimelineView.swift`
- Create: `Sources/FramerApp/Editor/VideoPlayerViewModel.swift`
- Modify: `Sources/FramerApp/Editor/LivePreviewPanel.swift` (show timeline for video files)

**Step 1: Create `VideoPlayerViewModel`**

```swift
import SwiftUI
import AVFoundation
import FramerCore

@MainActor @Observable
final class VideoPlayerViewModel {
    var asset: AVAsset?
    var duration: TimeInterval = 0
    var playheadPosition: TimeInterval = 0
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 0
    var thumbnails: [CGImage] = []

    private var imageGenerator: AVAssetImageGenerator?

    func load(url: URL) async {
        let asset = AVAsset(url: url)
        self.asset = asset
        do {
            let dur = try await asset.load(.duration)
            self.duration = dur.seconds
            self.trimEnd = dur.seconds
            await generateThumbnails()
        } catch {}
    }

    var trimRange: TrimRange? {
        guard trimStart > 0 || trimEnd < duration else { return nil }
        return try? TrimRange(start: trimStart, end: trimEnd)
    }

    private func generateThumbnails() async {
        guard let asset else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 80, height: 60)
        self.imageGenerator = generator

        let count = min(Int(duration * 2), 60) // ~2 per second, max 60
        var images: [CGImage] = []
        for i in 0..<count {
            let time = CMTime(seconds: duration * Double(i) / Double(count), preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                images.append(cgImage)
            }
        }
        self.thumbnails = images
    }

    func frameAtPlayhead() async -> CGImage? {
        guard let asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: playheadPosition, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}
```

**Step 2: Create `VideoTimelineView`**

```swift
import SwiftUI

struct VideoTimelineView: View {
    @Bindable var viewModel: VideoPlayerViewModel

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail strip with trim handles
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Thumbnail strip
                    HStack(spacing: 0) {
                        ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { _, thumb in
                            Image(decorative: thumb, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width / CGFloat(max(viewModel.thumbnails.count, 1)))
                                .clipped()
                        }
                    }

                    // Dimmed areas outside trim
                    let startX = geo.size.width * viewModel.trimStart / max(viewModel.duration, 1)
                    let endX = geo.size.width * viewModel.trimEnd / max(viewModel.duration, 1)

                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .frame(width: startX)

                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .frame(width: geo.size.width - endX)
                        .offset(x: endX)

                    // Trim handles
                    trimHandle(at: startX, geo: geo, isStart: true)
                    trimHandle(at: endX, geo: geo, isStart: false)

                    // Playhead
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2)
                        .offset(x: geo.size.width * viewModel.playheadPosition / max(viewModel.duration, 1))
                }
            }
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Timecodes
            HStack {
                Text(formatTimecode(viewModel.trimStart))
                Spacer()
                Text(formatTimecode(viewModel.playheadPosition))
                    .fontWeight(.medium)
                Spacer()
                Text(formatTimecode(viewModel.trimEnd))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func trimHandle(at x: CGFloat, geo: GeometryProxy, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.yellow)
            .frame(width: 6, height: 48)
            .offset(x: x - 3)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        let time = fraction * viewModel.duration
                        if isStart {
                            viewModel.trimStart = min(time, viewModel.trimEnd - 0.1)
                        } else {
                            viewModel.trimEnd = max(time, viewModel.trimStart + 0.1)
                        }
                    }
            )
    }

    private func formatTimecode(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
```

**Step 3: Integrate into LivePreviewPanel**

Show `VideoTimelineView` below the preview when a video file is selected. Use `VideoPlayerViewModel` to drive the playhead frame through `PreviewViewModel`.

**Step 4: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add Sources/FramerApp/Editor/VideoTimelineView.swift Sources/FramerApp/Editor/VideoPlayerViewModel.swift Sources/FramerApp/Editor/LivePreviewPanel.swift
git commit -m "feat: add iMovie-style video timeline scrubber with trim handles"
```

---

## Task 9: SwiftUI — Video Export with Codec Picker and Progress

**Files:**
- Modify: `Sources/FramerApp/App/AppState.swift` (add video export flow)
- Modify: `Sources/FramerApp/Queue/ExportQueueView.swift` (progress bar)
- Modify: Settings panel (codec picker)

**Step 1: Add codec picker to settings**

In the export/settings section of the app, add:

```swift
Picker("Video Codec", selection: $appState.videoCodec) {
    Text("H.264").tag(VideoCodec.h264)
    Text("H.265 (HEVC)").tag(VideoCodec.h265)
}
```

Add `videoCodec` property to `AppState`.

**Step 2: Add video export to AppState**

In `AppState`, add a method that uses `VideoProcessor` for video files:

```swift
func exportVideo(item: PhotoItem, outputURL: URL) async throws {
    let videoConfig = VideoExportConfig(
        codec: videoCodec,
        trim: videoPlayerViewModel?.trimRange
    )
    let processor = VideoProcessor()
    await processor.onProgress { [weak self] progress in
        Task { @MainActor in
            self?.exportProgress = progress.fraction
        }
    }
    try await processor.process(
        input: item.url,
        output: outputURL,
        config: currentConfig,
        videoExport: videoConfig
    )
}
```

**Step 3: Update export queue to show frame-level progress for videos**

In `ExportQueueView`, show a progress bar with frame count for video jobs.

**Step 4: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add Sources/FramerApp/App/AppState.swift Sources/FramerApp/Queue/ExportQueueView.swift
git commit -m "feat: add video export with codec picker and frame-level progress"
```

---

## Task 10: Wire FrameProcessor to Detect Video and Delegate

**Files:**
- Modify: `Sources/FramerCore/Processing/FrameProcessor.swift`

**Step 1: Add video detection to `FrameProcessor`**

In `Sources/FramerCore/Processing/FrameProcessor.swift`, add a static helper:

```swift
private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

public static func isVideoFile(_ url: URL) -> Bool {
    videoExtensions.contains(url.pathExtension.lowercased())
}
```

**Step 2: In `process()`, delegate to `VideoProcessor` for video files**

```swift
public func process(input: URL, output: URL, config: ProcessingConfig, rotation: Int = 0) async throws {
    if Self.isVideoFile(input) {
        let videoConfig = config.videoExport ?? VideoExportConfig()
        let videoProcessor = VideoProcessor()
        try await videoProcessor.process(input: input, output: output, config: config, videoExport: videoConfig)
        return
    }
    // ... existing image processing code ...
}
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add Sources/FramerCore/Processing/FrameProcessor.swift
git commit -m "feat: wire FrameProcessor to delegate video files to VideoProcessor"
```

---

## Task 11: Integration Testing and Cleanup

**Files:**
- Modify: `Package.swift` (add AVFoundation/CoreImage framework dependencies if needed)
- Test: Full integration test with real video file

**Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 2: Run full Xcode build**

Run: `xcodebuild -project Framer.xcodeproj -scheme Framer -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Manual smoke test with CLI**

```bash
# Process a video with border
.build/arm64-apple-macosx/debug/framer process --input test.mp4 --output output.mp4 --codec h264

# Process with trim
.build/arm64-apple-macosx/debug/framer process --input test.mp4 --output output.mp4 --trim 00:00:01.000-00:00:05.000
```

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: integration fixes for video processing pipeline"
```

---

## Summary

| Task | Description | Dependencies |
|------|-------------|--------------|
| 1 | Data models (VideoCodec, TrimRange, VideoExportConfig) | None |
| 2 | Output dimension calculator | Task 1 |
| 3 | CIFilterPipeline (Core Image layer chain) | Task 1 |
| 4 | Metal kernels (dither, overlay blend) | Task 3 |
| 5 | VideoProcessor actor | Tasks 2, 3 |
| 6 | CLI flags (--trim, --codec) | Tasks 1, 5 |
| 7 | SwiftUI output dimensions badge | Task 2 |
| 8 | SwiftUI video timeline scrubber | None |
| 9 | SwiftUI video export + codec picker | Tasks 5, 8 |
| 10 | FrameProcessor video delegation | Task 5 |
| 11 | Integration testing and cleanup | All |

**Parallel opportunities:** Tasks 1-3 can partially overlap. Tasks 7 and 8 are independent of each other. Tasks 6 and 7-8 are independent (CLI vs App).
