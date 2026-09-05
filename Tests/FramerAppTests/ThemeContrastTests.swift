import XCTest
import AppKit
import SwiftUI
@testable import Framer

@MainActor
final class ThemeContrastTests: XCTestCase {
    func test_normalTextTokensRemainReadableOnAppSurfaces() throws {
        let text: [(String, Color)] = [("text0", .text0), ("text1", .text1), ("text2", .text2), ("text3", .text3)]
        let surfaces: [Color] = [.surface0, .surface1, .surface2, .surface3, .surface4]
        for (name, color) in text {
            for (index, surface) in surfaces.enumerated() {
                let foreground = try luminance(color)
                let background = try luminance(surface)
                let ratio = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) on surface\(index): \(ratio):1")
            }
        }
    }

    private func luminance(_ color: Color) throws -> Double {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        let linear = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { component in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
