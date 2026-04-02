// Tests/FramerCoreTests/EXIFReaderTests.swift
import XCTest
@testable import FramerCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

    func test_readExif_negativeExposure_omitsShutterSpeed() throws {
        let url = try makeJPEGWithExposureTime(-0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let exif = try EXIFReader.read(from: url)

        XCTAssertNil(exif.shutterSpeed)
    }

    func test_readExif_zeroExposure_omitsShutterSpeed() throws {
        let url = try makeJPEGWithExposureTime(0)
        defer { try? FileManager.default.removeItem(at: url) }

        let exif = try EXIFReader.read(from: url)

        XCTAssertNil(exif.shutterSpeed)
    }

    private func makeJPEGWithExposureTime(_ exposureTime: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Could not create image context")
        }

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw XCTSkip("Could not create JPEG destination")
        }

        let metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: exposureTime
            ]
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Could not finalize JPEG with EXIF metadata")
        }

        return url
    }
}
