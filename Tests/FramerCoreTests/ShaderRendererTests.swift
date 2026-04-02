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

    func makeStripedGradientImage(width: Int, height: Int) -> CGImage {
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
                let span = max(1, min(24, width))
                let segment = x / span
                let localX = x % span
                let ramp = segment.isMultiple(of: 2) ? (span - 1 - localX) : localX
                let base = UInt8(max(0, min(255, Int((Double(ramp) / Double(max(1, span - 1))) * 255.0))))
                let contrast = ((segment + y) % 2 == 0) ? 72 : 224
                data[idx] = base
                data[idx + 1] = UInt8((Int(base) + contrast) / 2)
                data[idx + 2] = UInt8(max(0, min(255, contrast - Int(base) / 3)))
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


    func pixelData(for image: CGImage) -> [UInt8] {
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

        let count = width * height * 4
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: count)
        return Array(UnsafeBufferPointer(start: data, count: count))
    }

    func packedColorAt(_ image: CGImage, x: Int, y: Int) -> UInt32 {
        let pixels = pixelData(for: image)
        let idx = (y * image.width + x) * 4
        return (UInt32(pixels[idx]) << 24)
            | (UInt32(pixels[idx + 1]) << 16)
            | (UInt32(pixels[idx + 2]) << 8)
            | UInt32(pixels[idx + 3])
    }

    func luminanceValuesForRow(_ image: CGImage, y: Int, xRange: Range<Int>) -> [Double] {
        let pixels = pixelData(for: image)
        return xRange.map { x in
            let idx = (y * image.width + x) * 4
            let r = Double(pixels[idx])
            let g = Double(pixels[idx + 1])
            let b = Double(pixels[idx + 2])
            return (0.299 * r) + (0.587 * g) + (0.114 * b)
        }
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



    func test_asciiShader_quantizesIntoVisibleCells() throws {
        let image = makeColorGridImage(width: 24, height: 24)
        let params = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 6, edgeBias: 0.0, foreground: .white, background: .black, invert: false))
        )

        let result = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(packedColorAt(result, x: 1, y: 1), packedColorAt(result, x: 4, y: 4))
        XCTAssertEqual(packedColorAt(result, x: 7, y: 1), packedColorAt(result, x: 10, y: 4))

        var blockColors = Set<UInt32>()
        for y in stride(from: 1, to: result.height, by: 6) {
            for x in stride(from: 1, to: result.width, by: 6) {
                blockColors.insert(packedColorAt(result, x: x, y: y))
            }
        }
        XCTAssertGreaterThan(blockColors.count, 1)
    }

    func test_asciiShader_invertChangesOutput() throws {
        let image = makeColorGridImage(width: 24, height: 24)
        let normalParams = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 6, edgeBias: 0.3, foreground: .white, background: .black, invert: false))
        )
        let invertedParams = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 6, edgeBias: 0.3, foreground: .white, background: .black, invert: true))
        )

        let normal = try ShaderRenderer.apply(to: image, params: normalParams)
        let inverted = try ShaderRenderer.apply(to: image, params: invertedParams)

        XCTAssertNotEqual(pixelData(for: normal), pixelData(for: inverted))
    }

    func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height
        guard max(width, height) > maxDimension else { return image }

        let scale = Double(maxDimension) / Double(max(width, height))
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return ctx.makeImage()!
    }

    func test_asciiShader_previewDimensionMatchesPreviewSampling() throws {
        let image = makeColorGridImage(width: 64, height: 64)
        let params = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 4, edgeBias: 0.4, foreground: .white, background: .black, invert: false))
        )

        let previewInput = downscale(image, maxDimension: 32)
        let previewOutput = try ShaderRenderer.apply(to: previewInput, params: params)
        let exportOutput = try ShaderRenderer.apply(to: image, params: params, previewBaseDimension: 32)

        for previewY in stride(from: 2, to: previewOutput.height, by: 4) {
            for previewX in stride(from: 2, to: previewOutput.width, by: 4) {
                let exportX = min(exportOutput.width - 1, previewX * 2)
                let exportY = min(exportOutput.height - 1, previewY * 2)
                XCTAssertEqual(
                    packedColorAt(previewOutput, x: previewX, y: previewY),
                    packedColorAt(exportOutput, x: exportX, y: exportY)
                )
            }
        }
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

    func test_pixelSortShader_reordersPixelsAboveThreshold() throws {
        let image = makeStripedGradientImage(width: 192, height: 96)
        let params = ShaderLayerParams(
            style: .pixelSort,
            intensity: 1.0,
            params: .pixelSort(PixelSortShaderParams(threshold: 0.1, direction: .horizontal, span: 24, amount: 1.0))
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let originalLuminance = luminanceValuesForRow(image, y: 24, xRange: 0..<24)
        let sortedLuminance = luminanceValuesForRow(output, y: 24, xRange: 0..<24)

        XCTAssertNotEqual(sortedLuminance, originalLuminance)
        XCTAssertEqual(sortedLuminance, sortedLuminance.sorted())
    }

    func test_pixelSortAmountZeroMatchesOriginal() throws {
        let image = makeStripedGradientImage(width: 128, height: 128)
        let params = ShaderLayerParams(
            style: .pixelSort,
            intensity: 1.0,
            params: .pixelSort(PixelSortShaderParams(amount: 0.0))
        )

        let output = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(pixelData(for: output), pixelData(for: image))
    }
}
