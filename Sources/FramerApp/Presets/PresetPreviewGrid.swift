import SwiftUI
import FramerCore

struct PresetPreviewGrid: View {
    @Environment(AppState.self) var appState
    @State private var presetPreviews: [UUID: NSImage] = [:]
    @State private var renderTasks: [UUID: Task<Void, Never>] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(appState.presets) { preset in
                PresetPreviewCard(
                    preset: preset,
                    isActive: appState.activePresetName == preset.name,
                    thumbnail: presetPreviews[preset.id],
                    onTap: {
                        appState.currentConfig = preset.config
                        appState.activePresetName = preset.name
                    }
                )
                .contextMenu {
                    Button {
                        appState.currentConfig = preset.config
                        appState.activePresetName = preset.name
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                    Button {
                        let updated = Preset(id: preset.id, name: preset.name, config: appState.currentConfig)
                        try? appState.presetStore.save(updated)
                        appState.loadPresets()
                        appState.activePresetName = preset.name
                    } label: {
                        Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Divider()
                    Button(role: .destructive) {
                        try? appState.presetStore.delete(id: preset.id)
                        appState.loadPresets()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // Save card
            saveCard
        }
        .onChange(of: appState.selectedPhoto?.id) { _, _ in
            schedulePreviewRenders()
        }
        .onAppear {
            schedulePreviewRenders()
        }
    }

    private var saveCard: some View {
        Button(action: saveCurrentAsPreset) {
            VStack(spacing: 0) {
                ZStack {
                    Color.clear
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.text3)
                        Text("Save")
                            .font(AppFont.templateToken)
                            .foregroundStyle(Color.text3)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)

                Color.clear.frame(height: 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(Color.text3, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview Rendering

    private func schedulePreviewRenders() {
        // Cancel all in-flight renders
        for (_, task) in renderTasks { task.cancel() }
        renderTasks.removeAll()
        presetPreviews.removeAll()

        guard let photo = appState.selectedPhoto else { return }

        let presets = appState.presets
        let url = photo.url
        let rotation = photo.rotation

        for preset in presets {
            let presetID = preset.id
            let config = preset.config

            let task = Task {
                // Debounce
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }

                let processor = FrameProcessor()
                do {
                    let preview = try await Task.detached {
                        try await processor.previewImage(for: url, config: config, rotation: rotation)
                    }.value
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        presetPreviews[presetID] = preview
                    }
                } catch {
                    // Silently fail — card shows placeholder
                }
            }
            renderTasks[presetID] = task
        }
    }

    // MARK: - Save Preset

    private func saveCurrentAsPreset() {
        let baseName = "Preset"
        let existingNames = Set(appState.presets.map(\.name))
        var name = baseName
        var counter = 1
        while existingNames.contains(name) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        let preset = Preset(name: name, config: appState.currentConfig)
        try? appState.presetStore.save(preset)
        appState.loadPresets()
        appState.activePresetName = preset.name
    }
}
