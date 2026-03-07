import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Orchestrates the full image processing pipeline.
/// Runs on a background actor to keep the main thread free.
public actor FrameProcessor {
    public init() {}

    // MARK: - Preview (downscaled, no disk I/O)

    public func previewImage(for url: URL, config: ProcessingConfig, rotation: Int = 0) throws -> sending NSImage {
        let fullImage = try loadImage(from: url)
        let rotated = applyRotation(fullImage, degrees: rotation)
        let previewMax = previewMaxDimension(for: config, imageWidth: rotated.width, imageHeight: rotated.height)
        let cgImage = downscale(rotated, maxDimension: previewMax)
        let exif = (try? EXIFReader.read(from: url)) ?? ExifData()

        let borderResult: BorderResult
        if let layers = config.layers {
            borderResult = try BorderRenderer.applyLayers(layers, to: cgImage, sourceImage: cgImage, exif: exif)
        } else {
            borderResult = try BorderRenderer.applyBorder(to: cgImage, config: config, style: config.borderStyle)
        }

        return NSImage(cgImage: borderResult.image, size: NSSize(width: borderResult.image.width, height: borderResult.image.height))
    }

    // MARK: - Full Export

    public func process(input: URL, output: URL, config: ProcessingConfig, rotation: Int = 0) throws {
        let cgImage = applyRotation(try loadImage(from: input), degrees: rotation)
        let exif = (try? EXIFReader.read(from: input)) ?? ExifData()

        let borderResult: BorderResult
        if let layers = config.layers {
            borderResult = try BorderRenderer.applyLayers(layers, to: cgImage, sourceImage: cgImage, exif: exif)
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
    /// If a canvas layer specifies large dimensions, the preview photo needs to be
    /// proportionally larger so it fills the canvas properly.
    private func previewMaxDimension(for config: ProcessingConfig, imageWidth: Int, imageHeight: Int) -> Int {
        let baseDimension = 1200
        let layers = config.layers ?? CompositionLayer.defaultLayers()

        // Find the largest canvas dimension in the layer stack
        var maxCanvasDim = 0
        for layer in layers {
            if case .canvas(let p) = layer {
                maxCanvasDim = max(maxCanvasDim, p.width, p.height)
            }
        }

        guard maxCanvasDim > baseDimension else { return baseDimension }

        // Scale up the preview so the photo proportionally fills the canvas.
        // Cap at 3000 to keep preview responsive.
        return min(maxCanvasDim, 3000)
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

    private func encode(_ image: CGImage, to url: URL, format: OutputFormat) throws {
        let utType: CFString
        var options: [CFString: Any] = [:]

        switch format {
        case .jpeg(let quality):
            utType = "public.jpeg" as CFString
            options[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100.0
        case .png:
            utType = "public.png" as CFString
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw FramerError.encodingFailed(url)
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FramerError.encodingFailed(url)
        }
    }
}
