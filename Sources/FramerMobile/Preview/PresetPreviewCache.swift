import SwiftUI
import FramerCore

struct MobilePresetPreviewRenderKey: Equatable {
    let photoID: UUID?
    let photoRotation: Int?
    let presets: [Preset]
}

@MainActor
@Observable
final class PresetPreviewCache {
    typealias Renderer = @Sendable (URL, Int, Preset, Int) async throws -> CGImage

    var previews: [UUID: UIImage] = [:]
    private var renderTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let debounce: Duration?
    private let renderer: Renderer
    private let maxConcurrentPresetRenders = 4

    init(debounce: Duration? = .milliseconds(200), renderer: Renderer? = nil) {
        self.debounce = debounce
        if let renderer {
            self.renderer = renderer
        } else {
            let processor = FrameProcessor()
            self.renderer = { url, rotation, preset, maxDimension in
                try await processor.previewCGImage(
                    for: url,
                    config: preset.config,
                    rotation: rotation,
                    maxDimension: maxDimension
                )
            }
        }
    }

    func clear() {
        generation &+= 1
        renderTask?.cancel()
        renderTask = nil
        previews.removeAll()
    }

    @discardableResult
    func regenerate(for photo: PhotoItem, presets: [Preset]) -> Task<Void, Never> {
        clear()
        let requestGeneration = generation

        let url = photo.url
        let rotation = photo.rotation
        let presetList = presets
        let compactPreviewMaxDimension = 320
        let debounce = debounce
        let renderer = renderer

        let task = Task {
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled, requestGeneration == generation else { return }
            await withTaskGroup(of: Void.self) { group in
                var nextIndex = 0

                func enqueueNext() {
                    guard nextIndex < presetList.count else { return }
                    let preset = presetList[nextIndex]
                    nextIndex += 1

                    group.addTask {
                        guard !Task.isCancelled else { return }
                        do {
                            let cgImage = try await renderer(
                                url,
                                rotation,
                                preset,
                                compactPreviewMaxDimension
                            )
                            guard !Task.isCancelled else { return }
                            await self.store(
                                cgImage,
                                for: preset.id,
                                generation: requestGeneration
                            )
                        } catch {
                            // Silently fail — card shows placeholder
                        }
                    }
                }

                for _ in 0..<min(maxConcurrentPresetRenders, presetList.count) {
                    enqueueNext()
                }

                while await group.next() != nil {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    enqueueNext()
                }
            }
            finish(requestGeneration)
        }
        renderTask = task
        return task
    }

    private func store(_ image: CGImage, for presetID: UUID, generation: UInt64) {
        guard generation == self.generation else { return }
        previews[presetID] = UIImage(cgImage: image)
    }

    private func finish(_ requestGeneration: UInt64) {
        guard requestGeneration == generation else { return }
        renderTask = nil
    }
}
