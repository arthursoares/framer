import SwiftUI
import FramerCore

@MainActor
@Observable
final class PresetPreviewCache {
    var previews: [UUID: UIImage] = [:]
    private var renderTasks: [UUID: Task<Void, Never>] = [:]

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
            for preset in presetList {
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
                        previews[preset.id] = image
                    }
                } catch {
                    // Silently fail — card shows placeholder
                }
            }
        }
        renderTasks[UUID()] = task
    }
}
