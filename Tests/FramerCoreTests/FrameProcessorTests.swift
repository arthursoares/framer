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

    func test_previewImage_maxDimension_reasonable() async throws {
        let processor = FrameProcessor()
        let result = try await processor.previewImage(for: sampleURL, config: .default)
        let maxDim = max(result.size.width, result.size.height)
        // Source is downscaled to 1200px before pipeline; border/padding adds extra pixels.
        // Default config adds 20px border + 150px padding = 340px per axis total.
        // Final preview should be well under 2000px.
        XCTAssertLessThanOrEqual(maxDim, 2000)
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
}
