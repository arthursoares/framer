# Dithering Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `.dither` composition layer with five algorithms (Bayer, Floyd-Steinberg, Atkinson, Blue Noise, Artistic Drip), three color modes (B&W, two-tone, color), and pixel scale control.

**Architecture:** New `DitherLayerParams` struct + `DitherRenderer` static enum following the existing CaptionRenderer/BorderRenderer patterns. Integrates into `BorderRenderer.applyLayers` as a new switch case. All algorithms operate in linear RGB for perceptual correctness.

**Tech Stack:** Swift 5.10, CoreGraphics, Accelerate (vDSP for gamma conversion), XCTest

---

### Task 1: Add DitherLayerParams and DitherAlgorithm/DitherColorMode Types

**Files:**
- Modify: `Sources/FramerCore/Models/CompositionLayer.swift`
- Test: `Tests/FramerCoreTests/CompositionLayerTests.swift`

**Step 1: Write the failing test**

Add to `Tests/FramerCoreTests/CompositionLayerTests.swift`:

```swift
func test_ditherLayer_roundtripsJSON() throws {
    let params = DitherLayerParams(
        algorithm: .atkinson,
        colorMode: .bw,
        bayerLevel: 2,
        pixelScale: 1
    )
    let layer = CompositionLayer.dither(params)
    let data = try JSONEncoder().encode(layer)
    let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
    XCTAssertEqual(layer, decoded)
}

func test_ditherLayer_twoTone_roundtripsJSON() throws {
    let params = DitherLayerParams(
        algorithm: .bayer,
        colorMode: .twoTone(foreground: .black, background: CodableColor(unchecked: "#C4CFA1")),
        bayerLevel: 3,
        pixelScale: 4
    )
    let layer = CompositionLayer.dither(params)
    let data = try JSONEncoder().encode(layer)
    let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
    XCTAssertEqual(layer, decoded)
}

func test_ditherLayer_color_roundtripsJSON() throws {
    let params = DitherLayerParams(
        algorithm: .floydSteinberg,
        colorMode: .color(levels: 4),
        bayerLevel: 2,
        pixelScale: 2
    )
    let layer = CompositionLayer.dither(params)
    let data = try JSONEncoder().encode(layer)
    let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
    XCTAssertEqual(layer, decoded)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CompositionLayerTests 2>&1 | tail -20`
Expected: Compile error — `DitherLayerParams` not found.

**Step 3: Write minimal implementation**

In `Sources/FramerCore/Models/CompositionLayer.swift`, add before the `// MARK: - CompositionLayer` section:

```swift
// MARK: - Dither

public enum DitherAlgorithm: String, Codable, Sendable, CaseIterable {
    case bayer
    case floydSteinberg
    case atkinson
    case blueNoise
    case artisticDrip

    public var label: String {
        switch self {
        case .bayer: return "Bayer"
        case .floydSteinberg: return "Floyd-Steinberg"
        case .atkinson: return "Atkinson"
        case .blueNoise: return "Blue Noise"
        case .artisticDrip: return "Artistic Drip"
        }
    }
}

public enum DitherColorMode: Codable, Equatable, Sendable {
    case bw
    case twoTone(foreground: CodableColor, background: CodableColor)
    case color(levels: Int)

    private enum CodingKeys: String, CodingKey {
        case type, foreground, background, levels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "bw":
            self = .bw
        case "twoTone":
            let fg = try container.decode(CodableColor.self, forKey: .foreground)
            let bg = try container.decode(CodableColor.self, forKey: .background)
            self = .twoTone(foreground: fg, background: bg)
        case "color":
            let levels = try container.decode(Int.self, forKey: .levels)
            self = .color(levels: levels)
        default:
            self = .bw
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bw:
            try container.encode("bw", forKey: .type)
        case .twoTone(let fg, let bg):
            try container.encode("twoTone", forKey: .type)
            try container.encode(fg, forKey: .foreground)
            try container.encode(bg, forKey: .background)
        case .color(let levels):
            try container.encode("color", forKey: .type)
            try container.encode(levels, forKey: .levels)
        }
    }
}

public struct DitherLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var algorithm: DitherAlgorithm
    public var colorMode: DitherColorMode
    public var bayerLevel: Int
    public var pixelScale: Int

    public init(
        id: UUID = UUID(),
        algorithm: DitherAlgorithm = .atkinson,
        colorMode: DitherColorMode = .bw,
        bayerLevel: Int = 2,
        pixelScale: Int = 1
    ) {
        self.id = id
        self.algorithm = algorithm
        self.colorMode = colorMode
        self.bayerLevel = max(1, min(4, bayerLevel))
        self.pixelScale = max(1, min(8, pixelScale))
    }
}
```

Then add `.dither(DitherLayerParams)` to the `CompositionLayer` enum and update every switch:

