import SwiftUI
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    var previewImage: NSImage?
    var originalImage: NSImage?
    var isLoading = false
    var error: String?
    var exifData: ExifData?

    private var renderTask: Task<Void, Never>?
    private let processor = FrameProcessor()

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig) {
        guard let item else {
            previewImage = nil
            originalImage = nil
            exifData = nil
            error = nil
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

                // Load original at preview resolution for before/after comparison
                originalImage = Self.loadOriginal(from: item.url, maxDimension: 1200)

                let image = try await processor.previewImage(for: item.url, config: config)
                guard !Task.isCancelled else { return }
                previewImage = image
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Loads and downscales the source image for before/after comparison.
    private static func loadOriginal(from url: URL, maxDimension: Int) -> NSImage? {
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
