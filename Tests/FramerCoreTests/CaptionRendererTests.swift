// Tests/FramerCoreTests/CaptionRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class CaptionRendererTests: XCTestCase {
    func makeTestImage(width: Int = 400, height: Int = 500) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // Solid style: imageOrigin/imageSize are nil (default)
    func test_renderCaption_doesNotChangeImageSize() throws {
        let image = makeTestImage()
        var config = ProcessingConfig.default
        config.captionMode = .custom("TEST CAPTION")
        config.fontName = "Courier New"
        config.fontSize = .fixed(20)
        let result = try CaptionRenderer.renderCaption(
            on: image, config: config, exif: ExifData(),
            imageOrigin: nil, imageSize: nil
        )
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_renderCaption_noneMode_returnsOriginal() throws {
        let image = makeTestImage()
        var config = ProcessingConfig.default
        config.captionMode = .none
        let result = try CaptionRenderer.renderCaption(
            on: image, config: config, exif: ExifData(),
            imageOrigin: nil, imageSize: nil
        )
        // Same dimensions
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    // Print style: imageOrigin/imageSize are provided
    func test_renderCaption_printStyle_doesNotChangeImageSize() throws {
        let image = makeTestImage(width: 1748, height: 1181)
        var config = ProcessingConfig.default
        config.captionMode = .custom("PRINT CAPTION")
        config.fontName = "Courier New"
        config.fontSize = .fixed(30)
        config.captionPadding = 20
        let result = try CaptionRenderer.renderCaption(
            on: image, config: config, exif: ExifData(),
            imageOrigin: CGPoint(x: 100, y: 100),
            imageSize: CGSize(width: 1548, height: 981)
        )
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }
}