- `id`: `case .dither(let p): return p.id`
- `label`: `case .dither: return "Dither"`
- `iconName`: `case .dither: return "circle.dotted"`
- `init(from decoder:)`: `case "dither": self = .dither(try container.decode(DitherLayerParams.self, forKey: .params))`
- `encode(to:)`: `case .dither(let p): try container.encode("dither", forKey: .type); try container.encode(p, forKey: .params)`

**Step 4: Run test to verify it passes**

Run: `swift test --filter CompositionLayerTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Models/CompositionLayer.swift Tests/FramerCoreTests/CompositionLayerTests.swift
git commit -m "feat: add DitherLayerParams model and CompositionLayer.dither case"
```

---

### Task 2: Create DitherRenderer with Gamma Helpers and Bayer Algorithm

**Files:**
- Create: `Sources/FramerCore/Processing/DitherRenderer.swift`
- Create: `Tests/FramerCoreTests/DitherRendererTests.swift`

**Step 1: Write the failing tests**

Create `Tests/FramerCoreTests/DitherRendererTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class DitherRendererTests: XCTestCase {
    /// Creates a test image with a horizontal gradient from black to white.
    func makeGradientImage(width: Int = 200, height: Int = 100) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            let gray = CGFloat(x) / CGFloat(width - 1)
            ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }

    func makeSolidImage(width: Int = 200, height: Int = 100, gray: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - Bayer

    func test_bayer_bw_preservesDimensions() throws {
        let image = makeGradientImage()
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: 1)
        let result = try DitherRenderer.apply(to: image, params: params)
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_bayer_bw_producesOnlyBlackAndWhite() throws {
        let image = makeGradientImage()
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: 1)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for p in pixels {
            XCTAssertTrue(
                (p.r == 0 && p.g == 0 && p.b == 0) || (p.r == 255 && p.g == 255 && p.b == 255),
                "Found non-B&W pixel: \(p.r), \(p.g), \(p.b)"
            )
        }
    }

    func test_bayer_twoTone_producesOnlySpecifiedColors() throws {
        let image = makeGradientImage()
        let fg = CodableColor(unchecked: "#00FF00")
        let bg = CodableColor(unchecked: "#FF0000")
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .twoTone(foreground: fg, background: bg), bayerLevel: 2, pixelScale: 1)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for p in pixels {
            let isFG = p.r == 0 && p.g == 255 && p.b == 0
            let isBG = p.r == 255 && p.g == 0 && p.b == 0
            XCTAssertTrue(isFG || isBG, "Found unexpected pixel: \(p.r), \(p.g), \(p.b)")
        }
    }

    func test_bayer_color_respectsLevels() throws {
        let image = makeGradientImage()
        let levels = 3
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .color(levels: levels), bayerLevel: 2, pixelScale: 1)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        var uniqueR = Set<UInt8>()
        for p in pixels { uniqueR.insert(p.r) }
        XCTAssertLessThanOrEqual(uniqueR.count, levels, "R channel has \(uniqueR.count) unique values, expected <= \(levels)")
    }

    func test_bayer_differentLevelsProduceDifferentOutput() throws {
        let image = makeGradientImage()
        let result1 = try DitherRenderer.apply(to: image, params: DitherLayerParams(algorithm: .bayer, bayerLevel: 1, pixelScale: 1))
        let result2 = try DitherRenderer.apply(to: image, params: DitherLayerParams(algorithm: .bayer, bayerLevel: 4, pixelScale: 1))
        let p1 = extractPixels(from: result1)
        let p2 = extractPixels(from: result2)
        XCTAssertNotEqual(p1.map { $0.r }, p2.map { $0.r }, "Different Bayer levels should produce different output")
    }

    func test_gammaCorrection_midGrayDithersToMoreThanHalfWhite() throws {
        // sRGB 50% gray (186/255 ≈ 0.73 in sRGB, 0.5 in linear).
        // After linear conversion, luminance = 0.5, so dithering should produce ~50% white pixels.
        // Without gamma correction, 186/255 ≈ 0.73 would produce ~73% white — too many.
        // With gamma correction, 128/255 sRGB ≈ 0.216 linear — would produce ~22% white, too few.
        // So we use 186 sRGB → 0.5 linear → ~50% white.
        let image = makeSolidImage(gray: 186.0 / 255.0)
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 3, pixelScale: 1)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        let whiteCount = pixels.filter { $0.r == 255 }.count
        let ratio = Double(whiteCount) / Double(pixels.count)
        // Should be ~50% white (±10%), proving gamma is applied
        XCTAssertGreaterThan(ratio, 0.40, "Expected ~50% white pixels, got \(ratio)")
        XCTAssertLessThan(ratio, 0.60, "Expected ~50% white pixels, got \(ratio)")
    }

    // MARK: - Pixel Scale

    func test_pixelScale_preservesDimensions() throws {
        let image = makeGradientImage()
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: 4)
        let result = try DitherRenderer.apply(to: image, params: params)
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_pixelScale_producesBlockyOutput() throws {
        let image = makeGradientImage(width: 200, height: 100)
        let scale = 4
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: scale)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        // Check that pixels form scale×scale blocks: pixel at (0,0) == pixel at (1,0) == pixel at (0,1) etc.
        let w = result.width
        // Check a few sample blocks
        for by in stride(from: 0, to: min(result.height, 20), by: scale) {
            for bx in stride(from: 0, to: min(w, 40), by: scale) {
                let ref = pixels[by * w + bx]
                for dy in 0..<min(scale, result.height - by) {
                    for dx in 0..<min(scale, w - bx) {
                        let p = pixels[(by + dy) * w + (bx + dx)]
                        XCTAssertEqual(p.r, ref.r, "Block at (\(bx),\(by)) not uniform at offset (\(dx),\(dy))")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    struct Pixel { let r: UInt8, g: UInt8, b: UInt8 }

    func extractPixels(from image: CGImage) -> [Pixel] {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h,
                           bitsPerComponent: 8, bytesPerRow: w * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var pixels = [Pixel]()
        pixels.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            let off = i * 4
            pixels.append(Pixel(r: data[off], g: data[off + 1], b: data[off + 2]))
        }
        return pixels
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DitherRendererTests 2>&1 | tail -20`
Expected: Compile error — `DitherRenderer` not found.

