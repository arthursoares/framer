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

    func test_renderCaption_doesNotChangeImageSize() throws {
        let image = makeTestImage()
        let params = CaptionLayerParams(
            mode: .custom("TEST CAPTION"),
            fontName: "Courier New",
            fontSize: .fixed(20)
        )
        let result = try CaptionRenderer.renderCaption(
            on: image, params: params, exif: ExifData()
        )
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_renderCaption_noneMode_returnsOriginal() throws {
        let image = makeTestImage()
        let params = CaptionLayerParams(mode: .none)
        let result = try CaptionRenderer.renderCaption(
            on: image, params: params, exif: ExifData()
        )
        // Same dimensions
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }
}
