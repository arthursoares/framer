// Tests/FramerCoreTests/DitherCIFilterTests.swift
import XCTest
import CoreImage
import CoreGraphics
@testable import FramerCore

final class DitherCIFilterTests: XCTestCase {

    private let context = CIContext()
    private let exif = ExifData()

    // MARK: - Helpers

    /// Create a solid gray CIImage.
    private func makeSolidGray(width: Int, height: Int, gray: CGFloat = 0.5) -> CIImage {
        let color = CIColor(red: gray, green: gray, blue: gray, alpha: 1.0)
        return CIImage(color: color)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Create a solid gray CGImage for pixel inspection.
    private func makeSolidGrayCGImage(width: Int, height: Int, gray: UInt8) -> CGImage {
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

    /// Extract pixel values from a rendered CIImage.
    private func extractPixels(from ciImage: CIImage) -> [(r: UInt8, g: UInt8, b: UInt8)] {
        let extent = ciImage.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return [] }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return [] }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return [] }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var result: [(r: UInt8, g: UInt8, b: UInt8)] = []
        for i in 0..<(width * height) {
            let idx = i * 4
            result.append((pixels[idx], pixels[idx + 1], pixels[idx + 2]))
        }
        return result
    }

    // MARK: - DitherCIFilter Unit Tests

    func test_ditherFilter_preservesDimensions() {
        let input = makeSolidGray(width: 100, height: 80)
        let filter = DitherCIFilter()
        filter.inputImage = input
        filter.threshold = 0.5
        filter.bayerLevel = 2

        let output = filter.outputImage
        XCTAssertNotNil(output)
        let extent = output!.extent
        XCTAssertEqual(extent.width, 100, accuracy: 0.5)
        XCTAssertEqual(extent.height, 80, accuracy: 0.5)
    }

    func test_ditherFilter_producesRenderableOutput() {
        let input = makeSolidGray(width: 64, height: 64)
        let filter = DitherCIFilter()
        filter.inputImage = input
        filter.threshold = 0.5
        filter.bayerLevel = 2

        guard let output = filter.outputImage else {
            XCTFail("DitherCIFilter should produce output")
            return
        }
        let cgImage = context.createCGImage(output, from: output.extent)
        XCTAssertNotNil(cgImage, "Dithered output should be renderable")
    }

    func test_ditherFilter_solidGrayProducesNonUniformOutput() {
        // A mid-gray image dithered with Bayer should produce a mix of black and white pixels
        let input = makeSolidGray(width: 32, height: 32, gray: 0.5)
        let filter = DitherCIFilter()
        filter.inputImage = input
        filter.threshold = 0.5
        filter.bayerLevel = 2

        guard let output = filter.outputImage else {
            XCTFail("Should produce output")
            return
        }

        let pixels = extractPixels(from: output)
        XCTAssertFalse(pixels.isEmpty)

        // Count dark and light pixels
        var darkCount = 0
        var lightCount = 0
        for p in pixels {
            let lum = Int(p.r) + Int(p.g) + Int(p.b)
            if lum < 384 { // < 128 average per channel
                darkCount += 1
            } else {
                lightCount += 1
            }
        }

        // For a 50% gray, Bayer dithering should produce roughly equal dark and light
        XCTAssertGreaterThan(darkCount, 0, "Should have some dark pixels")
        XCTAssertGreaterThan(lightCount, 0, "Should have some light pixels")
    }

    func test_ditherFilter_nilInput_returnsNil() {
        let filter = DitherCIFilter()
        filter.inputImage = nil
        XCTAssertNil(filter.outputImage)
    }

    // MARK: - CIFilterPipeline Dither Integration

    func test_pipeline_ditherPreservesDimensions() {
        let input = makeSolidGray(width: 200, height: 150)
        let layers: [CompositionLayer] = [
            .dither(DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: 1))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = result.extent
        XCTAssertEqual(extent.width, 200, accuracy: 1.0)
        XCTAssertEqual(extent.height, 150, accuracy: 1.0)
    }

    func test_pipeline_ditherWithPixelScale() {
        let input = makeSolidGray(width: 200, height: 200)
        let layers: [CompositionLayer] = [
            .dither(DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 2, pixelScale: 2))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        // Should return to original dimensions after downscale + upscale
        let extent = result.extent
        XCTAssertEqual(extent.width, 200, accuracy: 2.0)
        XCTAssertEqual(extent.height, 200, accuracy: 2.0)

        // Verify renderable
        let cgImage = context.createCGImage(result, from: result.extent)
        XCTAssertNotNil(cgImage)
    }

    func test_pipeline_ditherProducesRenderableOutput() {
        let input = makeSolidGray(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .dither(DitherLayerParams(algorithm: .bayer, colorMode: .bw, bayerLevel: 1, pixelScale: 1))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let cgImage = context.createCGImage(result, from: result.extent)
        XCTAssertNotNil(cgImage, "Dithered pipeline output should be renderable")
    }

    // MARK: - CIFilterPipeline Overlay Integration

    func test_pipeline_overlayWithMissingTexture_passesThrough() {
        // When the overlay name doesn't resolve to a file, image should pass through unchanged
        let input = makeSolidGray(width: 200, height: 150)
        let layers: [CompositionLayer] = [
            .overlay(OverlayLayerParams(
                overlayName: "nonexistent_overlay_xyz",
                kind: .frame,
                blendMode: .screen,
                opacity: 100
            ))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = result.extent
        XCTAssertEqual(extent.width, 200, accuracy: 0.5)
        XCTAssertEqual(extent.height, 150, accuracy: 0.5)
    }

    // MARK: - Blend Helper Tests (via overlay pipeline)

    func test_pipeline_overlayBlendModes_allReturnImage() {
        // Verify each blend mode path doesn't crash, even with missing overlay
        let input = makeSolidGray(width: 100, height: 100)

        for mode in OverlayBlendMode.allCases {
            let layers: [CompositionLayer] = [
                .overlay(OverlayLayerParams(
                    overlayName: "missing_overlay",
                    kind: .frame,
                    blendMode: mode,
                    opacity: 50
                ))
            ]
            let result = CIFilterPipeline.apply(
                layers: layers,
                to: input,
                sourceImage: input,
                exif: exif
            )
            XCTAssertEqual(result.extent.width, 100, accuracy: 0.5,
                           "Blend mode \(mode.rawValue) should preserve width")
        }
    }
}
