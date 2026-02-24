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

    // MARK: - PrintFormat Tests

    func test_printFormat_defaultPixelCalculation() {
        let format = PrintFormat.print10x15
        // 148mm / 25.4 * 300 = 1748.03... → 1748
        XCTAssertEqual(format.widthPixels, 1748)
        // 100mm / 25.4 * 300 = 1181.10... → 1181
        XCTAssertEqual(format.heightPixels, 1181)
    }

    func test_printFormat_customDimensions() {
        let format = PrintFormat(widthMM: 200, heightMM: 150, dpi: 600)
        let expectedW = Int((200.0 / 25.4) * 600.0)
        let expectedH = Int((150.0 / 25.4) * 600.0)
        XCTAssertEqual(format.widthPixels, expectedW)
        XCTAssertEqual(format.heightPixels, expectedH)
    }

    // MARK: - BorderStyle JSON Round-trip

    func test_borderStyle_solid_roundtripsJSON() throws {
        let style = BorderStyle.solid
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BorderStyle.self, from: data)
        XCTAssertEqual(decoded, .solid)
    }

    func test_borderStyle_instagram_roundtripsJSON() throws {
        let style = BorderStyle.instagram
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BorderStyle.self, from: data)
        XCTAssertEqual(decoded, .instagram)
    }

    func test_borderStyle_print_roundtripsJSON() throws {
        let format = PrintFormat(widthMM: 200, heightMM: 150, dpi: 600)
        let style = BorderStyle.print(format)
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BorderStyle.self, from: data)
        XCTAssertEqual(decoded, style)
    }

    func test_borderStyle_print10x15_stringBackwardCompat() throws {
        // Simulate a JSON string "print10x15" being decoded
        let json = "\"print10x15\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BorderStyle.self, from: data)
        XCTAssertEqual(decoded, .print(.print10x15))
    }

    // MARK: - ProcessingConfig backward compat

    func test_processingConfig_decodesWithMissingNewFields() throws {
        // Encode a config, then strip the new fields to simulate old data
        var config = ProcessingConfig.default
        config.borderStyle = .instagram
        let data = try JSONEncoder().encode(config)

        // Decode a JSON that has all the old fields
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Remove new fields
        dict.removeValue(forKey: "backgroundColor")
        dict.removeValue(forKey: "outerPadding")
        dict.removeValue(forKey: "captionPadding")
        dict.removeValue(forKey: "noMetadata")

        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(ProcessingConfig.self, from: strippedData)

        // Should use defaults for missing fields
        XCTAssertEqual(decoded.borderStyle, .instagram)
        XCTAssertEqual(decoded.backgroundColor.hex, "#FFFFFF")
        XCTAssertEqual(decoded.outerPadding, 0)
        XCTAssertEqual(decoded.captionPadding, 0)
        XCTAssertEqual(decoded.noMetadata, false)
    }

    // MARK: - Template Placeholder Tests

    func test_exifData_monthPlaceholder_fullName() {
        var exif = ExifData()
        // January 15, 2024
        let cal = Calendar.current
        exif.dateTime = cal.date(from: DateComponents(year: 2024, month: 1, day: 15))

        let result = exif.resolve(template: "{{month}}")
        XCTAssertEqual(result, "January")
    }

    func test_exifData_datePlaceholder_isoFormat() {
        var exif = ExifData()
        let cal = Calendar.current
        exif.dateTime = cal.date(from: DateComponents(year: 2024, month: 3, day: 5))

        let result = exif.resolve(template: "{{date}}")
        XCTAssertEqual(result, "2024-03-05")
    }

    func test_exifData_monthPlaceholder_december() {
        var exif = ExifData()
        let cal = Calendar.current
        exif.dateTime = cal.date(from: DateComponents(year: 2024, month: 12, day: 25))

        let result = exif.resolve(template: "{{month}}")
        XCTAssertEqual(result, "December")
    }

    // MARK: - New config fields

    func test_defaultConfig_newFieldDefaults() {
        let config = ProcessingConfig.default
        XCTAssertEqual(config.backgroundColor.hex, "#FFFFFF")
        XCTAssertEqual(config.outerPadding, 0)
        XCTAssertEqual(config.captionPadding, 0)
        XCTAssertEqual(config.noMetadata, false)
    }
}
