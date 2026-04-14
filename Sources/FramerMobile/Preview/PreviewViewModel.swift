import SwiftUI
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    var previewImage: UIImage?
    var originalImage: UIImage?
    var isLoading = false
    var error: String?
    var outputSize: CGSize?

    private var renderTask: Task<Void, Never>?
    private var originalLoadTask: Task<Void, Never>?
    private var originalImageURL: URL?
    private let processor = FrameProcessor()

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig, includeOriginal: Bool = false) {
        renderTask?.cancel()

        guard let item else {
            renderTask = nil
            originalLoadTask?.cancel()
            originalLoadTask = nil
            originalImageURL = nil
            previewImage = nil
            originalImage = nil
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

        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            isLoading = true
            error = nil
            defer { isLoading = false }

            do {
                let itemURL = item.url
                let itemRotation = item.rotation
                let cgPreview = try await processor.previewCGImage(for: itemURL, config: config, rotation: itemRotation)
                let preview = UIImage(cgImage: cgPreview)
                guard !Task.isCancelled else {
                    return
                }
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

    private nonisolated static func loadOriginal(from url: URL, maxDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let w = cgImage.width, h = cgImage.height
        guard max(w, h) > maxDimension else {
            return UIImage(cgImage: cgImage)
        }
        let scale = Double(maxDimension) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)
        // Canonical premultipliedLast RGBA8 — see desktop PreviewViewModel
        // for the context-compatibility rationale.
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: newW * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let scaled = (ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH)), ctx.makeImage()).1 else {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(cgImage: scaled)
    }
}
