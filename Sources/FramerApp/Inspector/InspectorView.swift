import SwiftUI
import FramerCore

struct InspectorView: View {
    @Environment(AppState.self) var appState

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

            PresetPreviewGrid()
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


}
