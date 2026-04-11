import AppKit
import CoreGraphics
import ImageIO

enum ImageThumbnailLoader {
    static func loadCGThumbnail(from url: URL, maxPixelSize: Int = 160, rotation: Int = 0) async -> CGImage? {
        let cacheKey = "\(url.absoluteString)|\(maxPixelSize)|\(normalizedRotation(rotation))" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        return await Task.detached { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            let rotated = applyRotation(thumbnail, degrees: rotation)
            let nsImage = NSImage(
                cgImage: rotated,
                size: NSSize(width: rotated.width, height: rotated.height)
            )
            thumbnailCache.setObject(nsImage, forKey: cacheKey)
            return rotated
        }.value
    }

    private static func normalizedRotation(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    private static func applyRotation(_ image: CGImage, degrees: Int) -> CGImage {
        let normalized = normalizedRotation(degrees)
        guard normalized != 0 else { return image }

        let radians = Double(normalized) * .pi / 180.0
        let swapDimensions = normalized == 90 || normalized == 270
        let newWidth = swapDimensions ? image.height : image.width
        let newHeight = swapDimensions ? image.width : image.height

        guard let ctx = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        ctx.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        ctx.rotate(by: -radians)
        ctx.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return ctx.makeImage() ?? image
    }

    private nonisolated(unsafe) static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()
}
