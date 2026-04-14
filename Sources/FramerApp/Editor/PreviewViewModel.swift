import SwiftUI
@preconcurrency import AppKit
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    var previewImage: NSImage?
    var originalImage: NSImage?
    var isLoading = false
    var error: String?
    var exifData: ExifData?
    /// Pixel dimensions of the rendered output image.
    var outputSize: CGSize?

    private var renderTask: Task<Void, Never>?
    private var originalLoadTask: Task<Void, Never>?
    private var originalImageURL: URL?
    private let processor = FrameProcessor()
    private var renderGeneration: UInt64 = 0

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig, includeOriginal: Bool = false) {
        renderTask?.cancel()

        guard let item else {
            renderTask = nil
            originalLoadTask?.cancel()
            originalLoadTask = nil
            originalImageURL = nil
            previewImage = nil
            originalImage = nil
            exifData = nil
            error = nil
            outputSize = nil
            isLoading = false
            return
        }

        if originalImageURL != item.url {
            originalLoadTask?.cancel()
            originalLoadTask = nil
            originalImageURL = nil
            originalImage = nil
        }

        renderGeneration &+= 1
        let generation = renderGeneration

        renderTask = Task {
            // Debounce: wait 150ms before rendering
            try? await Task.sleep(for: .milliseconds(150))
            guard generation == renderGeneration else { return }

            isLoading = true
            error = nil
            defer { isLoading = false }

            do {
                let itemURL = item.url
                let itemRotation = item.rotation

                let exif = await processor.exifData(for: itemURL)
                guard generation == renderGeneration else { return }
                exifData = exif

                let cgPreview = try await processor.previewCGImage(for: itemURL, config: config, rotation: itemRotation)
                guard generation == renderGeneration else { return }
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let preview = NSImage(cgImage: cgPreview, size: NSSize(
                    width: CGFloat(cgPreview.width) / scale,
                    height: CGFloat(cgPreview.height) / scale
                ))
                previewImage = preview
                outputSize = CGSize(width: cgPreview.width, height: cgPreview.height)
                if includeOriginal {
                    loadOriginalIfNeeded(for: item)
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func loadOriginalIfNeeded(for item: PhotoItem?) {
        guard let item else {
            originalLoadTask?.cancel()
            originalLoadTask = nil
            originalImageURL = nil
            originalImage = nil
            return
        }

        if originalImageURL == item.url, originalImage != nil {
            return
        }

        originalLoadTask?.cancel()
        let itemURL = item.url
        originalImageURL = itemURL
        originalLoadTask = Task {
            let original = await Task.detached {
                Self.loadOriginal(from: itemURL, maxDimension: 1200)
            }.value
            guard !Task.isCancelled, originalImageURL == itemURL else { return }
            originalImage = original
            originalLoadTask = nil
        }
    }

    /// Loads and downscales the source image for before/after comparison.
    private nonisolated static func loadOriginal(from url: URL, maxDimension: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let w = cgImage.width, h = cgImage.height
        // NSImage size must be in points (pixels / scale) for correct Retina rendering
        let screenScale = 2.0 // safe default; nonisolated can't access NSScreen
        guard max(w, h) > maxDimension else {
            return NSImage(cgImage: cgImage, size: NSSize(
                width: Double(w) / screenScale, height: Double(h) / screenScale
            ))
        }
        let scale = Double(maxDimension) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)
        // Always downscale through a canonical premultipliedLast RGBA8
        // context rather than copying the source's `bitmapInfo.rawValue`.
        // Some ImageIO decoders hand back CGImages with combined flags
        // (`kCGImageAlphaLast | kCGImagePixelFormatPacked` etc) that
        // `CGBitmapContextCreate` rejects — leaving the whole preview
        // path to silently skip the downscale and render the full-size
        // image instead.
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: newW * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let scaled = (ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH)), ctx.makeImage()).1 else {
            return NSImage(cgImage: cgImage, size: NSSize(
                width: Double(w) / screenScale, height: Double(h) / screenScale
            ))
        }
        return NSImage(cgImage: scaled, size: NSSize(
            width: Double(newW) / screenScale, height: Double(newH) / screenScale
        ))
    }
}
