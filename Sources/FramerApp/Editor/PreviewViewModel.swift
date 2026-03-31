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
        guard let item else {
            previewImage = nil
            originalImage = nil
            exifData = nil
            error = nil
            outputSize = nil
            return
        }

        renderTask?.cancel()
        renderTask = Task {
            // Debounce: wait 150ms before rendering
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            isLoading = true
            error = nil

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
                let preview = try await processor.previewImage(for: itemURL, config: config, rotation: itemRotation)
                let original = await originalHandle.value
                guard !Task.isCancelled else { return }
                originalImage = original
                previewImage = preview
                outputSize = preview.size
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Loads and downscales the source image for before/after comparison.
    private nonisolated static func loadOriginal(from url: URL, maxDimension: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let w = cgImage.width, h = cgImage.height
        guard max(w, h) > maxDimension else {
            return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
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
            return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
        }
        return NSImage(cgImage: scaled, size: NSSize(width: newW, height: newH))
    }
}
