import SwiftUI
import FramerCore

struct InspectorView: View {
    @Environment(AppState.self) var appState
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""
    @State private var presetToDelete: Preset?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Active preset banner
                    if let presetName = appState.activePresetName {
                        activePresetBanner(presetName)
                    }

                    // Presets section
                    presetsSection

                    // Layers section
                    layersSection

                    // Output section
                    outputSection
                }
                .padding(12)
            }

            ExportBar()
        }
        .frame(width: 280)
        .background(Color.surface1)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.borderDefault).frame(width: 1)
        }
        .onAppear { ensureLayersInitialized() }
        .onChange(of: appState.currentConfig.layers == nil) { _, layersAreNil in
            if layersAreNil { ensureLayersInitialized() }
        }
        .sheet(isPresented: $showingSaveSheet) { savePresetSheet }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "Unknown error")
        }
        .alert("Delete Preset?", isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { presetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    try? appState.presetStore.delete(id: preset.id)
                    appState.loadPresets()
                    presetToDelete = nil
                }
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete \"\(preset.name)\"?")
            }
        }
    }

    // MARK: - Active Preset Banner

    private func activePresetBanner(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(Color.accent)
            Text(name)
                .font(AppFont.body(11, weight: .semibold))
                .foregroundStyle(Color.accent)
            Spacer()
            Button {
                appState.activePresetName = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.accentGlow, in: RoundedRectangle(cornerRadius: CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.accent.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)

            if appState.presets.isEmpty {
                Text("No presets yet")
                    .font(AppFont.body(11))
                    .foregroundStyle(Color.text3)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.presets) { preset in
                    presetRow(preset)
                }
            }

            Button(action: { showingSaveSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                    Text("Save Current Settings")
                        .font(AppFont.body(11))
                }
                .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        Button {
            appState.currentConfig = preset.config
            appState.activePresetName = preset.name
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.text3)
                    .frame(width: 14)
                Text(preset.name)
                    .font(AppFont.layerName)
                    .foregroundStyle(Color.text0)
                    .lineLimit(1)
                Spacer()
                if appState.activePresetName == preset.name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                appState.activePresetName == preset.name
                    ? Color.accentGlow
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: CornerRadius.sm)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                appState.currentConfig = preset.config
                appState.activePresetName = preset.name
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
            }
            Button {
                let updated = Preset(id: preset.id, name: preset.name, config: appState.currentConfig)
                do {
                    try appState.presetStore.save(updated)
                    appState.loadPresets()
                    appState.activePresetName = preset.name
                } catch {
                    saveError = error.localizedDescription
                }
            } label: {
                Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive) {
                presetToDelete = preset
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Layers Section

    private var layersSection: some View {
        LayerListSection(layers: layersBinding)
    }

    private var layersBinding: Binding<[CompositionLayer]> {
        Binding(
            get: { appState.currentConfig.layers ?? CompositionLayer.defaultLayers() },
            set: { appState.currentConfig.layers = $0 }
        )
    }

    private func ensureLayersInitialized() {
        if appState.currentConfig.layers == nil {
            appState.currentConfig.layers = CompositionLayer.defaultLayers()
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUT")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)

            // Format picker
            HStack {
                Text("Format")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                FormatPicker(selection: outputFormatBinding)
            }

            // Quality slider (JPEG only)
            if case .jpeg(let q) = appState.currentConfig.outputFormat {
                HStack {
                    Text("Quality")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    Spacer()
                    StyledSlider(
                        value: Binding(
                            get: { Double(q) },
                            set: { appState.currentConfig.outputFormat = .jpeg(quality: Int($0)) }
                        ),
                        range: 60...100,
                        step: 5,
                        suffix: "%"
                    )
                    .frame(maxWidth: 180)
                }
            }

            // Strip EXIF toggle
            HStack {
                Text("Strip EXIF metadata")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                StyledToggle(isOn: Binding(
                    get: { appState.currentConfig.noMetadata },
                    set: { appState.currentConfig.noMetadata = $0 }
                ))
            }
        }
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { appState.currentConfig.outputFormat == .png ? "png" : "jpeg" },
            set: { appState.currentConfig.outputFormat = $0 == "png" ? .png : .jpeg(quality: 100) }
        )
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(AppFont.body(14, weight: .semibold))
                .foregroundStyle(Color.text0)

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
                    let name = newPresetName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let preset = Preset(name: name, config: appState.currentConfig)
                    do {
                        try appState.presetStore.save(preset)
                        appState.loadPresets()
                        appState.activePresetName = preset.name
                        newPresetName = ""
                        showingSaveSheet = false
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }
}
