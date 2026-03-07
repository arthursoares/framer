import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Orchestrates the full image processing pipeline.
/// Runs on a background actor to keep the main thread free.
public actor FrameProcessor {
    public init() {}

    // MARK: - Preview (downscaled, no disk I/O)

    public func previewImage(for url: URL, config: ProcessingConfig) throws -> sending NSImage {
        let fullImage = try loadImage(from: url)
        let cgImage = downscale(fullImage, maxDimension: 1200)
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

    public func process(input: URL, output: URL, config: ProcessingConfig) throws {
        let cgImage = try loadImage(from: input)
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
