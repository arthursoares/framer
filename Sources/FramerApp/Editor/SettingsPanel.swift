import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState
    @AppStorage("lastExportDirectory") private var lastExportDirectory: String = ""
    @State private var showingExportSheet = false
    @State private var pendingExportItems: [PhotoItem] = []
    @State private var selectedPresetIDs: Set<UUID> = []
    @State private var includeCurrentSettings = true

    var body: some View {
        @Bindable var state = appState

        Form {
            // Active preset indicator
            if let presetName = appState.activePresetName {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(presetName)
                        .font(.caption.bold())
                    Spacer()
                    Button {
                        appState.activePresetName = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Layer-based composition
            LayerListSection(layers: layersBinding)

            // Output
            Section("Output") {
                Picker("Format", selection: outputFormatBinding) {
                    Text("JPEG").tag("jpeg")
                    Text("PNG").tag("png")
                }

                if case .jpeg(let q) = appState.currentConfig.outputFormat {
                    LabeledContent("Quality") {
                        sliderWithInput(
                            value: Binding(
                                get: { Double(q) },
                                set: { appState.currentConfig.outputFormat = .jpeg(quality: Int($0)) }
                            ),
                            range: 60...100,
                            step: 5,
                            suffix: "%"
                        )
                    }
                }

                Toggle("Strip EXIF metadata", isOn: $state.currentConfig.noMetadata)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 260)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Button {
                        promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Selected")
                            if !appState.selectedItems.isEmpty {
                                Text("\(appState.selectedItems.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.secondary.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                    .disabled(appState.selectedItems.isEmpty)

                    Spacer()

                    Button {
                        promptAndExport(appState.library)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up.on.square")
                            Text("Export All")
                            if !appState.library.isEmpty {
                                Text("\(appState.library.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.secondary.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                    .disabled(appState.library.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .onAppear {
            ensureLayersInitialized()
        }
        .onChange(of: appState.currentConfig) { _, _ in
            // Re-derive layers when a preset is applied that has no explicit layers
            ensureLayersInitialized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportSelected)) { _ in
            promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportAll)) { _ in
            promptAndExport(appState.library)
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Export \(pendingExportItems.count) photo\(pendingExportItems.count == 1 ? "" : "s")")
                    .font(.headline)

                // Current settings toggle
                Toggle(isOn: $includeCurrentSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                        Text("Current Settings")
                        if let name = appState.activePresetName {
                            Text("(\(name))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !appState.presets.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Also export with presets:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(appState.presets) { preset in
                            Toggle(isOn: presetToggleBinding(preset.id)) {
                                Text(preset.name)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("Cancel") {
                    showingExportSheet = false
                    selectedPresetIDs.removeAll()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                let totalExports = (includeCurrentSettings ? 1 : 0) + selectedPresetIDs.count
                Button("Export\(totalExports > 1 ? " (\(totalExports) presets)" : "")") {
                    performExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(totalExports == 0)
            }
            .padding(20)
        }
        .frame(width: 340)
    }

    private func presetToggleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedPresetIDs.contains(id) },
            set: { enabled in
                if enabled { selectedPresetIDs.insert(id) }
                else { selectedPresetIDs.remove(id) }
            }
        )
    }

    private func performExport() {
        showingExportSheet = false
        let items = pendingExportItems
        guard !items.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        if !lastExportDirectory.isEmpty, let url = URL(string: lastExportDirectory) {
            panel.directoryURL = url
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        lastExportDirectory = dir.absoluteString

        // Export with current settings
        if includeCurrentSettings {
            appState.exportItems(items, to: dir)
        }

        // Export with selected presets
        let presetConfigs = appState.presets
            .filter { selectedPresetIDs.contains($0.id) }
            .map { (name: $0.name, config: $0.config) }

        if !presetConfigs.isEmpty {
            appState.exportItems(items, to: dir, withPresets: presetConfigs)
        }

        selectedPresetIDs.removeAll()
    }

    // MARK: - Layer Binding

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

    // MARK: - Slider + TextField Helper

    private func sliderWithInput(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String,
        width: CGFloat = 55
    ) -> some View {
        let snappedBinding = Binding<Double>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = (($0 / step).rounded() * step).clamped(to: range) }
        )
        return HStack {
            Slider(value: snappedBinding, in: range)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { appState.currentConfig.outputFormat == .png ? "png" : "jpeg" },
            set: { appState.currentConfig.outputFormat = $0 == "png" ? .png : .jpeg(quality: 100) }
        )
    }

    // MARK: - Export

    private func promptAndExport(_ items: [PhotoItem]) {
        guard !items.isEmpty else { return }
        if appState.presets.isEmpty {
            directExport(items)
        } else {
            pendingExportItems = items
            showingExportSheet = true
        }
    }

    /// Opens the folder picker immediately and exports using current settings, bypassing the
    /// preset-selection sheet. Used when no presets are saved.
    private func directExport(_ items: [PhotoItem]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        if !lastExportDirectory.isEmpty, let url = URL(string: lastExportDirectory) {
            panel.directoryURL = url
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        lastExportDirectory = dir.absoluteString
        appState.exportItems(items, to: dir)
    }
}

// MARK: - ColorPickerWithHex

struct ColorPickerWithHex: View {
    let label: String
    @Binding var selection: Color
    @State private var hexText: String = ""

    init(_ label: String, selection: Binding<Color>) {
        self.label = label
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker(label, selection: $selection)
            TextField("#HEX", text: $hexText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 80)
                .onSubmit {
                    applyHex()
                }
        }
        .onAppear { syncHexFromColor() }
        .onChange(of: selection) { _, _ in syncHexFromColor() }
    }

    private func syncHexFromColor() {
        if let hex = selection.hexString {
            hexText = hex
        }
    }

    private func applyHex() {
        let cleaned = hexText.trimmingCharacters(in: .whitespaces)
        guard let codable = try? CodableColor(hex: cleaned) else { return }
        if let nsColor = NSColor(cgColor: codable.cgColor) {
            selection = Color(nsColor: nsColor)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
