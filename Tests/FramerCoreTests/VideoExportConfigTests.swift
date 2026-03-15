import XCTest
@testable import FramerCore

final class VideoExportConfigTests: XCTestCase {

    // MARK: - VideoCodec Tests

    func testVideoCodecRawValues() {
        XCTAssertEqual(VideoCodec.h264.rawValue, "h264")
        XCTAssertEqual(VideoCodec.h265.rawValue, "h265")
    }

    func testVideoCodecCodableRoundtrip() throws {
        for codec in VideoCodec.allCases {
            let data = try JSONEncoder().encode(codec)
            let decoded = try JSONDecoder().decode(VideoCodec.self, from: data)
            XCTAssertEqual(decoded, codec)
        }
    }

    func testVideoCodecDecodesFromRawString() throws {
        let json = "\"h265\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VideoCodec.self, from: data)
        XCTAssertEqual(decoded, .h265)
    }

    // MARK: - TrimRange Tests

    func testTrimRangeValidInit() throws {
        let range = try TrimRange(start: 1.0, end: 5.0)
        XCTAssertEqual(range.start, 1.0)
        XCTAssertEqual(range.end, 5.0)
    }

    func testTrimRangeStartAfterEndThrows() {
        XCTAssertThrowsError(try TrimRange(start: 10.0, end: 5.0)) { error in
            guard case FramerError.invalidTrimRange(let msg) = error else {
                XCTFail("Expected FramerError.invalidTrimRange, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("before"))
        }
    }

    func testTrimRangeStartEqualsEndThrows() {
        XCTAssertThrowsError(try TrimRange(start: 5.0, end: 5.0)) { error in
            guard case FramerError.invalidTrimRange = error else {
                XCTFail("Expected FramerError.invalidTrimRange, got \(error)")
                return
            }
        }
    }

    func testTrimRangeFromTimecodeValid() throws {
        let range = try TrimRange(from: "00:01:30.000-00:02:00.500")
        XCTAssertEqual(range.start, 90.0, accuracy: 0.001)
        XCTAssertEqual(range.end, 120.5, accuracy: 0.001)
    }

    func testTrimRangeFromTimecodeHoursMinutesSeconds() throws {
        let range = try TrimRange(from: "01:00:00.000-02:30:15.750")
        XCTAssertEqual(range.start, 3600.0, accuracy: 0.001)
        XCTAssertEqual(range.end, 9015.75, accuracy: 0.001)
    }

    func testTrimRangeFromTimecodeInvalidFormatNoDash() {
        XCTAssertThrowsError(try TrimRange(from: "00:01:30.000")) { error in
            guard case FramerError.invalidTrimRange(let msg) = error else {
                XCTFail("Expected FramerError.invalidTrimRange, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Expected format"))
        }
    }

    func testTrimRangeFromTimecodeInvalidSegments() {
        XCTAssertThrowsError(try TrimRange(from: "00:30-01:00")) { error in
            guard case FramerError.invalidTrimRange(let msg) = error else {
                XCTFail("Expected FramerError.invalidTrimRange, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid timecode"))
        }
    }

    func testTrimRangeFromTimecodeNonNumeric() {
        XCTAssertThrowsError(try TrimRange(from: "ab:cd:ef-00:01:00")) { error in
            guard case FramerError.invalidTrimRange(let msg) = error else {
                XCTFail("Expected FramerError.invalidTrimRange, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Non-numeric"))
        }
    }

    func testTrimRangeFromTimecodeStartAfterEnd() {
        XCTAssertThrowsError(try TrimRange(from: "00:05:00.000-00:01:00.000")) { error in
            guard case FramerError.invalidTrimRange = error else {
                XCTFail("Expected FramerError.invalidTrimRange, got \(error)")
                return
            }
        }
    }

    func testTrimRangeCodableRoundtrip() throws {
        let original = try TrimRange(start: 10.5, end: 60.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrimRange.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - VideoExportConfig Tests

    func testVideoExportConfigDefaults() {
        let config = VideoExportConfig()
        XCTAssertEqual(config.codec, .h264)
        XCTAssertNil(config.trim)
    }

    func testVideoExportConfigCustomInit() throws {
        let trim = try TrimRange(start: 0, end: 30)
        let config = VideoExportConfig(codec: .h265, trim: trim)
        XCTAssertEqual(config.codec, .h265)
        XCTAssertEqual(config.trim?.start, 0)
        XCTAssertEqual(config.trim?.end, 30)
    }

    func testVideoExportConfigCodableRoundtrip() throws {
        let trim = try TrimRange(start: 5.0, end: 120.0)
        let original = VideoExportConfig(codec: .h265, trim: trim)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoExportConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testVideoExportConfigCodableRoundtripNoTrim() throws {
        let original = VideoExportConfig(codec: .h264, trim: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoExportConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - OutputFormat mp4 case

    func testOutputFormatMp4Case() {
        let config = VideoExportConfig(codec: .h265)
        let format = OutputFormat.mp4(config)
        if case .mp4(let exportConfig) = format {
            XCTAssertEqual(exportConfig.codec, .h265)
        } else {
            XCTFail("Expected .mp4 case")
        }
    }

    // MARK: - ProcessingConfig videoExport property

    func testProcessingConfigVideoExportDefaultsToNil() {
        let config = ProcessingConfig()
        XCTAssertNil(config.videoExport)
    }
}
