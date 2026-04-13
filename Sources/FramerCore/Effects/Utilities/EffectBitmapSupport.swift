import Foundation
import CoreGraphics

enum EffectBitmapSupport {
    static func rasterize(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // No manual Y-flip. CGBitmapContext stores pixels top-down in memory
        // (row 0 = top of image) regardless of draw-coordinate direction, and
        // ctx.draw(image, rect) writes to that storage in the same convention.
        // The previous `translateBy(y: height) + scaleBy(y: -1)` dance was a
        // no-op for the MEMORY layout but an unnecessary source of confusion;
        // worse, it diverged from the ShaderPrimitives.renderToRGBAContext
        // pattern that the shader-style GPU renderers use, so bucket-system
        // output appeared upside-down relative to every other layer's output
        // when composited in the preview pipeline.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    static func makeImage(from pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
