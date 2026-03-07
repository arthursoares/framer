import SwiftUI
import FramerCore

struct PresetManagerView: View {
    @Environment(AppState.self) var appState
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""
    @State private var presetToDelete: Preset?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                Button(action: { showingSaveSheet = true }) {
                    Label("Save Current", systemImage: "plus.circle")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if appState.presets.isEmpty {
                emptyState
            } else {
                presetGrid
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            savePresetSheet
        }
        .alert("Delete Preset?", isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { presetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    deletePreset(preset)
                }
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete \"\(preset.name)\"?")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No presets yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Configure your settings and save them as a preset.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var presetGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
            ], spacing: 16) {
                ForEach(appState.presets) { preset in
                    presetCard(preset)
                }
            }
            .padding()
        }
    }

    private func presetCard(_ preset: Preset) -> some View {
        Button {
            applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail or placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    if let data = preset.thumbnailData, let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info
                Text(preset.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    configChip(presetLayerSummary(preset.config))
                    configChip(presetOutputSummary(preset.config))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                applyPreset(preset)
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                presetToDelete = preset
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func presetLayerSummary(_ config: ProcessingConfig) -> String {
        if let layers = config.layers {
            return "\(layers.count) layer\(layers.count == 1 ? "" : "s")"
        }
        switch config.borderStyle {
        case .solid: return "Solid"
        case .instagram: return "Instagram"
        case .print: return "Print"
        }
    }

    private func presetOutputSummary(_ config: ProcessingConfig) -> String {
        switch config.outputFormat {
        case .jpeg(let q): return "JPEG \(q)%"
        case .png: return "PNG"
        }
    }

    @ViewBuilder
    private func configChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(.headline)

            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack {
                Button("Cancel") {
                    newPresetName = ""
                    showingSaveSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    savePreset()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    // MARK: - Actions

    private func applyPreset(_ preset: Preset) {
        appState.currentConfig = preset.config
        appState.activePresetName = preset.name
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let preset = Preset(name: name, config: appState.currentConfig)
        try? appState.presetStore.save(preset)
        appState.loadPresets()
        newPresetName = ""
        showingSaveSheet = false
    }

    private func deletePreset(_ preset: Preset) {
        try? appState.presetStore.delete(id: preset.id)
        appState.loadPresets()
        presetToDelete = nil
    }
}
