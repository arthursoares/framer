// Tests/FramerCoreTests/DitherRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class DitherRendererTests: XCTestCase {

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

    // MARK: - All Algorithms Produce Different Output

    func test_allAlgorithms_produceDifferentOutput() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let algorithms: [DitherAlgorithm] = [.bayer, .floydSteinberg, .atkinson, .blueNoise, .artisticDrip]

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
