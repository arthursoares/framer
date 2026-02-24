import XCTest
import CoreGraphics
import ImageIO
@testable import FramerCore

final class MetadataWriterTests: XCTestCase {
    // MARK: - Helpers

    func makeTestImage(width: Int = 100, height: Int = 80) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    var sampleURL: URL {
        Bundle.module.url(forResource: "sample", withExtension: "jpg", subdirectory: "Resources")!
    }

    private func tempOutputURL(ext: String = "jpg") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("metadata_writer_test_\(UUID().uuidString).\(ext)")
    }

    // MARK: - Tests

    func test_metadataPreserved_exifDateExists() throws {
        let image = makeTestImage()
        let output = tempOutputURL()
        defer { try? FileManager.default.removeItem(at: output) }

        try MetadataWriter.encode(
            image,
            to: output,
            format: .jpeg(quality: 90),
            sourceURL: sampleURL,
            borderStyle: .solid,
            preserveMetadata: true
        )

        // Read back the written file and check for EXIF data
        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            XCTFail("Could not read properties from output file")
            return
        }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNotNil(exif, "EXIF dictionary should be present when metadata is preserved")

        // The sample image should have a date; verify it was copied
        let dateOriginal = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
        XCTAssertNotNil(dateOriginal, "EXIF DateTimeOriginal should be preserved from source")
    }

    func test_iptcKeywordsAdded() throws {
        let image = makeTestImage()
        let output = tempOutputURL()
        defer { try? FileManager.default.removeItem(at: output) }

        try MetadataWriter.encode(
            image,
            to: output,
            format: .jpeg(quality: 90),
            sourceURL: sampleURL,
            borderStyle: .instagram,
            preserveMetadata: true
        )

        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            XCTFail("Could not read properties from output file")
            return
        }

        let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
        XCTAssertNotNil(iptc, "IPTC dictionary should be present")

        let keywords = iptc?[kCGImagePropertyIPTCKeywords as String] as? [String]
        XCTAssertNotNil(keywords, "IPTC keywords should be present")
        XCTAssertTrue(keywords?.contains("framer") == true, "Keywords should contain 'framer'")
        XCTAssertTrue(
            keywords?.contains("framer - instagram") == true,
            "Keywords should contain 'framer - instagram'"
        )
    }

    func test_noMetadata_skipsPreservation() throws {
        let image = makeTestImage()
        let output = tempOutputURL()
        defer { try? FileManager.default.removeItem(at: output) }

        try MetadataWriter.encode(
            image,
            to: output,
            format: .jpeg(quality: 90),
            sourceURL: sampleURL,
            borderStyle: .solid,
            preserveMetadata: false
        )

        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            // No properties at all is acceptable when metadata is not preserved
            return
        }

        // EXIF and IPTC dictionaries should not be present from source
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any]

        // When preserveMetadata is false, source EXIF should not be copied
        let dateOriginal = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
        XCTAssertNil(dateOriginal, "EXIF DateTimeOriginal should not be present when metadata is not preserved")

        // IPTC keywords from framer should not be present
        let keywords = iptc?[kCGImagePropertyIPTCKeywords as String] as? [String]
        XCTAssertNil(keywords, "IPTC keywords should not be present when metadata is not preserved")
    }
}
