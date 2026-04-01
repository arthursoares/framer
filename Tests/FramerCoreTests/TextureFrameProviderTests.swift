import XCTest
@testable import FramerCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class TextureFrameProviderTests: XCTestCase {
    func test_cachedThumbnail_respectsRequestedMaxSize() throws {
        TextureFrameProvider.invalidateCache()
        let url = try makePNG(width: 400, height: 200)
        defer { try? FileManager.default.removeItem(at: url) }

        let overlay = TextureFrameProvider.OverlayInfo(
            id: "test_overlay",
            url: url,
            displayName: "Test",
            kind: .frame
        )

        let small = try XCTUnwrap(TextureFrameProvider.cachedThumbnail(for: overlay, maxSize: 40))
        let large = try XCTUnwrap(TextureFrameProvider.cachedThumbnail(for: overlay, maxSize: 120))

        XCTAssertLessThan(small.width, large.width)
    }

    private func makePNG(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Could not create image context")
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw XCTSkip("Could not create PNG destination")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Could not finalize PNG")
        }

        return url
    }
}
