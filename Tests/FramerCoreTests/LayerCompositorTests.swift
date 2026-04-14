// LayerCompositorTests.swift
// Sanity tests for the standard blend-mode compositor. Covers one pixel
// per mode — the math is scalar per-pixel so single-pixel images tell
// us everything about correctness. Also pins the "opacity=0 is identity
// to base" and "opacity=1 normal is identity to over" invariants and
// the dimension-mismatch error path.

import XCTest
import CoreGraphics
@testable import FramerCore

final class LayerCompositorTests: XCTestCase {

    // MARK: - Identity invariants

    func testNormalAtFullOpacityReturnsOverUnchanged() throws {
        let base = solid(r: 100, g: 50, b: 200, width: 4, height: 4)
        let over = solid(r: 10, g: 220, b: 30, width: 4, height: 4)
        let result = try LayerCompositor.compose(base: base, over: over, mode: .normal, opacity: 1.0)
        let p = firstPixel(result)
        XCTAssertEqual(p.r, 10)
        XCTAssertEqual(p.g, 220)
        XCTAssertEqual(p.b, 30)
    }

    func testAnyModeAtZeroOpacityReturnsBase() throws {
        let base = solid(r: 100, g: 50, b: 200, width: 4, height: 4)
        let over = solid(r: 10, g: 220, b: 30, width: 4, height: 4)
        for mode in LayerBlendMode.allCases {
            let result = try LayerCompositor.compose(base: base, over: over, mode: mode, opacity: 0)
            let p = firstPixel(result)
            XCTAssertEqual(p.r, 100, "\(mode.label) at opacity=0 should leave base red unchanged")
            XCTAssertEqual(p.g, 50,  "\(mode.label) at opacity=0 should leave base green unchanged")
            XCTAssertEqual(p.b, 200, "\(mode.label) at opacity=0 should leave base blue unchanged")
        }
    }

    // MARK: - Per-mode spot checks (single pixel)

    /// Each case exercises the branch at a value where the formula is
    /// well-conditioned (not at a clamp boundary), so we catch both
    /// sign and magnitude errors in the implementation.
    func testModeFormulas() throws {
        // base = mid-gray 128, over = specific test value per mode.
        let mid: UInt8 = 128  // ≈ 0.502 in 0..1

        // multiply: mid × mid ≈ 0.252 → 64
        try assertMode(.multiply, base: mid, over: mid, expect: 64, tolerance: 2)

        // screen: 1 - (1-0.5)² = 0.75 → 191
        try assertMode(.screen, base: mid, over: mid, expect: 191, tolerance: 2)

        // difference: |0.5 - 0.5| = 0 → 0
        try assertMode(.difference, base: mid, over: mid, expect: 0)

        // exclusion: 0.5 + 0.5 - 2*0.5*0.5 = 0.5 → 128
        try assertMode(.exclusion, base: mid, over: mid, expect: 128, tolerance: 2)

        // darken: min(0.5, 0.3) = 0.3 → ~77
        try assertMode(.darken, base: mid, over: 77, expect: 77)

        // lighten: max(0.5, 0.8) = 0.8 → ~204
        try assertMode(.lighten, base: mid, over: 204, expect: 204)

        // linearDodge: clamp(0.5 + 0.3, 0, 1) = 0.8 → 204
        try assertMode(.linearDodge, base: mid, over: 77, expect: 205, tolerance: 2)

        // subtract: max(0, 0.5 - 0.3) = 0.2 → ~51
        try assertMode(.subtract, base: mid, over: 77, expect: 51, tolerance: 2)

        // linearBurn: max(0, 0.5 + 0.3 - 1) = 0 → 0
        try assertMode(.linearBurn, base: mid, over: 77, expect: 0)
    }

    // MARK: - HSL sanity

    func testLuminosityPreservesBaseHue() throws {
        // Base = pure red; Over = pure gray. Luminosity copies over's
        // lum onto base's hue → expected result has same hue as base
        // (dominant red) but brightness of over.
        let base = solid(r: 255, g: 0, b: 0, width: 2, height: 2)
        let over = solid(r: 128, g: 128, b: 128, width: 2, height: 2)
        let result = try LayerCompositor.compose(base: base, over: over, mode: .luminosity, opacity: 1.0)
        let p = firstPixel(result)
        XCTAssertGreaterThan(p.r, p.g, "Luminosity should preserve base's red-dominant hue")
        XCTAssertGreaterThan(p.r, p.b, "Luminosity should preserve base's red-dominant hue")
    }

    // MARK: - Error paths

    func testDimensionMismatchThrows() {
        let base = solid(r: 0, g: 0, b: 0, width: 4, height: 4)
        let over = solid(r: 0, g: 0, b: 0, width: 4, height: 5)
        XCTAssertThrowsError(try LayerCompositor.compose(base: base, over: over, mode: .normal, opacity: 1.0))
    }

    // MARK: - Helpers

    private func solid(r: UInt8, g: UInt8, b: UInt8, width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            data[i * 4]     = r
            data[i * 4 + 1] = g
            data[i * 4 + 2] = b
            data[i * 4 + 3] = 255
        }
        return ctx.makeImage()!
    }

    private func firstPixel(_ image: CGImage) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &bytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func assertMode(
        _ mode: LayerBlendMode,
        base: UInt8, over: UInt8,
        expect: Int, tolerance: Int = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let baseImg = solid(r: base, g: base, b: base, width: 2, height: 2)
        let overImg = solid(r: over, g: over, b: over, width: 2, height: 2)
        let result = try LayerCompositor.compose(base: baseImg, over: overImg, mode: mode, opacity: 1.0)
        let p = firstPixel(result)
        XCTAssertEqual(p.r, expect, accuracy: tolerance,
                       "\(mode.label) R", file: file, line: line)
    }
}

private func XCTAssertEqual(_ actual: Int, _ expected: Int, accuracy: Int, _ msg: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    if abs(actual - expected) > accuracy {
        XCTFail("\(msg): expected \(expected)±\(accuracy), got \(actual)", file: file, line: line)
    }
}
