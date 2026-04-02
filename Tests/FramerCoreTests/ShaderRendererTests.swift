// Tests/FramerCoreTests/ShaderRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class ShaderRendererTests: XCTestCase {
    func makeColorGridImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = UInt8((x * 13 + y * 7) % 256)
                let g = UInt8((x * 3 + y * 19) % 256)
                let b = UInt8((x * 11 + y * 5) % 256)
                data[idx] = r
                data[idx + 1] = g
                data[idx + 2] = b
                data[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    func uniqueColorCount(in image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var colors = Set<UInt32>()
        colors.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let idx = i * 4
            let packed = (UInt32(data[idx]) << 24)
                | (UInt32(data[idx + 1]) << 16)
                | (UInt32(data[idx + 2]) << 8)
                | UInt32(data[idx + 3])
            colors.insert(packed)
        }
        return colors.count
    }

    func test_asciiShader_preservesDimensions() throws {
        let image = makeColorGridImage(width: 37, height: 23)
        let params = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams())
        )

        let result = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_distantPastShader_reducesColorVariety() throws {
        let image = makeColorGridImage(width: 32, height: 32)
        let params = ShaderLayerParams(
            style: .distantPast,
            intensity: 1.0,
            params: .distantPast(DistantPastShaderParams(paletteDepth: 4, fade: 0.5, softness: 0.2, grain: 0.0))
        )

        let result = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
        XCTAssertLessThan(uniqueColorCount(in: result), uniqueColorCount(in: image))
    }
}
