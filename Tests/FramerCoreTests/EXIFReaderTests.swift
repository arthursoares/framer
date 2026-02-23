// Tests/FramerCoreTests/EXIFReaderTests.swift
import XCTest
@testable import FramerCore

final class EXIFReaderTests: XCTestCase {
    var sampleURL: URL {
        Bundle.module.url(forResource: "sample", withExtension: "jpg", subdirectory: "Resources")!
    }

    func test_readExif_returnsData() throws {
        let exif = try EXIFReader.read(from: sampleURL)
        // sample.jpg should have some EXIF — at minimum dateTime or camera
        XCTAssertNotNil(exif)
    }

    func test_readExif_nonexistentFile_throws() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        XCTAssertThrowsError(try EXIFReader.read(from: url))
    }
}
