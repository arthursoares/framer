import SwiftUI
import FramerCore

struct PresetPreviewGrid: View {
    @Environment(AppState.self) var appState
    @State private var presetPreviews: [UUID: NSImage] = [:]
    @State private var renderTasks: [UUID: Task<Void, Never>] = [:]
    @State private var renamingPreset: Preset?
    @State private var renameText = ""

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
                    thumbnail: appState.selectedPhoto != nil ? presetPreviews[preset.id] : nil,
                    onTap: {
                        appState.currentConfig = preset.config
                        appState.activePresetName = preset.name
                        appState.appliedPresetConfig = preset.config
                    }
                )
                .contextMenu {
                    Button {
                        appState.currentConfig = preset.config
                        appState.activePresetName = preset.name
                        appState.appliedPresetConfig = preset.config
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                    Button {
                        let updated = Preset(id: preset.id, name: preset.name, config: appState.currentConfig)
                        try? appState.presetStore.save(updated)
                        appState.loadPresets()
                        appState.activePresetName = preset.name
                        appState.appliedPresetConfig = appState.currentConfig
                    } label: {
                        Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        renameText = preset.name
                        renamingPreset = preset
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        exportPreset(preset)
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
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
        // Preset management row
        HStack(spacing: 8) {
            Button { importPresets() } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text3)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { showInFinder() } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text3)
            }
            .buttonStyle(.plain)
        }

        .onChange(of: appState.selectedPhoto?.id) { _, _ in
            schedulePreviewRenders()
        }
        .onAppear {
            schedulePreviewRenders()
        }
        .alert("Rename Preset", isPresented: Binding(
            get: { renamingPreset != nil },
            set: { if !$0 { renamingPreset = nil } }
        )) {
            TextField("Preset name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingPreset = nil }
            Button("Rename") {
                if let preset = renamingPreset, !renameText.isEmpty {
                    let updated = Preset(id: preset.id, name: renameText, config: preset.config)
                    try? appState.presetStore.save(updated)
                    if appState.activePresetName == preset.name {
                        appState.activePresetName = renameText
                    }
                    appState.loadPresets()
                }
                renamingPreset = nil
            }
        } message: {
            Text("Enter a new name for this preset.")
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
                .aspectRatio(1, contentMode: .fit)

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
                    let cgImage = try await Task.detached {
                        try await processor.previewCGImage(for: url, config: config, rotation: rotation)
                    }.value
                    guard !Task.isCancelled else { return }

                    // Size in points (not pixels) — divide by screen scale so
                    // SwiftUI renders at the correct dimensions on Retina displays.
                    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                    let preview = NSImage(cgImage: cgImage, size: NSSize(
                        width: CGFloat(cgImage.width) / scale,
                        height: CGFloat(cgImage.height) / scale
                    ))
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
        appState.appliedPresetConfig = preset.config
    }

    // MARK: - Import / Export

    private func exportPreset(_ preset: Preset) {
        guard let data = try? appState.presetStore.exportData(for: preset) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).framerpreset"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Select .framerpreset or .json files to import"
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let data = try? Data(contentsOf: url) {
                    try? appState.presetStore.importData(data)
                }
            }
            appState.loadPresets()
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.open(appState.presetStore.storageDirectory)
    }
}
