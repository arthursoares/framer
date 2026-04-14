// MetalTextureSupportTests.swift
// Regression test for the CGBitmapContext error surfaced by some PNGs with
// non-premultiplied alpha: `MTKTextureLoader` internally tried to create a
// CGBitmapContext mirroring the input's `.alphaLast` layout — which CG
// rejects for RGB + 8bpc — leaving an incorrectly-coloured fallback upload.
// `MetalTextureSupport.makeTexture` now pre-normalises to `.premultipliedLast`
// before upload; this test exercises that path with a synthetically-built
// non-premultiplied CGImage.

import XCTest
import CoreGraphics
import Metal
@testable import FramerCore

final class MetalTextureSupportTests: XCTestCase {

    func testMakeTextureSucceedsForAlphaLastInput() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let image = try makeAlphaLastImage(width: 64, height: 64)

        let texture = try MetalTextureSupport.makeTexture(from: image, device: device)
        XCTAssertEqual(texture.width, 64)
        XCTAssertEqual(texture.height, 64)
    }

    // Build an RGBA CGImage tagged as `.alphaLast` (non-premultiplied) by
    // handing pre-filled pixel data to `CGImage` directly. CGBitmapContext
    // can't CREATE such a context, but CGImage accepts this layout for reads
    // — which is exactly the class of image that triggers the upstream error
    // when MTKTextureLoader tries to upload it.
    private func makeAlphaLastImage(width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in 0..<(width * height) {
            let idx = i * 4
            pixels[idx]     = UInt8(i % 256)
            pixels[idx + 1] = UInt8((i * 2) % 256)
            pixels[idx + 2] = UInt8((i * 3) % 256)
            pixels[idx + 3] = 200  // non-opaque so premultiplied ≠ raw
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            throw XCTSkip("Could not construct .alphaLast fixture CGImage")
        }
        return image
    }
}
