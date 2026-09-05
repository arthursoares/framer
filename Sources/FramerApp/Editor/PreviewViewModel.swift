import SwiftUI
@preconcurrency import AppKit
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    typealias Renderer = @Sendable (URL, ProcessingConfig, Int) async throws -> CGImage
    typealias ExifLoader = @Sendable (URL) async -> ExifData?
    typealias OriginalLoader = @Sendable (URL, Int) async throws -> CGImage

    var previewImage: NSImage?
    var originalImage: NSImage?
    var isLoading = false
    var error: String?
    var isOriginalLoading = false
    var originalError: String?
    var exifData: ExifData?
    /// Pixel dimensions of the rendered output image.
    var outputSize: CGSize?

    private var renderTask: Task<Void, Never>?
    private var originalLoadTask: Task<Void, Never>?
    private let renderer: Renderer
    private let exifLoader: ExifLoader
    private let originalLoader: OriginalLoader
    private var renderGeneration: UInt64 = 0
    private var originalLoadGeneration: UInt64 = 0
    private var previewPhotoID: PhotoItem.ID?
    private var previewRotation: Int?
    private var originalPhotoID: PhotoItem.ID?
    private var originalRotation: Int?

    init(
        renderer: Renderer? = nil,
        exifLoader: ExifLoader? = nil,
        originalLoader: OriginalLoader? = nil
    ) {
        let processor = FrameProcessor()
        let originalProcessor = FrameProcessor()
        self.renderer = renderer ?? { url, config, rotation in
            try await processor.previewCGImage(for: url, config: config, rotation: rotation)
        }
        self.exifLoader = exifLoader ?? { url in
            await processor.exifData(for: url)
        }
        self.originalLoader = originalLoader ?? { url, rotation in
            try await originalProcessor.previewCGImage(
                for: url,
                config: ProcessingConfig(layers: []),
                rotation: rotation,
                maxDimension: 1200
            )
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
            previewPhotoID = nil
            previewRotation = nil
            previewImage = nil
            exifData = nil
            error = nil
            outputSize = nil
            isLoading = false
            resetOriginalState()
            return nil
        }

        let selectionChanged = previewPhotoID != item.id || previewRotation != item.rotation
        previewPhotoID = item.id
        previewRotation = item.rotation
        if selectionChanged {
            previewImage = nil
            exifData = nil
            outputSize = nil
            resetOriginalState()
        }
        isLoading = true
        error = nil

        if includeOriginal {
            loadOriginalIfNeeded(for: item)
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

            defer {
                if generation == renderGeneration {
                    isLoading = false
                    renderTask = nil
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

    @discardableResult
    func loadOriginalIfNeeded(for item: PhotoItem?) -> Task<Void, Never>? {
        guard let item else {
            resetOriginalState()
            return nil
        }

        let matchesRequest = originalPhotoID == item.id && originalRotation == item.rotation
        if matchesRequest, originalImage != nil || isOriginalLoading {
            return originalLoadTask
        }

        originalLoadTask?.cancel()
        originalLoadGeneration &+= 1
        let generation = originalLoadGeneration
        let photoID = item.id
        let itemURL = item.url
        let rotation = item.rotation
        originalPhotoID = photoID
        originalRotation = rotation
        originalImage = nil
        originalError = nil
        isOriginalLoading = true

        let task = Task(priority: .utility) {
            defer {
                if generation == originalLoadGeneration {
                    isOriginalLoading = false
                    originalLoadTask = nil
                }
            }
            do {
                let cgImage = try await originalLoader(itemURL, rotation)
                guard !Task.isCancelled,
                      generation == originalLoadGeneration,
                      originalPhotoID == photoID,
                      originalRotation == rotation else { return }
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                originalImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                ))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      generation == originalLoadGeneration,
                      originalPhotoID == photoID,
                      originalRotation == rotation else { return }
                originalError = error.localizedDescription
            }
        }
        originalLoadTask = task
        return task
    }

    private func resetOriginalState() {
        originalLoadTask?.cancel()
        originalLoadGeneration &+= 1
        originalLoadTask = nil
        originalPhotoID = nil
        originalRotation = nil
        originalImage = nil
        originalError = nil
        isOriginalLoading = false
    }
}
