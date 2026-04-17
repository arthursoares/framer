import XCTest

final class FramerCLIE2ETests: XCTestCase {
    func test_process_singleImage_writesExpectedJPEG() throws {
        let outputDir = try E2ETestSupport.makeTemporaryDirectory(named: "single-export")
        let input = E2ETestSupport.fixturesRoot.appendingPathComponent("input/sample-1.jpg")
        let output = outputDir.appendingPathComponent("sample-1_solid.jpg")
        let manifestURL = E2ETestSupport.fixturesRoot.appendingPathComponent("manifests/single-export.json")
        let manifest = try JSONDecoder().decode(SingleExportManifest.self, from: Data(contentsOf: manifestURL))

        let process = Process()
        process.executableURL = E2ETestSupport.builtCLI
        process.arguments = [
            "process",
            "--input", input.path,
            "--output-file", output.path,
            "--border-style", "solid",
        ]

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output.lastPathComponent, manifest.outputFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))

        let size = try E2ETestSupport.imageSize(at: output)
        XCTAssertEqual(Int(size.width), manifest.expectedWidth)
        XCTAssertEqual(Int(size.height), manifest.expectedHeight)
    }

    func test_process_directory_writesExpectedBatchOutputs() throws {
        let outputDir = try E2ETestSupport.makeTemporaryDirectory(named: "batch-export")
        let inputDir = E2ETestSupport.fixturesRoot.appendingPathComponent("input")

        let process = Process()
        process.executableURL = E2ETestSupport.builtCLI
        process.arguments = [
            "process",
            "--input", inputDir.path,
            "--output", outputDir.path,
            "--border-style", "instagram",
            "--workers", "1",
        ]

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("sample-1_instagram.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("sample-2_instagram.jpg").path))
    }

    func test_process_singleImage_noMetadataRemovesExifPayload() throws {
        let outputDir = try E2ETestSupport.makeTemporaryDirectory(named: "metadata-strip")
        let input = E2ETestSupport.fixturesRoot.appendingPathComponent("input/sample-1.jpg")
        let output = outputDir.appendingPathComponent("sample-1_solid.jpg")

        let process = Process()
        process.executableURL = E2ETestSupport.builtCLI
        process.arguments = [
            "process",
            "--input", input.path,
            "--output-file", output.path,
            "--border-style", "solid",
            "--no-metadata",
        ]

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertFalse(try E2ETestSupport.hasExifDate(at: output))
    }
}
