import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState

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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
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
