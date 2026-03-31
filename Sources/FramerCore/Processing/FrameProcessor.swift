import Foundation
import CoreGraphics
import ImageIO

/// Orchestrates the full image processing pipeline.
/// Runs on a background actor to keep the main thread free.
public actor FrameProcessor {
    public init() {}

    // MARK: - Preview (downscaled, no disk I/O)

    public func previewCGImage(for url: URL, config: ProcessingConfig, rotation: Int = 0) throws -> sending CGImage {
        let fullImage = try loadImage(from: url)
        let rotated = applyRotation(fullImage, degrees: rotation)
        try Task.checkCancellation()
        let previewMax = previewMaxDimension(for: config, imageWidth: rotated.width, imageHeight: rotated.height)
        let cgImage = downscale(rotated, maxDimension: previewMax)
        try Task.checkCancellation()
        let exif = (try? EXIFReader.read(from: url)) ?? ExifData()

        let borderResult: BorderResult
        if let layers = config.layers {
            borderResult = try BorderRenderer.applyLayers(layers, to: cgImage, sourceImage: cgImage, exif: exif)
        } else {
            borderResult = try BorderRenderer.applyBorder(to: cgImage, config: config, style: config.borderStyle)
        }

        return borderResult.image
    }

    // MARK: - Full Export

    public func process(input: URL, output: URL, config: ProcessingConfig, rotation: Int = 0) throws {
        let cgImage = applyRotation(try loadImage(from: input), degrees: rotation)
        let exif = (try? EXIFReader.read(from: input)) ?? ExifData()

        // Compute the preview base dimension so DitherRenderer can match pixel scale
        let previewBase = previewMaxDimension(for: config, imageWidth: cgImage.width, imageHeight: cgImage.height)

        let borderResult: BorderResult
        if let layers = config.layers {
            borderResult = try BorderRenderer.applyLayers(layers, to: cgImage, sourceImage: cgImage, exif: exif, previewBaseDimension: previewBase)
        } else {
            borderResult = try BorderRenderer.applyBorder(to: cgImage, config: config, style: config.borderStyle)
        }

        try MetadataWriter.encode(
            borderResult.image,
            to: output,
            format: config.outputFormat,
            sourceURL: input,
            borderStyle: config.borderStyle,
            preserveMetadata: !config.noMetadata
        )
    }

    // MARK: - Helpers

    private func loadImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FramerError.invalidImage(url)
        }
        return image
    }

    /// Compute preview downscale target based on layer requirements.
    /// Simulates all size-mutating layers to determine the largest intermediate
    /// dimension the photo reaches, so the preview is scaled appropriately.
    private func previewMaxDimension(for config: ProcessingConfig, imageWidth: Int, imageHeight: Int) -> Int {
        let baseDimension = 1200
        let layers = config.layers ?? CompositionLayer.defaultLayers()

        // Walk the layer stack, simulating size changes to find the max intermediate dimension.
        // This ensures aspectRatio, resize, canvas, border, and padding are all accounted for.
        var w = CGFloat(imageWidth)
        var h = CGFloat(imageHeight)
        var maxDim: CGFloat = 0

        for layer in layers {
            switch layer {
            case .aspectRatio(let p):
                let cropped = p.croppedSize(for: CGSize(width: w, height: h))
                w = cropped.width
                h = cropped.height

            case .border(let p):
                let shorter = Int(min(w, h))
                let t = CGFloat(p.thickness.resolved(relativeTo: shorter))
                w += t * 2
                h += t * 2

            case .padding(let p):
                let t = CGFloat(p.thickness)
                w += t * 2
                h += t * 2

            case .canvas(let p):
                w = CGFloat(p.width)
                h = CGFloat(p.height)

            case .resize(let p):
                let maxW = CGFloat(p.maxWidth)
                let maxH = CGFloat(p.maxHeight)
                if w > maxW || h > maxH {
                    let scale = min(maxW / w, maxH / h)
                    w = (w * scale).rounded(.down)
                    h = (h * scale).rounded(.down)
                }

            default:
                break
            }
            maxDim = max(maxDim, w, h)
        }

        let needed = Int(maxDim)
        guard needed > baseDimension else { return baseDimension }
        return min(needed, 3000)
    }

    private func applyRotation(_ image: CGImage, degrees: Int) -> CGImage {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0 else { return image }
        let radians = Double(normalized) * .pi / 180.0
        let swapDims = (normalized == 90 || normalized == 270)
        let newW = swapDims ? image.height : image.width
        let newH = swapDims ? image.width : image.height
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else { return image }
        ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        ctx.rotate(by: -radians)
        ctx.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2,
                                    width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    private func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let w = image.width, h = image.height
        guard max(w, h) > maxDimension else { return image }
        let scale = Double(maxDimension) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

}
