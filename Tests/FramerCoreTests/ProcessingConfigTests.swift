import XCTest
@testable import FramerCore

final class ProcessingConfigTests: XCTestCase {
    func test_defaultConfig_hasSolidBorderStyle() {
        let config = ProcessingConfig.default
        XCTAssertEqual(config.borderStyle, .solid)
    }

    func test_borderColor_roundtripsHex() throws {
        let color = try CodableColor(hex: "#FF5733")
        XCTAssertEqual(color.hex, "#FF5733")
    }

    func test_borderColor_lowercaseNormalized() throws {
        let color = try CodableColor(hex: "#ff5733")
        XCTAssertEqual(color.hex, "#FF5733")
    }

    func test_borderColor_invalidHex_throws() {
        XCTAssertThrowsError(try CodableColor(hex: "nope"))
    }

    func test_borderSize_pixels_roundtripsJSON() throws {
        let size = BorderSize.pixels(50)
        let data = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(BorderSize.self, from: data)
        XCTAssertEqual(size, decoded)
    }

    func test_borderSize_percent_roundtripsJSON() throws {
        let size = BorderSize.percent(5.0)
        let data = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(BorderSize.self, from: data)
        XCTAssertEqual(size, decoded)
    }

    func test_borderSize_stringParsing_pixels() {
        let size = BorderSize(string: "50")
        XCTAssertEqual(size, .pixels(50))
    }

    func test_borderSize_stringParsing_percent() {
        let size = BorderSize(string: "5%")
        XCTAssertEqual(size, .percent(5.0))
    }

    func test_borderSize_resolved_pixels() {
        let size = BorderSize.pixels(20)
        XCTAssertEqual(size.resolved(relativeTo: 1000), 20)
    }

    func test_borderSize_resolved_percent() {
        let size = BorderSize.percent(10)
        XCTAssertEqual(size.resolved(relativeTo: 1000), 100)
    }

    func test_processingConfig_roundtripsJSON() throws {
        let config = ProcessingConfig.default
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProcessingConfig.self, from: data)
        XCTAssertEqual(config.borderStyle, decoded.borderStyle)
        XCTAssertEqual(config.padding, decoded.padding)
    }

    func test_exifData_resolveTemplate() {
        var exif = ExifData()
        exif.camera = "Sony A7IV"
        exif.aperture = "2.8"
        exif.iso = "800"

        let result = exif.resolve(template: "{{camera}} {{aperture}} {{iso}}")
        XCTAssertEqual(result, "Sony A7IV f/2.8 ISO 800")
    }

    func test_exifData_resolveTemplate_missingFields() {
        let exif = ExifData()
        let result = exif.resolve(template: "{{camera}} {{lens}}")
        XCTAssertEqual(result, " ")
    }
}
