// Tests/FramerCoreTests/ColorExtractorTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class ColorExtractorTests: XCTestCase {

    // MARK: - HSLColor Conversion Tests

    func test_rgbToHsl_pureRed() {
        let hsl = HSLColor.fromRGB(r: 255, g: 0, b: 0)
        XCTAssertEqual(hsl.h, 0, accuracy: 1)
        XCTAssertEqual(hsl.s, 100, accuracy: 1)
        XCTAssertEqual(hsl.l, 50, accuracy: 1)
    }

    func test_rgbToHsl_pureGreen() {
        let hsl = HSLColor.fromRGB(r: 0, g: 255, b: 0)
        XCTAssertEqual(hsl.h, 120, accuracy: 1)
        XCTAssertEqual(hsl.s, 100, accuracy: 1)
        XCTAssertEqual(hsl.l, 50, accuracy: 1)
    }

    func test_rgbToHsl_pureBlue() {
        let hsl = HSLColor.fromRGB(r: 0, g: 0, b: 255)
        XCTAssertEqual(hsl.h, 240, accuracy: 1)
        XCTAssertEqual(hsl.s, 100, accuracy: 1)
        XCTAssertEqual(hsl.l, 50, accuracy: 1)
    }

    func test_rgbToHsl_white() {
        let hsl = HSLColor.fromRGB(r: 255, g: 255, b: 255)
        XCTAssertEqual(hsl.s, 0, accuracy: 1)
        XCTAssertEqual(hsl.l, 100, accuracy: 1)
    }

    func test_rgbToHsl_gray() {
        let hsl = HSLColor.fromRGB(r: 128, g: 128, b: 128)
        XCTAssertEqual(hsl.s, 0, accuracy: 1)
        XCTAssertEqual(hsl.l, 50, accuracy: 2)
    }

    func test_hslToRgb_roundtrip() {
        let original = HSLColor(h: 210, s: 60, l: 45)
        let (r, g, b) = original.rgbComponents
        let roundtripped = HSLColor.fromRGB(r: r * 255, g: g * 255, b: b * 255)
        XCTAssertEqual(roundtripped.h, original.h, accuracy: 1)
        XCTAssertEqual(roundtripped.s, original.s, accuracy: 1)
        XCTAssertEqual(roundtripped.l, original.l, accuracy: 1)
    }

    // MARK: - Color Extraction Tests

    func test_extractDominantColor_fromRedImage() {
        let image = makeColorImage(r: 200, g: 50, b: 50)
        let dominant = ColorExtractor.extractDominantColor(from: image)
        // Should detect hue near red (0° or 360°)
        XCTAssert(dominant.h < 30 || dominant.h > 330,
            "Expected hue near red, got \(dominant.h)")
        XCTAssertGreaterThan(dominant.s, 30, "Expected saturated color")
    }

    func test_extractDominantColor_fromBlueImage() {
        let image = makeColorImage(r: 50, g: 50, b: 200)
        let dominant = ColorExtractor.extractDominantColor(from: image)
        // Should detect hue near blue (240°)
        XCTAssertEqual(dominant.h, 240, accuracy: 30,
            "Expected hue near blue, got \(dominant.h)")
        XCTAssertGreaterThan(dominant.s, 30, "Expected saturated color")
    }

    func test_extractDominantColor_fromGrayscaleImage() {
        let image = makeColorImage(r: 128, g: 128, b: 128)
        let dominant = ColorExtractor.extractDominantColor(from: image)
        // Grayscale images should return low saturation
        XCTAssertLessThan(dominant.s, 20, "Expected low saturation for gray image")
    }

    // MARK: - Gradient Generation Tests

    func test_generateGradientColors_returnsTwoColors() {
        let dominant = HSLColor(h: 200, s: 70, l: 45)
        let (center, edge) = ColorExtractor.generateGradientColors(dominant: dominant)
        XCTAssertNotNil(center)
        XCTAssertNotNil(edge)
        // Both should have color components
        XCTAssertEqual(center.numberOfComponents, 4) // RGBA
        XCTAssertEqual(edge.numberOfComponents, 4)
    }

    func test_generateGradientColors_edgeIsDarkerForDarkInput() {
        let dominant = HSLColor(h: 200, s: 70, l: 30) // dark
        let (center, edge) = ColorExtractor.generateGradientColors(dominant: dominant)
        // Edge should be darker (lower lightness) than center
        let centerComps = center.components!
        let edgeComps = edge.components!
        let centerLum = centerComps[0] * 0.299 + centerComps[1] * 0.587 + centerComps[2] * 0.114
        let edgeLum = edgeComps[0] * 0.299 + edgeComps[1] * 0.587 + edgeComps[2] * 0.114
        XCTAssertLessThan(edgeLum, centerLum, "Edge should be darker than center for dark input")
    }

    // MARK: - Helpers

    private func makeColorImage(r: UInt8, g: UInt8, b: UInt8, width: Int = 100, height: Int = 100) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}
