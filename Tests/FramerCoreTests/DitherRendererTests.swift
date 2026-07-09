// Tests/FramerCoreTests/DitherRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class DitherRendererTests: XCTestCase {
    // The dither path is GPU-only since the CPU implementations were retired
    // (docs/adr/2026-07-09-retire-cpu-effect-path.md) — without Metal every
    // non-Riemersma render here would throw MetalEffectError. Riemersma's
    // Metal-less coverage lives in EffectGPUBehaviorTests, which runs its
    // routing test on any host.
    override func setUpWithError() throws {
        guard MetalEffectLibrary.shared != nil else {
            throw XCTSkip("Metal device unavailable on this host (likely CI sandbox).")
        }
    }

    // MARK: - Test Helpers

    /// Create a horizontal black-to-white gradient image.
    func makeGradientImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        // Draw horizontal gradient manually
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let val = UInt8(Double(x) / Double(width - 1) * 255.0)
                data[idx] = val     // R
                data[idx + 1] = val // G
                data[idx + 2] = val // B
                data[idx + 3] = 255 // A
            }
        }
        return ctx.makeImage()!
    }

    /// Create a solid gray image.
    func makeSolidImage(width: Int, height: Int, gray: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let idx = i * 4
            data[idx] = gray
            data[idx + 1] = gray
            data[idx + 2] = gray
            data[idx + 3] = 255
        }
        return ctx.makeImage()!
    }

    /// Create a checkerboard image with alternating light/dark blocks.
    func makeCheckerboardImage(width: Int, height: Int, blockSize: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let isLight = ((x / blockSize) + (y / blockSize)) % 2 == 0
                let val: UInt8 = isLight ? 200 : 50
                data[idx] = val
                data[idx + 1] = val
                data[idx + 2] = val
                data[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    /// Extract pixels from a CGImage as an array of (r, g, b) tuples.
    func extractPixels(from image: CGImage) -> [(r: UInt8, g: UInt8, b: UInt8)] {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var result = [(r: UInt8, g: UInt8, b: UInt8)]()
        result.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let idx = i * 4
            result.append((r: data[idx], g: data[idx + 1], b: data[idx + 2]))
        }
        return result
    }

    // MARK: - B&W Algorithm Tests

    func test_bayer_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Bayer B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_floydSteinberg_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .floydSteinberg, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Floyd-Steinberg B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_atkinson_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .atkinson, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Atkinson B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_blueNoise_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .blueNoise, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Blue Noise B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_artisticDrip_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .artisticDrip, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Artistic Drip B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    // MARK: - Two-Tone Tests

    func test_twoTone_producesOnlySpecifiedColors() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let fg = try CodableColor(hex: "#FF0000")
        let bg = try CodableColor(hex: "#0000FF")
        let params = DitherLayerParams(
            algorithm: .atkinson,
            colorMode: .twoTone(foreground: fg, background: bg)
        )
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            let isForeground = pixel.r == 255 && pixel.g == 0 && pixel.b == 0
            let isBackground = pixel.r == 0 && pixel.g == 0 && pixel.b == 255
            XCTAssertTrue(isForeground || isBackground,
                          "Two-tone should only produce fg or bg colors, got (\(pixel.r), \(pixel.g), \(pixel.b))")
        }
    }

    // MARK: - Color Mode Tests

    func test_colorMode_respectsLevelCount() throws {
        let image = makeGradientImage(width: 128, height: 32)
        let levels = 3
        let params = DitherLayerParams(
            algorithm: .bayer,
            colorMode: .color(levels: levels),
            bayerLevel: 2
        )
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)

        // Collect unique values per channel
        var uniqueR = Set<UInt8>()
        var uniqueG = Set<UInt8>()
        var uniqueB = Set<UInt8>()
        for pixel in pixels {
            uniqueR.insert(pixel.r)
            uniqueG.insert(pixel.g)
            uniqueB.insert(pixel.b)
        }

        XCTAssertLessThanOrEqual(uniqueR.count, levels,
            "Red channel should have at most \(levels) unique values, got \(uniqueR.count): \(uniqueR.sorted())")
        XCTAssertLessThanOrEqual(uniqueG.count, levels,
            "Green channel should have at most \(levels) unique values, got \(uniqueG.count): \(uniqueG.sorted())")
        XCTAssertLessThanOrEqual(uniqueB.count, levels,
            "Blue channel should have at most \(levels) unique values, got \(uniqueB.count): \(uniqueB.sorted())")
    }

    // MARK: - Bayer Level Tests

    func test_differentBayerLevels_produceDifferentOutput() throws {
        let image = makeGradientImage(width: 64, height: 64)

        let params1 = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 1)
        let params2 = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 3)

        let result1 = try DitherRenderer.apply(to: image, params: params1)
        let result2 = try DitherRenderer.apply(to: image, params: params2)

        let pixels1 = extractPixels(from: result1)
        let pixels2 = extractPixels(from: result2)

        var differenceCount = 0
        for i in 0..<pixels1.count {
            if pixels1[i].r != pixels2[i].r { differenceCount += 1 }
        }

        XCTAssertGreaterThan(differenceCount, 0,
            "Different Bayer levels should produce different output")
    }

    // MARK: - Gamma Correction Test

    func test_gammaCorrection_midGrayDithersToApproxHalfWhite() throws {
        // sRGB 186/255 ≈ 0.5 in linear space
        // (0.729)^2.4 ≈ 0.5 for sRGB gamma
        let image = makeSolidImage(width: 128, height: 128, gray: 186)
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)

        let whiteCount = pixels.filter { $0.r == 255 }.count
        let totalCount = pixels.count
        let whiteRatio = Double(whiteCount) / Double(totalCount)

        // Should be approximately 50% white (±10%)
        XCTAssertGreaterThan(whiteRatio, 0.40,
            "sRGB 186 (~0.5 linear) should dither to ~50% white, got \(whiteRatio * 100)%")
        XCTAssertLessThan(whiteRatio, 0.60,
            "sRGB 186 (~0.5 linear) should dither to ~50% white, got \(whiteRatio * 100)%")
    }

    // MARK: - Pixel Scale Tests

    func test_pixelScale_preservesDimensions() throws {
        let image = makeGradientImage(width: 128, height: 128)
        let params = DitherLayerParams(algorithm: .atkinson, colorMode: .bw, pixelScale: 4)
        let result = try DitherRenderer.apply(to: image, params: params)

        XCTAssertEqual(result.width, 128, "Pixel scale should preserve original width")
        XCTAssertEqual(result.height, 128, "Pixel scale should preserve original height")
    }

    func test_pixelScale_producesBlockyOutput() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let scale = 4
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: scale)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)

        // Check that NxN blocks have identical values
        var blockConsistentCount = 0
        var totalBlocks = 0
        let width = result.width

        for by in stride(from: 0, to: result.height, by: scale) {
            for bx in stride(from: 0, to: width, by: scale) {
                totalBlocks += 1
                let refPixel = pixels[by * width + bx]
                var allSame = true
                for dy in 0..<min(scale, result.height - by) {
                    for dx in 0..<min(scale, width - bx) {
                        let p = pixels[(by + dy) * width + (bx + dx)]
                        if p.r != refPixel.r || p.g != refPixel.g || p.b != refPixel.b {
                            allSame = false
                        }
                    }
                }
                if allSame { blockConsistentCount += 1 }
            }
        }

        let consistency = Double(blockConsistentCount) / Double(totalBlocks)
        XCTAssertGreaterThan(consistency, 0.95,
            "Pixel scale \(scale) should produce >95% consistent NxN blocks, got \(consistency * 100)%")
    }

    // MARK: - Threshold Tests

    func test_threshold_clampsInInit() {
        let paramsLow = DitherLayerParams(threshold: 0.0)
        XCTAssertEqual(paramsLow.threshold, 0.1, "Threshold below 0.1 should be clamped to 0.1")

        let paramsHigh = DitherLayerParams(threshold: 1.0)
        XCTAssertEqual(paramsHigh.threshold, 0.9, "Threshold above 0.9 should be clamped to 0.9")

        let paramsNormal = DitherLayerParams(threshold: 0.3)
        XCTAssertEqual(paramsNormal.threshold, 0.3, accuracy: 0.001)
    }

    func test_threshold_defaultIsHalf() {
        let params = DitherLayerParams()
        XCTAssertEqual(params.threshold, 0.5, accuracy: 0.001)
    }

    func test_threshold_higherProducesBrighterOutput() throws {
        let image = makeSolidImage(width: 64, height: 64, gray: 128)

        let paramsBright = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, threshold: 0.8)
        let paramsDark = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, threshold: 0.2)

        let resultBright = try DitherRenderer.apply(to: image, params: paramsBright)
        let resultDark = try DitherRenderer.apply(to: image, params: paramsDark)

        let whiteBright = extractPixels(from: resultBright).filter { $0.r == 255 }.count
        let whiteDark = extractPixels(from: resultDark).filter { $0.r == 255 }.count

        XCTAssertGreaterThan(whiteBright, whiteDark,
            "Higher threshold should produce more white pixels (brighter), got bright=\(whiteBright) dark=\(whiteDark)")
    }

    func test_threshold_worksWithColorMode() throws {
        let image = makeSolidImage(width: 64, height: 64, gray: 128)

        let paramsBright = DitherLayerParams(algorithm: .bayer, colorMode: .color(levels: 2), bayerLevel: 2, threshold: 0.8)
        let paramsDark = DitherLayerParams(algorithm: .bayer, colorMode: .color(levels: 2), bayerLevel: 2, threshold: 0.2)

        let resultBright = try DitherRenderer.apply(to: image, params: paramsBright)
        let resultDark = try DitherRenderer.apply(to: image, params: paramsDark)

        let avgBright = extractPixels(from: resultBright).map { Int($0.r) }.reduce(0, +)
        let avgDark = extractPixels(from: resultDark).map { Int($0.r) }.reduce(0, +)

        XCTAssertGreaterThan(avgBright, avgDark,
            "Higher threshold should produce brighter color output, got bright=\(avgBright) dark=\(avgDark)")
    }

    func test_threshold_yamlRoundtrip() throws {
        var config = ProcessingConfig.default
        config.layers = [
            .dither(DitherLayerParams(algorithm: .atkinson, threshold: 0.3))
        ]

        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)

        guard let layers = decoded.layers, let layer = layers.first,
              case .dither(let params) = layer else {
            XCTFail("Expected dither layer after YAML round-trip")
            return
        }
        XCTAssertEqual(params.threshold, 0.3, accuracy: 0.001)
    }

    func test_threshold_yamlDefaultWhenMissing() throws {
        // YAML without dither_threshold should default to 0.5
        let yaml = """
        layers:
        - type: dither
          algorithm: bayer
          bayer_level: 2
          pixel_scale: 1
          color_mode: bw
        """
        let config = try YAMLConfig.decode(yaml)
        guard let layers = config.layers, let layer = layers.first,
              case .dither(let params) = layer else {
            XCTFail("Expected dither layer")
            return
        }
        XCTAssertEqual(params.threshold, 0.5, accuracy: 0.001)
    }

    // MARK: - New Algorithm Tests

    func test_halftone_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .halftone, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Halftone B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_stucki_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .stucki, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Stucki B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_whiteNoise_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .whiteNoise, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "White Noise B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_riemersma_bw_producesOnlyBlackWhite() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .riemersma, colorMode: .bw)
        let result = try DitherRenderer.apply(to: image, params: params)
        let pixels = extractPixels(from: result)
        for pixel in pixels {
            XCTAssertTrue(pixel.r == 0 || pixel.r == 255, "Riemersma B&W should produce only 0 or 255, got \(pixel.r)")
            XCTAssertEqual(pixel.r, pixel.g)
            XCTAssertEqual(pixel.g, pixel.b)
        }
    }

    func test_whiteNoise_isDeterministic() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .whiteNoise, colorMode: .bw)
        let result1 = try DitherRenderer.apply(to: image, params: params)
        let result2 = try DitherRenderer.apply(to: image, params: params)
        let pixels1 = extractPixels(from: result1)
        let pixels2 = extractPixels(from: result2)
        for i in 0..<pixels1.count {
            XCTAssertEqual(pixels1[i].r, pixels2[i].r, "White noise should be deterministic (seeded)")
        }
    }

    // MARK: - Pre-Processing Tests

    func test_sharpen_clampsInInit() {
        let low = DitherLayerParams(sharpen: -1)
        XCTAssertEqual(low.sharpen, 0)
        let high = DitherLayerParams(sharpen: 2)
        XCTAssertEqual(high.sharpen, 1)
    }

    func test_contrast_clampsInInit() {
        let low = DitherLayerParams(contrast: -1)
        XCTAssertEqual(low.contrast, 0)
        let high = DitherLayerParams(contrast: 2)
        XCTAssertEqual(high.contrast, 1)
    }

    func test_sharpen_changesOutput() throws {
        // Use a checkerboard pattern so unsharp mask has edges to enhance
        let image = makeCheckerboardImage(width: 64, height: 64, blockSize: 4)
        let paramsOff = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, sharpen: 0)
        let paramsOn = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, sharpen: 1)
        let resultOff = try DitherRenderer.apply(to: image, params: paramsOff)
        let resultOn = try DitherRenderer.apply(to: image, params: paramsOn)
        let pixelsOff = extractPixels(from: resultOff)
        let pixelsOn = extractPixels(from: resultOn)
        var diffs = 0
        for i in 0..<pixelsOff.count {
            if pixelsOff[i].r != pixelsOn[i].r { diffs += 1 }
        }
        XCTAssertGreaterThan(diffs, 0, "Sharpen should produce different output on high-contrast edges")
    }

    func test_contrast_changesOutput() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let paramsOff = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, contrast: 0)
        let paramsOn = DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, contrast: 1)
        let resultOff = try DitherRenderer.apply(to: image, params: paramsOff)
        let resultOn = try DitherRenderer.apply(to: image, params: paramsOn)
        let pixelsOff = extractPixels(from: resultOff)
        let pixelsOn = extractPixels(from: resultOn)
        var diffs = 0
        for i in 0..<pixelsOff.count {
            if pixelsOff[i].r != pixelsOn[i].r { diffs += 1 }
        }
        XCTAssertGreaterThan(diffs, 0, "Contrast should produce different output")
    }

    // MARK: - All Algorithms Produce Different Output

    func test_allAlgorithms_produceDifferentOutput() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let algorithms: [DitherAlgorithm] = DitherAlgorithm.allCases

        var results = [DitherAlgorithm: [UInt8]]()

        for algo in algorithms {
            let params = DitherLayerParams(algorithm: algo, colorMode: .bw, bayerLevel: 2)
            let result = try DitherRenderer.apply(to: image, params: params)
            let pixels = extractPixels(from: result)
            results[algo] = pixels.map { $0.r }
        }

        // Compare every pair
        for i in 0..<algorithms.count {
            for j in (i + 1)..<algorithms.count {
                let a = algorithms[i]
                let b = algorithms[j]
                let rA = results[a]!
                let rB = results[b]!

                var differences = 0
                for k in 0..<rA.count {
                    if rA[k] != rB[k] { differences += 1 }
                }

                XCTAssertGreaterThan(differences, 0,
                    "\(a.label) and \(b.label) should produce different output")
            }
        }
    }
}
