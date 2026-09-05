import SwiftUI
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    typealias Renderer = @Sendable (URL, ProcessingConfig, Int) async throws -> CGImage
    typealias OriginalLoader = @Sendable (URL, Int) async throws -> CGImage

    var previewImage: UIImage?
    var originalImage: UIImage?
    var isLoading = false
    var error: String?
    var isOriginalLoading = false
    var originalError: String?
    var outputSize: CGSize?

    private var renderTask: Task<Void, Never>?
    private var originalLoadTask: Task<Void, Never>?
    private let renderer: Renderer
    private let originalLoader: OriginalLoader
    private var renderGeneration: UInt64 = 0
    private var originalLoadGeneration: UInt64 = 0
    private var previewPhotoID: PhotoItem.ID?
    private var previewRotation: Int?
    private var originalPhotoID: PhotoItem.ID?
    private var originalRotation: Int?

    init(renderer: Renderer? = nil, originalLoader: OriginalLoader? = nil) {
        let processor = FrameProcessor()
        let originalProcessor = FrameProcessor()
        if let renderer {
            self.renderer = renderer
        } else {
            self.renderer = { url, config, rotation in
                try await processor.previewCGImage(for: url, config: config, rotation: rotation)
            }
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
            outputSize = nil
            resetOriginalState()
        }
        isLoading = true
        error = nil

        if includeOriginal {
            loadOriginalIfNeeded(for: item)
        }

        let task = Task {
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
                let cgPreview = try await renderer(itemURL, config, itemRotation)
                let preview = UIImage(cgImage: cgPreview)
                guard !Task.isCancelled, generation == renderGeneration else { return }
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
                originalImage = UIImage(cgImage: cgImage)
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
