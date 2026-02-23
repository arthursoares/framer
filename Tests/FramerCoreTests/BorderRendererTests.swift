// Tests/FramerCoreTests/BorderRendererTests.swift
import XCTest
import CoreImage
@testable import FramerCore

final class BorderRendererTests: XCTestCase {
    func makeTestImage(width: Int = 100, height: Int = 80) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func test_solidBorder_increasesCanvasSize() throws {
        let image = makeTestImage()
        let config = ProcessingConfig.default // 20px border, 150px padding
        let result = try BorderRenderer.applyBorder(to: image, config: config, style: .solid)
        // Canvas should be larger than original
        XCTAssertGreaterThan(result.width, image.width)
        XCTAssertGreaterThan(result.height, image.height)
    }

    func test_solidBorder_pixelThickness_correctSize() throws {
        let image = makeTestImage(width: 100, height: 100)
        var config = ProcessingConfig.default
        config.borderThickness = .pixels(10)
        config.padding = 0
        let result = try BorderRenderer.applyBorder(to: image, config: config, style: .solid)
        XCTAssertEqual(result.width, 120) // 100 + 2*10
        XCTAssertEqual(result.height, 120)
    }

    func test_instagramBorder_hasFixedAspectRatio() throws {
        let image = makeTestImage(width: 800, height: 600)
        let config = ProcessingConfig.default
        let result = try BorderRenderer.applyBorder(to: image, config: config, style: .instagram)
        // Instagram is 4:5 = 1080x1350 scaled
        let ratio = Double(result.width) / Double(result.height)
        XCTAssertEqual(ratio, 1080.0 / 1350.0, accuracy: 0.01)
    }
}
