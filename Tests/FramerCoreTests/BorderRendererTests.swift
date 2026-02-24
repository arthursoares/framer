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
        let borderResult = try BorderRenderer.applyBorder(to: image, config: config, style: .solid)
        // Canvas should be larger than original
        XCTAssertGreaterThan(borderResult.image.width, image.width)
        XCTAssertGreaterThan(borderResult.image.height, image.height)
        // Solid style should not report image origin/size
        XCTAssertNil(borderResult.imageOrigin)
        XCTAssertNil(borderResult.imageSize)
    }

    func test_solidBorder_pixelThickness_correctSize() throws {
        let image = makeTestImage(width: 100, height: 100)
        var config = ProcessingConfig.default
        config.borderThickness = .pixels(10)
        config.padding = 0
        let borderResult = try BorderRenderer.applyBorder(to: image, config: config, style: .solid)
        XCTAssertEqual(borderResult.image.width, 120) // 100 + 2*10
        XCTAssertEqual(borderResult.image.height, 120)
    }

    func test_instagramBorder_hasFixedAspectRatio() throws {
        let image = makeTestImage(width: 800, height: 600)
        let config = ProcessingConfig.default
        let borderResult = try BorderRenderer.applyBorder(to: image, config: config, style: .instagram)
        // Instagram is 4:5 = 1080x1350 scaled
        let ratio = Double(borderResult.image.width) / Double(borderResult.image.height)
        XCTAssertEqual(ratio, 1080.0 / 1350.0, accuracy: 0.01)
        // Instagram style should not report image origin/size
        XCTAssertNil(borderResult.imageOrigin)
        XCTAssertNil(borderResult.imageSize)
    }

    // MARK: - Print Border Tests

    func test_printBorder_outputDimensionsMatchPrintFormat() throws {
        let image = makeTestImage(width: 800, height: 600)
        var config = ProcessingConfig.default
        config.borderStyle = .print(.print10x15)
        let format = PrintFormat.print10x15
        let borderResult = try BorderRenderer.applyBorder(to: image, config: config, style: .print(format))
        XCTAssertEqual(borderResult.image.width, format.widthPixels)
        XCTAssertEqual(borderResult.image.height, format.heightPixels)
        // Print style should report image origin and size
        XCTAssertNotNil(borderResult.imageOrigin)
        XCTAssertNotNil(borderResult.imageSize)
    }

    func test_printBorder_verticalImageGetsRotated() throws {
        // Create a vertical (portrait) image: width < height
        let image = makeTestImage(width: 80, height: 100)
        let format = PrintFormat.print10x15
        let config = ProcessingConfig.default
        let borderResult = try BorderRenderer.applyBorder(to: image, config: config, style: .print(format))
        // Output should be the print format dimensions (landscape)
        XCTAssertEqual(borderResult.image.width, format.widthPixels)
        XCTAssertEqual(borderResult.image.height, format.heightPixels)
        // The image should have been auto-rotated to landscape before scaling
        // so the drawn image should be wider than it is tall
        if let size = borderResult.imageSize {
            XCTAssertGreaterThan(size.width, size.height,
                "Vertical image should be rotated to landscape for print")
        }
    }

    func test_printBorder_customFormatDimensions() throws {
        let image = makeTestImage(width: 400, height: 300)
        let customFormat = PrintFormat(widthMM: 210, heightMM: 148, dpi: 150)
        let config = ProcessingConfig.default
        let borderResult = try BorderRenderer.applyBorder(to: image, config: config, style: .print(customFormat))
        XCTAssertEqual(borderResult.image.width, customFormat.widthPixels)
        XCTAssertEqual(borderResult.image.height, customFormat.heightPixels)
    }
}
