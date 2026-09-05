import SwiftUI
@preconcurrency import AppKit
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    typealias Renderer = @Sendable (URL, ProcessingConfig, Int) async throws -> CGImage
    typealias ExifLoader = @Sendable (URL) async -> ExifData?

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
    private let renderer: Renderer
    private let exifLoader: ExifLoader
    private var renderGeneration: UInt64 = 0
    private var originalLoadGeneration: UInt64 = 0

    init(renderer: Renderer? = nil, exifLoader: ExifLoader? = nil) {
        let processor = FrameProcessor()
        self.renderer = renderer ?? { url, config, rotation in
            try await processor.previewCGImage(for: url, config: config, rotation: rotation)
        }
        self.exifLoader = exifLoader ?? { url in
            await processor.exifData(for: url)
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
            exifData = nil
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

        // `.utility` priority keeps this off the User-initiated QoS band. The
        // render hops onto the `FrameProcessor` actor, which escalates to the
        // caller's QoS; at User-initiated it would block on CoreGraphics'
        // Default-QoS internal render threads (priority inversion flagged at
        // BorderRenderer's `ctx.draw`). Utility sits at/below those workers, so
        // no high-priority thread waits on a lower one. The 150ms debounce
        // already makes this non-instant, so the QoS drop is imperceptible.
        let task = Task(priority: .utility) {
            // Debounce: wait 150ms before rendering
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

                let exif = await exifLoader(itemURL)
                guard !Task.isCancelled, generation == renderGeneration else { return }
                exifData = exif

                let cgPreview = try await renderer(itemURL, config, itemRotation)
                guard !Task.isCancelled, generation == renderGeneration else { return }
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
            // The detached task returns a CGImage (Sendable) rather than an
            // NSImage. NSImage's Sendable conformance is unavailable, so it
            // cannot cross back to the main actor; we build it here instead.
            let cgImage = await Task.detached {
                Self.loadOriginalCGImage(from: itemURL, maxDimension: 1200)
            }.value
            guard !Task.isCancelled,
                  generation == originalLoadGeneration,
                  originalImageURL == itemURL,
                  let cgImage else { return }
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            originalImage = NSImage(cgImage: cgImage, size: NSSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            ))
            originalLoadTask = nil
        }
    }

    /// Loads and downscales the source image for before/after comparison.
    /// Returns a `CGImage` (which is Sendable) so the result can be handed
    /// back to the main actor, where the caller wraps it in an `NSImage`.
    private nonisolated static func loadOriginalCGImage(from url: URL, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let w = cgImage.width, h = cgImage.height
        guard max(w, h) > maxDimension else {
            return cgImage
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
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return cgImage
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? cgImage
    }
}
