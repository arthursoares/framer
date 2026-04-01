// Tests/FramerCoreTests/LUTRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class LUTRendererTests: XCTestCase {

    // MARK: - Test Helpers

    func makeSolidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
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
            data[idx] = r
            data[idx + 1] = g
            data[idx + 2] = b
            data[idx + 3] = 255
        }
        return ctx.makeImage()!
    }

    func makeGradientImage(width: Int, height: Int) -> CGImage {
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
                data[idx] = UInt8(Double(x) / Double(width - 1) * 255.0)
                data[idx + 1] = UInt8(Double(y) / Double(height - 1) * 255.0)
                data[idx + 2] = 128
                data[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

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

    func makeIdentityLUT(size: Int) -> LUT3D {
        var data = [Float]()
        data.reserveCapacity(size * size * size * 3)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    data.append(Float(r) / Float(size - 1))
                    data.append(Float(g) / Float(size - 1))
                    data.append(Float(b) / Float(size - 1))
                }
            }
        }
        return LUT3D(size: size, data: data)
    }

    // MARK: - Identity LUT Tests

    func test_lutRenderer_identity() throws {
        let image = makeGradientImage(width: 32, height: 32)
        let lut = makeIdentityLUT(size: 33)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0)
        let originalPixels = extractPixels(from: image)
        let resultPixels = extractPixels(from: result)

        XCTAssertEqual(originalPixels.count, resultPixels.count)
        for (orig, res) in zip(originalPixels, resultPixels) {
            XCTAssertEqual(res.r, orig.r, accuracy: 1, "R channel should be preserved")
            XCTAssertEqual(res.g, orig.g, accuracy: 1, "G channel should be preserved")
            XCTAssertEqual(res.b, orig.b, accuracy: 1, "B channel should be preserved")
        }
    }

    func test_lutRenderer_intensity0_returnsOriginal() throws {
        let image = makeGradientImage(width: 32, height: 32)
        let lut = makeIdentityLUT(size: 33)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 0.0)
        let originalPixels = extractPixels(from: image)
        let resultPixels = extractPixels(from: result)

        XCTAssertEqual(originalPixels.count, resultPixels.count)
        for (orig, res) in zip(originalPixels, resultPixels) {
            XCTAssertEqual(res.r, orig.r, accuracy: 1)
            XCTAssertEqual(res.g, orig.g, accuracy: 1)
            XCTAssertEqual(res.b, orig.b, accuracy: 1)
        }
    }

    func test_lutRenderer_intensity1_fullApply() throws {
        let image = makeSolidImage(width: 32, height: 32, r: 128, g: 64, b: 32)
        let lut = makeIdentityLUT(size: 33)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0)
        let resultPixels = extractPixels(from: result)

        for pixel in resultPixels {
            XCTAssertEqual(pixel.r, 128, accuracy: 1)
            XCTAssertEqual(pixel.g, 64, accuracy: 1)
            XCTAssertEqual(pixel.b, 32, accuracy: 1)
        }
    }

    func test_lutRenderer_solidColorApply() throws {
        let image = makeSolidImage(width: 32, height: 32, r: 200, g: 100, b: 50)
        let lut = makeIdentityLUT(size: 33)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0)
        let resultPixels = extractPixels(from: result)

        for pixel in resultPixels {
            XCTAssertEqual(pixel.r, 200, accuracy: 1)
            XCTAssertEqual(pixel.g, 100, accuracy: 1)
            XCTAssertEqual(pixel.b, 50, accuracy: 1)
        }
    }

    // MARK: - Preview Dimension Tests

    func test_lutRenderer_previewDimension_scalesDown() throws {
        let image = makeGradientImage(width: 64, height: 64)
        let lut = makeIdentityLUT(size: 33)

        let resultFull = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0)
        let resultPreview = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0, previewBaseDimension: 32)

        XCTAssertEqual(resultFull.width, 64)
        XCTAssertEqual(resultFull.height, 64)
        XCTAssertEqual(resultPreview.width, 64)
        XCTAssertEqual(resultPreview.height, 64)
    }

    // MARK: - Intensity Blend Tests

    func test_lutRenderer_intensityHalf() throws {
        let image = makeSolidImage(width: 8, height: 8, r: 128, g: 128, b: 128)
        let lut = makeIdentityLUT(size: 33)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 0.5)
        let resultPixels = extractPixels(from: result)

        for pixel in resultPixels {
            XCTAssertEqual(pixel.r, 128, accuracy: 1)
            XCTAssertEqual(pixel.g, 128, accuracy: 1)
            XCTAssertEqual(pixel.b, 128, accuracy: 1)
        }
    }

    // MARK: - Edge Cases

    func test_lutRenderer_smallImage() throws {
        let image = makeSolidImage(width: 1, height: 1, r: 100, g: 150, b: 200)
        let lut = makeIdentityLUT(size: 2)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0)
        let resultPixels = extractPixels(from: result)

        XCTAssertEqual(resultPixels.count, 1)
        XCTAssertEqual(resultPixels[0].r, 100, accuracy: 1)
        XCTAssertEqual(resultPixels[0].g, 150, accuracy: 1)
        XCTAssertEqual(resultPixels[0].b, 200, accuracy: 1)
    }

    func test_lutRenderer_33sizeLUT() throws {
        let image = makeGradientImage(width: 16, height: 16)
        let lut = makeIdentityLUT(size: 33)

        let result = try LUTRenderer.apply(to: image, lut: lut, intensity: 1.0)
        let originalPixels = extractPixels(from: image)
        let resultPixels = extractPixels(from: result)

        XCTAssertEqual(originalPixels.count, resultPixels.count)
        for (orig, res) in zip(originalPixels, resultPixels) {
            XCTAssertEqual(res.r, orig.r, accuracy: 2)
            XCTAssertEqual(res.g, orig.g, accuracy: 2)
            XCTAssertEqual(res.b, orig.b, accuracy: 2)
        }
    }
}
