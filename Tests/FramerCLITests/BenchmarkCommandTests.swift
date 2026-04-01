import XCTest
@testable import FramerCLI

final class BenchmarkCommandTests: XCTestCase {
    func test_benchmarkLUTCommand_parsesRequiredOptions() throws {
        let command = try BenchmarkCommand.LUT.parse([
            "--input", "/tmp/image.jpg",
            "--lut", "/tmp/look.cube"
        ])

        XCTAssertEqual(command.input, "/tmp/image.jpg")
        XCTAssertEqual(command.lut, "/tmp/look.cube")
        XCTAssertEqual(command.iterations, 10)
        XCTAssertEqual(command.intensity, 1.0)
        XCTAssertNil(command.previewBase)
    }
}