**Step 3: Write the implementation**

Create `Sources/FramerCore/Processing/DitherRenderer.swift`:

```swift
import Foundation
import CoreGraphics
import Accelerate

public enum DitherRenderer {
    // MARK: - Public API

    public static func apply(to image: CGImage, params: DitherLayerParams) throws -> CGImage {
        let w = image.width, h = image.height

        // Pixel scale: downscale, dither, upscale with nearest-neighbor
        let workImage: CGImage
        let workW: Int, workH: Int
        if params.pixelScale > 1 {
            workW = max(1, w / params.pixelScale)
            workH = max(1, h / params.pixelScale)
            workImage = try resize(image, width: workW, height: workH, interpolation: .high)
        } else {
            workW = w
            workH = h
            workImage = image
        }

        // Extract RGBA pixels
        var pixels = try extractRGBA(from: workImage, width: workW, height: workH)

        // Convert sRGB → linear
        sRGBToLinear(&pixels)

        // Apply dithering algorithm
        switch params.algorithm {
        case .bayer:
            applyBayer(to: &pixels, width: workW, height: workH, level: params.bayerLevel, colorMode: params.colorMode)
        case .floydSteinberg:
            applyFloydSteinberg(to: &pixels, width: workW, height: workH, colorMode: params.colorMode)
        case .atkinson:
            applyAtkinson(to: &pixels, width: workW, height: workH, colorMode: params.colorMode)
        case .blueNoise:
            applyBlueNoise(to: &pixels, width: workW, height: workH, colorMode: params.colorMode)
        case .artisticDrip:
            applyArtisticDrip(to: &pixels, width: workW, height: workH, colorMode: params.colorMode)
        }

        // Convert linear → sRGB
        linearToSRGB(&pixels)

        // Apply color mode mapping (two-tone replaces colors after quantization)
        applyColorMapping(&pixels, colorMode: params.colorMode)

        // Write back to CGImage
        var result = try createImage(from: pixels, width: workW, height: workH)

        // Upscale back to original size with nearest-neighbor
        if params.pixelScale > 1 {
            result = try resize(result, width: w, height: h, interpolation: .none)
        }

        return result
    }

    // MARK: - Pixel Buffer

    struct PixelF {
        var r: Float, g: Float, b: Float, a: Float
    }

    // MARK: - Gamma Conversion

    /// sRGB → linear: each channel. Standard IEC 61966-2-1.
    static func sRGBToLinear(_ pixels: inout [PixelF]) {
        for i in pixels.indices {
            pixels[i].r = srgbChannelToLinear(pixels[i].r)
            pixels[i].g = srgbChannelToLinear(pixels[i].g)
            pixels[i].b = srgbChannelToLinear(pixels[i].b)
        }
    }

    static func linearToSRGB(_ pixels: inout [PixelF]) {
        for i in pixels.indices {
            pixels[i].r = linearChannelToSRGB(pixels[i].r)
            pixels[i].g = linearChannelToSRGB(pixels[i].g)
            pixels[i].b = linearChannelToSRGB(pixels[i].b)
        }
    }

    @inline(__always)
    private static func srgbChannelToLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    @inline(__always)
    private static func linearChannelToSRGB(_ c: Float) -> Float {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    // MARK: - Pixel Extraction

    static func extractRGBA(from image: CGImage, width: Int, height: Int) throws -> [PixelF] {
        let count = width * height
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { throw FramerError.invalidImage(URL(fileURLWithPath: "")) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { throw FramerError.invalidImage(URL(fileURLWithPath: "")) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: count * 4)
        var pixels = [PixelF](repeating: PixelF(r: 0, g: 0, b: 0, a: 1), count: count)
        let scale: Float = 1.0 / 255.0
        for i in 0..<count {
            let off = i * 4
            pixels[i] = PixelF(
                r: Float(bytes[off]) * scale,
                g: Float(bytes[off + 1]) * scale,
                b: Float(bytes[off + 2]) * scale,
                a: Float(bytes[off + 3]) * scale
            )
        }
        return pixels
    }

    static func createImage(from pixels: [PixelF], width: Int, height: Int) throws -> CGImage {
        let count = width * height
        var bytes = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count {
            let off = i * 4
            bytes[off]     = UInt8(min(max(pixels[i].r * 255, 0), 255))
            bytes[off + 1] = UInt8(min(max(pixels[i].g * 255, 0), 255))
            bytes[off + 2] = UInt8(min(max(pixels[i].b * 255, 0), 255))
            bytes[off + 3] = UInt8(min(max(pixels[i].a * 255, 0), 255))
        }
        let ctx = CGContext(data: &bytes, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx, let image = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return image
    }

    // MARK: - Resize

    private static func resize(_ image: CGImage, width: Int, height: Int, interpolation: CGInterpolationQuality) throws -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { throw FramerError.invalidImage(URL(fileURLWithPath: "")) }
        ctx.interpolationQuality = interpolation
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else { throw FramerError.invalidImage(URL(fileURLWithPath: "")) }
        return result
    }

    // MARK: - Quantization

    /// Quantize a value in [0,1] to N evenly-spaced levels, returning the nearest level.
    @inline(__always)
    static func quantize(_ value: Float, levels: Int) -> Float {
        let n = Float(levels - 1)
        return (value * n).rounded() / n
    }

    /// Compute luminance from linear RGB.
    @inline(__always)
    static func luminance(_ p: PixelF) -> Float {
        0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
    }

    // MARK: - Bayer Ordered Dithering

    /// Generates a Bayer threshold matrix of size 2^(level+1) × 2^(level+1).
    static func bayerMatrix(level: Int) -> (matrix: [Float], size: Int) {
        // Level 0: 2×2 base matrix
        var matrix: [Float] = [0, 2, 3, 1]
        var size = 2

        for _ in 0..<level {
            let newSize = size * 2
            var newMatrix = [Float](repeating: 0, count: newSize * newSize)
            for y in 0..<newSize {
                for x in 0..<newSize {
                    let oldVal = matrix[(y % size) * size + (x % size)]
                    let quadrant: Float
                    if y < size {
                        quadrant = x < size ? 0 : 2
                    } else {
                        quadrant = x < size ? 3 : 1
                    }
                    newMatrix[y * newSize + x] = 4 * oldVal + quadrant
                }
            }
            matrix = newMatrix
            size = newSize
        }

        // Normalize to [0, 1]
        let count = Float(size * size)
        for i in matrix.indices {
            matrix[i] = (matrix[i] + 0.5) / count
        }
        return (matrix, size)
    }

    static func applyBayer(to pixels: inout [PixelF], width: Int, height: Int, level: Int, colorMode: DitherColorMode) {
        let (matrix, matrixSize) = bayerMatrix(level: max(0, level - 1))
        let levels = colorModeLevels(colorMode)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let threshold = matrix[(y % matrixSize) * matrixSize + (x % matrixSize)] - 0.5
                let p = pixels[i]
                if levels == 2 {
                    let lum = luminance(p)
                    let q: Float = (lum + threshold / Float(levels)) > 0.5 ? 1 : 0
                    pixels[i].r = q
                    pixels[i].g = q
                    pixels[i].b = q
                } else {
                    pixels[i].r = quantize(p.r + threshold / Float(levels), levels: levels)
                    pixels[i].g = quantize(p.g + threshold / Float(levels), levels: levels)
                    pixels[i].b = quantize(p.b + threshold / Float(levels), levels: levels)
                }
            }
        }
    }

    // MARK: - Error Diffusion Helpers

    typealias DiffusionKernel = [(dx: Int, dy: Int, weight: Float)]

    static func applyErrorDiffusion(
        to pixels: inout [PixelF],
        width: Int, height: Int,
        kernel: DiffusionKernel,
        colorMode: DitherColorMode
    ) {
        let levels = colorModeLevels(colorMode)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let old = pixels[i]

                let newR: Float, newG: Float, newB: Float
                if levels == 2 {
                    let lum = luminance(old)
                    let q: Float = lum > 0.5 ? 1 : 0
                    newR = q; newG = q; newB = q
                } else {
                    newR = quantize(old.r, levels: levels)
                    newG = quantize(old.g, levels: levels)
                    newB = quantize(old.b, levels: levels)
                }

                let errR = old.r - newR
                let errG = old.g - newG
                let errB = old.b - newB

                pixels[i].r = newR
                pixels[i].g = newG
                pixels[i].b = newB

                for (dx, dy, weight) in kernel {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let ni = ny * width + nx
                    pixels[ni].r += errR * weight
                    pixels[ni].g += errG * weight
                    pixels[ni].b += errB * weight
                }
            }
        }
    }

    // MARK: - Floyd-Steinberg

    static func applyFloydSteinberg(to pixels: inout [PixelF], width: Int, height: Int, colorMode: DitherColorMode) {
        let kernel: DiffusionKernel = [
            (1, 0, 7.0/16.0),
            (-1, 1, 3.0/16.0),
            (0, 1, 5.0/16.0),
            (1, 1, 1.0/16.0),
        ]
        applyErrorDiffusion(to: &pixels, width: width, height: height, kernel: kernel, colorMode: colorMode)
    }

    // MARK: - Atkinson

    static func applyAtkinson(to pixels: inout [PixelF], width: Int, height: Int, colorMode: DitherColorMode) {
        // Atkinson: 1/8 to each of 6 neighbors (only 75% of error propagated)
        let w: Float = 1.0 / 8.0
        let kernel: DiffusionKernel = [
            (1, 0, w),
            (2, 0, w),
            (-1, 1, w),
            (0, 1, w),
            (1, 1, w),
            (0, 2, w),
        ]
        applyErrorDiffusion(to: &pixels, width: width, height: height, kernel: kernel, colorMode: colorMode)
    }

    // MARK: - Blue Noise

    static func applyBlueNoise(to pixels: inout [PixelF], width: Int, height: Int, colorMode: DitherColorMode) {
        let levels = colorModeLevels(colorMode)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let threshold = blueNoiseTexture[(y % 64) * 64 + (x % 64)] - 0.5
                let p = pixels[i]
                if levels == 2 {
                    let lum = luminance(p)
                    let q: Float = (lum + threshold) > 0.5 ? 1 : 0
                    pixels[i].r = q
                    pixels[i].g = q
                    pixels[i].b = q
                } else {
                    pixels[i].r = quantize(p.r + threshold / Float(levels), levels: levels)
                    pixels[i].g = quantize(p.g + threshold / Float(levels), levels: levels)
                    pixels[i].b = quantize(p.b + threshold / Float(levels), levels: levels)
                }
            }
        }
    }

    // MARK: - Artistic Drip

    static func applyArtisticDrip(to pixels: inout [PixelF], width: Int, height: Int, colorMode: DitherColorMode) {
        // Custom kernel: pushes error downward for a "dripping" effect
        let w: Float = 1.0 / 8.0
        let kernel: DiffusionKernel = [
            (1, 0, w),           // right
            (-1, 1, -0.5 * w),   // below-left (negative = pull, creates edge artifacts)
            (0, 1, 3 * w),       // below (heavy)
            (1, 1, 3 * w),       // below-right (heavy)
            (0, 2, 2 * w),       // two below (drip continuation)
        ]
        applyErrorDiffusion(to: &pixels, width: width, height: height, kernel: kernel, colorMode: colorMode)
    }

    // MARK: - Color Mode Helpers

    /// Returns the number of quantization levels for the given color mode.
    static func colorModeLevels(_ mode: DitherColorMode) -> Int {
        switch mode {
        case .bw, .twoTone: return 2
        case .color(let levels): return max(2, min(8, levels))
        }
    }

    /// After dithering (which produces B&W or quantized values), map to the final colors.
    static func applyColorMapping(_ pixels: inout [PixelF], colorMode: DitherColorMode) {
        guard case .twoTone(let fg, let bg) = colorMode else { return }
        let fgColor = fg.cgColor.components ?? [0, 0, 0, 1]
        let bgColor = bg.cgColor.components ?? [1, 1, 1, 1]
        let fgR = Float(fgColor[0]), fgG = Float(fgColor[1]), fgB = Float(fgColor[2])
        let bgR = Float(bgColor[0]), bgG = Float(bgColor[1]), bgB = Float(bgColor[2])

        for i in pixels.indices {
            // After B&W dithering, r/g/b are all 0 or 1
            if pixels[i].r > 0.5 {
                pixels[i].r = fgR; pixels[i].g = fgG; pixels[i].b = fgB
            } else {
                pixels[i].r = bgR; pixels[i].g = bgG; pixels[i].b = bgB
            }
        }
    }

    // MARK: - Blue Noise Texture (64×64)

    /// Pre-computed 64×64 blue noise threshold texture, values in [0, 1].
    /// Generated via void-and-cluster algorithm. Tiles seamlessly.
    static let blueNoiseTexture: [Float] = {
        // Generate a deterministic blue noise pattern using a simple LDS (low-discrepancy sequence)
        // approach. For production quality you'd use a proper void-and-cluster generator,
        // but the R2 sequence produces excellent blue-noise-like properties.
        var texture = [Float](repeating: 0, count: 64 * 64)
        // R2 quasi-random sequence (generalized golden ratio in 2D)
        let g: Double = 1.32471795724  // plastic constant
        let a1 = 1.0 / g
        let a2 = 1.0 / (g * g)
        // Fill with R2 sequence values mapped to threshold positions
        for i in 0..<(64 * 64) {
            let x = Int((0.5 + a1 * Double(i)).truncatingRemainder(dividingBy: 1.0) * 64)
            let y = Int((0.5 + a2 * Double(i)).truncatingRemainder(dividingBy: 1.0) * 64)
            let idx = y * 64 + x
            if texture[idx] == 0 {
                texture[idx] = Float(i) / Float(64 * 64)
            }
        }
        // Fill any remaining zeros with interpolated values
        var val: Float = 0
        for i in texture.indices {
            if texture[i] == 0 {
                val += 0.0003
                texture[i] = val.truncatingRemainder(dividingBy: 1.0)
            }
        }
        return texture
    }()
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter DitherRendererTests 2>&1 | tail -30`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/DitherRenderer.swift Tests/FramerCoreTests/DitherRendererTests.swift
git commit -m "feat: add DitherRenderer with Bayer, Floyd-Steinberg, Atkinson, Blue Noise, Artistic Drip"
```

---

### Task 3: Add Remaining Algorithm Tests

**Files:**
- Modify: `Tests/FramerCoreTests/DitherRendererTests.swift`

**Step 1: Add tests for all algorithms**

Append to `DitherRendererTests`:

```swift
// MARK: - Floyd-Steinberg

