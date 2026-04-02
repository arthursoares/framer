import XCTest
import ImageIO
@testable import FramerCore

final class FrameProcessorTests: XCTestCase {
    var sampleURL: URL {
        Bundle.module.url(forResource: "sample", withExtension: "jpg", subdirectory: "Resources")!
    }

    func test_previewCGImage_returnsCGImage() async throws {
        let processor = FrameProcessor()
        let result = try await processor.previewCGImage(for: sampleURL, config: .default)
        XCTAssertGreaterThan(result.width, 0)
        XCTAssertGreaterThan(result.height, 0)
    }

    func test_previewCGImage_maxDimension_reasonable() async throws {
        let processor = FrameProcessor()
        let result = try await processor.previewCGImage(for: sampleURL, config: .default)
        let maxDim = max(result.width, result.height)
        // previewMaxDimension() simulates the full layer stack (border + padding additions)
        // to compute the downscale target, so the final preview can be up to 3500px.
        XCTAssertLessThanOrEqual(maxDim, 4000)
        // But also should be larger than a tiny thumbnail
        XCTAssertGreaterThan(maxDim, 500)
    }

    func test_processToFile_createsOutputFile() async throws {
        let processor = FrameProcessor()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer_test_\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await processor.process(input: sampleURL, output: outputURL, config: .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_processToFile_pngFormat() async throws {
        let processor = FrameProcessor()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var config = ProcessingConfig.default
        config.outputFormat = .png
        try await processor.process(input: sampleURL, output: outputURL, config: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_previewCGImage_customMaxDimensionProducesSmallerResult() async throws {
        let processor = FrameProcessor()
        let full = try await processor.previewCGImage(for: sampleURL, config: .default)
        let compact = try await processor.previewCGImage(for: sampleURL, config: .default, maxDimension: 320)

        XCTAssertLessThan(max(compact.width, compact.height), max(full.width, full.height))
    }

    func loadCGImage(from url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            XCTFail("Failed to load image at \(url.path)")
            throw FramerError.invalidImage(url)
        }
        return image
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

    func imageDifference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        let left = pixelData(for: lhs)
        let right = pixelData(for: rhs)
        XCTAssertEqual(left.count, right.count)

        var total = 0.0
        for idx in 0..<left.count {
            total += abs(Double(left[idx]) - Double(right[idx])) / 255.0
        }
        return total / Double(left.count)
    }

    func downscaleLikeFrameProcessor(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height
        guard max(width, height) > maxDimension else { return image }

        let scale = Double(maxDimension) / Double(max(width, height))
        let newWidth = Int(Double(width) * scale)
        let newHeight = Int(Double(height) * scale)
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

    func test_previewCGImage_shaderLayer_matchesExportShape() async throws {
        let processor = FrameProcessor()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer_shader_parity_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var config = ProcessingConfig.default
        config.outputFormat = .png
        config.layers = [
            .shader(
                ShaderLayerParams(
                    style: .crimewave,
                    intensity: 1.0,
                    params: .crimewave(CrimewaveShaderParams())
                )
            )
        ]

        let preview = try await processor.previewCGImage(for: sampleURL, config: config, maxDimension: 320)
        try await processor.process(input: sampleURL, output: outputURL, config: config)
        let exportedFull = try loadCGImage(from: outputURL)
        let exported = downscaleLikeFrameProcessor(exportedFull, maxDimension: 320)

        XCTAssertEqual(preview.width, exported.width)
        XCTAssertEqual(preview.height, exported.height)
        XCTAssertLessThan(imageDifference(preview, exported), 0.08)
    }
}
