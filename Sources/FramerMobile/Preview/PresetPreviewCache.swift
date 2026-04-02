import SwiftUI
import FramerCore

@MainActor
@Observable
final class PresetPreviewCache {
    var previews: [UUID: UIImage] = [:]
    private var renderTasks: [UUID: Task<Void, Never>] = [:]
    private let maxConcurrentPresetRenders = 4

    func clear() {
        for (_, task) in renderTasks { task.cancel() }
        renderTasks.removeAll()
        previews.removeAll()
    }

    func regenerate(for photo: PhotoItem, presets: [Preset]) {
        clear()

        let url = photo.url
        let rotation = photo.rotation
        let presetList = presets
        let compactPreviewMaxDimension = 320

        let task = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let processor = FrameProcessor()
            await withTaskGroup(of: Void.self) { group in
                var nextIndex = 0

                func enqueueNext() {
                    guard nextIndex < presetList.count else { return }
                    let preset = presetList[nextIndex]
                    nextIndex += 1

                    group.addTask {
                        guard !Task.isCancelled else { return }
                        do {
                            let cgImage = try await Task.detached {
                                try await processor.previewCGImage(
                                    for: url,
                                    config: preset.config,
                                    rotation: rotation,
                                    maxDimension: compactPreviewMaxDimension
                                )
                            }.value
                            guard !Task.isCancelled else { return }
                            let image = UIImage(cgImage: cgImage)
                            await MainActor.run {
                                self.previews[preset.id] = image
                            }
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
        }
        renderTasks[UUID()] = task
    }
}
