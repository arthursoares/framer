import XCTest
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
}