func test_floydSteinberg_bw_producesOnlyBlackAndWhite() throws {
    let image = makeGradientImage()
    let params = DitherLayerParams(algorithm: .floydSteinberg, colorMode: .bw)
    let result = try DitherRenderer.apply(to: image, params: params)
    let pixels = extractPixels(from: result)
    for p in pixels {
        XCTAssertTrue(
            (p.r == 0 && p.g == 0 && p.b == 0) || (p.r == 255 && p.g == 255 && p.b == 255),
            "Found non-B&W pixel: \(p.r), \(p.g), \(p.b)"
        )
    }
}

// MARK: - Atkinson

func test_atkinson_bw_producesOnlyBlackAndWhite() throws {
    let image = makeGradientImage()
    let params = DitherLayerParams(algorithm: .atkinson, colorMode: .bw)
    let result = try DitherRenderer.apply(to: image, params: params)
    let pixels = extractPixels(from: result)
    for p in pixels {
        XCTAssertTrue(
            (p.r == 0 && p.g == 0 && p.b == 0) || (p.r == 255 && p.g == 255 && p.b == 255),
            "Found non-B&W pixel: \(p.r), \(p.g), \(p.b)"
        )
    }
}

// MARK: - Blue Noise

func test_blueNoise_bw_producesOnlyBlackAndWhite() throws {
    let image = makeGradientImage()
    let params = DitherLayerParams(algorithm: .blueNoise, colorMode: .bw)
    let result = try DitherRenderer.apply(to: image, params: params)
    let pixels = extractPixels(from: result)
    for p in pixels {
        XCTAssertTrue(
            (p.r == 0 && p.g == 0 && p.b == 0) || (p.r == 255 && p.g == 255 && p.b == 255),
            "Found non-B&W pixel: \(p.r), \(p.g), \(p.b)"
        )
    }
}

