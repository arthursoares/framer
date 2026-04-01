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
    private let processor = FrameProcessor()

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig) {
        renderTask?.cancel()

        guard let item else {
            renderTask = nil
            previewImage = nil
            originalImage = nil
            exifData = nil
            error = nil
            outputSize = nil
            isLoading = false
            return
        }

        renderTask = Task {
            // Debounce: wait 150ms before rendering
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            isLoading = true
            error = nil
            defer { isLoading = false }

            do {
                let exif = try? EXIFReader.read(from: item.url)
                exifData = exif

                // Run original decode and preview render concurrently.
                // loadOriginal is CPU-bound and synchronous, so push it onto a
                // detached task to avoid blocking the MainActor executor.
                let itemURL = item.url
                let itemRotation = item.rotation
                let originalHandle = Task.detached {
                    Self.loadOriginal(from: itemURL, maxDimension: 1200)
                }
                defer { originalHandle.cancel() }
                let cgPreview = try await processor.previewCGImage(for: itemURL, config: config, rotation: itemRotation)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let preview = NSImage(cgImage: cgPreview, size: NSSize(
                    width: CGFloat(cgPreview.width) / scale,
                    height: CGFloat(cgPreview.height) / scale
                ))
                let original = await originalHandle.value
                guard !Task.isCancelled else {
                    return
                }
                originalImage = original
                previewImage = preview
                // Output size in actual pixels (not points)
                outputSize = CGSize(width: cgPreview.width, height: cgPreview.height)
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
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
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: cgImage.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: cgImage.bitmapInfo.rawValue),
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
