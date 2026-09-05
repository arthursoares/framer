import SwiftUI
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    typealias Renderer = @Sendable (URL, ProcessingConfig, Int) async throws -> CGImage

    var previewImage: UIImage?
    var originalImage: UIImage?
    var isLoading = false
    var error: String?
    var outputSize: CGSize?

    private var renderTask: Task<Void, Never>?
    private var originalLoadTask: Task<Void, Never>?
    private var originalImageURL: URL?
    private let renderer: Renderer
    private var renderGeneration: UInt64 = 0
    private var originalLoadGeneration: UInt64 = 0

    init(renderer: Renderer? = nil) {
        if let renderer {
            self.renderer = renderer
        } else {
            let processor = FrameProcessor()
            self.renderer = { url, config, rotation in
                try await processor.previewCGImage(for: url, config: config, rotation: rotation)
            }
        }
    }

    @discardableResult
    func updatePreview(
        for item: PhotoItem?,
        config: ProcessingConfig,
        includeOriginal: Bool = false
    ) -> Task<Void, Never>? {
        renderTask?.cancel()
        renderGeneration &+= 1
        let generation = renderGeneration

        guard let item else {
            renderTask = nil
            originalLoadTask?.cancel()
            originalLoadGeneration &+= 1
            originalLoadTask = nil
            originalImageURL = nil
            previewImage = nil
            originalImage = nil
            error = nil
            outputSize = nil
            isLoading = false
            return nil
        }

        if originalImageURL != item.url {
            originalLoadTask?.cancel()
            originalLoadGeneration &+= 1
            originalLoadTask = nil
            originalImageURL = nil
            originalImage = nil
        }

        let task = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, generation == renderGeneration else { return }

            isLoading = true
            error = nil
            defer {
                if generation == renderGeneration {
                    isLoading = false
                }
            }

            do {
                let itemURL = item.url
                let itemRotation = item.rotation
                let cgPreview = try await renderer(itemURL, config, itemRotation)
                let preview = UIImage(cgImage: cgPreview)
                guard !Task.isCancelled, generation == renderGeneration else { return }
                previewImage = preview
                outputSize = CGSize(width: cgPreview.width, height: cgPreview.height)
                if includeOriginal {
                    loadOriginalIfNeeded(for: item)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == renderGeneration else { return }
                self.error = error.localizedDescription
            }
        }
        renderTask = task
        return task
    }

    func loadOriginalIfNeeded(for item: PhotoItem?) {
        guard let item else {
            originalLoadTask?.cancel()
            originalLoadGeneration &+= 1
            originalLoadTask = nil
            originalImageURL = nil
            originalImage = nil
            return
        }

        if originalImageURL == item.url, originalImage != nil {
            return
        }

        originalLoadTask?.cancel()
        originalLoadGeneration &+= 1
        let generation = originalLoadGeneration
        let itemURL = item.url
        originalImageURL = itemURL
        originalLoadTask = Task {
            let original = await Task.detached {
                Self.loadOriginal(from: itemURL, maxDimension: 1200)
            }.value
            guard !Task.isCancelled,
                  generation == originalLoadGeneration,
                  originalImageURL == itemURL else { return }
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