// MARK: - Artistic Drip

func test_artisticDrip_bw_producesOnlyBlackAndWhite() throws {
    let image = makeGradientImage()
    let params = DitherLayerParams(algorithm: .artisticDrip, colorMode: .bw)
    let result = try DitherRenderer.apply(to: image, params: params)
    let pixels = extractPixels(from: result)
    for p in pixels {
        XCTAssertTrue(
            (p.r == 0 && p.g == 0 && p.b == 0) || (p.r == 255 && p.g == 255 && p.b == 255),
            "Found non-B&W pixel: \(p.r), \(p.g), \(p.b)"
        )
    }
}

// MARK: - Cross-algorithm

func test_allAlgorithms_produceDifferentOutput() throws {
    let image = makeGradientImage()
    var outputs: [DitherAlgorithm: [UInt8]] = [:]
    for algo in DitherAlgorithm.allCases {
        let params = DitherLayerParams(algorithm: algo, colorMode: .bw, bayerLevel: 2, pixelScale: 1)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        outputs[algo] = pixels.map { $0.r }
    }
    // Each algorithm should produce unique output
    let algos = DitherAlgorithm.allCases
    for i in 0..<algos.count {
        for j in (i+1)..<algos.count {
            XCTAssertNotEqual(outputs[algos[i]], outputs[algos[j]],
                              "\(algos[i]) and \(algos[j]) produced identical output")
        }
    }
}
```

**Step 2: Run tests**

Run: `swift test --filter DitherRendererTests 2>&1 | tail -30`
Expected: All tests PASS.

**Step 3: Commit**

```bash
git add Tests/FramerCoreTests/DitherRendererTests.swift
git commit -m "test: add comprehensive tests for all dithering algorithms"
```

---

### Task 4: Wire DitherRenderer into BorderRenderer.applyLayers

**Files:**
- Modify: `Sources/FramerCore/Processing/BorderRenderer.swift` (~line 169, in the `switch layer` block)

**Step 1: Write the failing test**

Add to `Tests/FramerCoreTests/BorderRendererTests.swift`:

```swift
func test_applyLayers_ditherLayer_appliesDithering() throws {
    let image = makeTestImage()  // use existing helper from this test file
    let layers: [CompositionLayer] = [
        .dither(DitherLayerParams(algorithm: .atkinson, colorMode: .bw))
    ]
    let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
    XCTAssertEqual(result.image.width, image.width)
    XCTAssertEqual(result.image.height, image.height)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter BorderRendererTests/test_applyLayers_ditherLayer 2>&1 | tail -10`
Expected: FAIL — exhaustive switch doesn't handle `.dither`.

**Step 3: Add the case to BorderRenderer**

In `Sources/FramerCore/Processing/BorderRenderer.swift`, in the `switch layer` block inside `applyLayers`, add before the `case .caption` line:

```swift
case .dither(let params):
    current = try DitherRenderer.apply(to: current, params: params)
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter BorderRendererTests/test_applyLayers_ditherLayer 2>&1 | tail -10`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/FramerCore/Processing/BorderRenderer.swift Tests/FramerCoreTests/BorderRendererTests.swift
git commit -m "feat: wire DitherRenderer into BorderRenderer layer pipeline"
```

---

### Task 5: Add Dither Layer UI Controls

**Files:**
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`

**Step 1: Add the dither case to LayerRow**

In `LayerListSection.swift`, update three switch statements:

**In `layerControls`** (the `@ViewBuilder` computed property), add:
```swift
case .dither(let params):
    DitherLayerControls(params: params) { layer = .dither($0) }
```

**In `layerSummary`**, add:
```swift
case .dither(let p):
    return p.algorithm.label
```

**In `addLayerMenu`**, add a new button before the Divider:
```swift
Button {
    addLayer(.dither(DitherLayerParams()))
} label: {
    Label("Dither", systemImage: "circle.dotted")
}
```

**Step 2: Create the DitherLayerControls view**

Add at the bottom of `LayerListSection.swift` (or in a new section):

```swift
// MARK: - DitherLayerControls

struct DitherLayerControls: View {
    var params: DitherLayerParams
    var onChange: (DitherLayerParams) -> Void

    var body: some View {
        Picker("Algorithm", selection: algorithmBinding) {
            ForEach(DitherAlgorithm.allCases, id: \.self) { algo in
                Text(algo.label).tag(algo)
            }
        }

        colorModePicker

        // Bayer level (only for Bayer algorithm)
        if params.algorithm == .bayer {
            LabeledContent("Matrix Level") {
                HStack {
                    Stepper("\(params.bayerLevel)", value: bayerLevelBinding, in: 1...4)
                    Text("(\(Int(pow(2.0, Double(params.bayerLevel + 1))))×\(Int(pow(2.0, Double(params.bayerLevel + 1)))))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        // Pixel scale
        LabeledContent("Pixel Scale") {
            HStack {
                Stepper("\(params.pixelScale)×", value: pixelScaleBinding, in: 1...8)
            }
        }

        // Two-tone color pickers
        if case .twoTone = params.colorMode {
            twoToneControls
        }

        // Color levels stepper
        if case .color(let levels) = params.colorMode {
            LabeledContent("Levels") {
                Stepper("\(levels) per channel", value: colorLevelsBinding, in: 2...8)
            }
        }
    }

    private var colorModePicker: some View {
        Picker("Color Mode", selection: colorModeTagBinding) {
            Text("B&W").tag(0)
            Text("Two-Tone").tag(1)
            Text("Color").tag(2)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var twoToneControls: some View {
        if case .twoTone(let fg, let bg) = params.colorMode {
            ColorPickerWithHex("Foreground", selection: Binding(
                get: { Color(nsColor: NSColor(cgColor: fg.cgColor) ?? .black) },
                set: { newColor in
                    guard let hex = newColor.hexString, let c = try? CodableColor(hex: hex) else { return }
                    var p = params
                    if case .twoTone(_, let bg) = p.colorMode {
                        p.colorMode = .twoTone(foreground: c, background: bg)
                    }
                    onChange(p)
                }
            ))
            ColorPickerWithHex("Background", selection: Binding(
                get: { Color(nsColor: NSColor(cgColor: bg.cgColor) ?? .white) },
                set: { newColor in
                    guard let hex = newColor.hexString, let c = try? CodableColor(hex: hex) else { return }
                    var p = params
                    if case .twoTone(let fg, _) = p.colorMode {
                        p.colorMode = .twoTone(foreground: fg, background: c)
                    }
                    onChange(p)
                }
            ))
        }
    }

    // MARK: - Bindings

    private var algorithmBinding: Binding<DitherAlgorithm> {
        Binding(
            get: { params.algorithm },
            set: { var p = params; p.algorithm = $0; onChange(p) }
        )
    }

    private var bayerLevelBinding: Binding<Int> {
        Binding(
            get: { params.bayerLevel },
            set: { var p = params; p.bayerLevel = $0; onChange(p) }
        )
    }

    private var pixelScaleBinding: Binding<Int> {
        Binding(
            get: { params.pixelScale },
            set: { var p = params; p.pixelScale = $0; onChange(p) }
        )
    }

    private var colorModeTagBinding: Binding<Int> {
        Binding(
            get: {
                switch params.colorMode {
                case .bw: return 0
                case .twoTone: return 1
                case .color: return 2
                }
            },
            set: { tag in
                var p = params
                switch tag {
                case 0: p.colorMode = .bw
                case 1: p.colorMode = .twoTone(foreground: .black, background: .white)
                case 2: p.colorMode = .color(levels: 4)
                default: break
                }
                onChange(p)
            }
        )
    }

    private var colorLevelsBinding: Binding<Int> {
        Binding(
            get: {
                if case .color(let l) = params.colorMode { return l }
                return 4
            },
            set: { var p = params; p.colorMode = .color(levels: $0); onChange(p) }
        )
    }
}
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add Sources/FramerApp/Editor/LayerListSection.swift
git commit -m "feat: add dither layer UI controls with algorithm, color mode, and pixel scale"
```

---

### Task 6: Add YAML Config Support for Dither Layer

**Files:**
- Modify: `Sources/FramerCore/Config/YAMLConfig.swift` (or wherever YAML encoding/decoding handles layers)
- Test: `Tests/FramerCoreTests/ProcessingConfigTests.swift`

**Step 1: Write the failing test**

Add to `ProcessingConfigTests.swift`:

```swift
func test_yamlConfig_ditherLayer_roundtrips() throws {
    let config = ProcessingConfig(
        layers: [
            .dither(DitherLayerParams(algorithm: .atkinson, colorMode: .bw, bayerLevel: 2, pixelScale: 3))
        ]
    )
    let yaml = try YAMLConfig.encode(config)
    let decoded = try YAMLConfig.decode(yaml)
    XCTAssertEqual(decoded.layers?.count, 1)
    if case .dither(let params) = decoded.layers?.first {
        XCTAssertEqual(params.algorithm, .atkinson)
        XCTAssertEqual(params.pixelScale, 3)
    } else {
        XCTFail("Expected dither layer")
    }
}
```

**Step 2: Run test — it may already pass if YAML uses Codable. If not, update YAMLConfig.**

Run: `swift test --filter test_yamlConfig_ditherLayer_roundtrips 2>&1 | tail -10`

If it passes (YAML uses the same Codable path as JSON), commit directly. If it fails, check how `YAMLConfig` handles layer encoding and add the `"dither"` case.

**Step 3: Commit**

```bash
git add Tests/FramerCoreTests/ProcessingConfigTests.swift
git commit -m "test: verify dither layer roundtrips through YAML config"
```

---

### Task 7: Full Build + Test Validation

**Step 1: Run full build**

```bash
swift build 2>&1 | tail -10
```
Expected: Build complete with no errors.

**Step 2: Run full test suite**

```bash
swift test 2>&1 | tail -30
```
Expected: All tests pass (existing + new dither tests).

**Step 3: Regenerate Xcode project**

```bash
xcodegen generate
```

**Step 4: Commit if any generated files changed**

```bash
git add -A && git diff --cached --quiet || git commit -m "chore: regenerate Xcode project with dither layer"
```
