import SwiftUI
import FramerCore

enum InspectorOutputControlState {
    static func formatSelection(for outputFormat: OutputFormat) -> String {
        outputFormat == .png ? "png" : "jpeg"
    }

    static func applyFormatSelection(_ selection: String, to config: inout ProcessingConfig) {
        config.outputFormat = selection == "png" ? .png : .jpeg(quality: 100)
    }

    static func jpegQuality(for outputFormat: OutputFormat) -> Double? {
        guard case .jpeg(let quality) = outputFormat else {
            return nil
        }

        return Double(quality)
    }

    static func setJPEGQuality(_ quality: Double, on config: inout ProcessingConfig) {
        config.outputFormat = .jpeg(quality: Int(quality))
    }
}

struct InspectorView: View {
    @Environment(AppState.self) var appState
    @AppStorage("sidebarPresetsSectionExpanded") private var presetsExpanded: Bool = true

    var body: some View {
        SidebarShell {
            VStack(alignment: .leading, spacing: 16) {
                // Presets section (collapsible; collapsed state shows the
                // active preset banner inline if one is applied)
                presetsSection

                // Layers section
                layersSection

                // Output section
                outputSection
            }
        } footer: {
            ExportBar()
        }
        .onAppear { ensureLayersInitialized() }
        .onChange(of: appState.currentConfig.layers == nil) { _, layersAreNil in
            if layersAreNil { ensureLayersInitialized() }
        }
    }

    // MARK: - Active Preset Summary (shown when section is collapsed)

    @ViewBuilder
    private func activePresetSummary(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(Color.accent)
            Text(name)
                .font(AppFont.body(11, weight: .semibold))
                .foregroundStyle(Color.accent)
            if appState.isPresetModified {
                Text("Modified")
                    .font(AppFont.body(9, weight: .medium))
                    .foregroundStyle(Color.text2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.surface3, in: Capsule())
            }
            Spacer()
            Button {
                appState.activePresetName = nil
                appState.appliedPresetConfig = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear active preset")
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
        CollapsibleSidebarSection(
            "PRESETS",
            isExpanded: $presetsExpanded
        ) {
            PresetPreviewGrid()
        } collapsedContent: {
            if let presetName = appState.activePresetName {
                activePresetSummary(presetName)
            }
        }
    }

    // MARK: - Layers Section

    private var layersSection: some View {
        // Header-less section — `LayerListSection` owns its "LAYERS (n)"
        // eyebrow internally rather than surfacing it through
        // `SidebarSection`'s Header slot. `expandedBodyInset: 0` tightens
        // the section's internal spacing so the layer row rhythm isn't
        // double-padded.
        SidebarSection(metrics: SidebarMetrics(expandedBodyInset: 0)) {
            LayerListSection(layers: layersBinding)
        }
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
        SidebarSection("OUTPUT") {
            SidebarCompoundControlBlock {
                SidebarControlRow("Format") {
                    FormatPicker(selection: outputFormatBinding)
                }
            } secondary: {
                if jpegQuality != nil {
                    SidebarControlRow("Quality") {
                        Slider(value: jpegQualityBinding, in: 60...100, step: 5)
                            .tint(Color.accentDim)
                            .accessibilityLabel(Text("Quality"))
                    } trailingValue: {
                        SidebarTrailingUnitCluster(unit: "%") {
                            TextField("", value: jpegQualityBinding, format: .number)
                                .textFieldStyle(.plain)
                                .font(AppFont.numericInput)
                                .foregroundStyle(Color.text1)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .stroke(Color.borderDefault, lineWidth: 1)
                                )
                                .monospacedDigit()
                                .accessibilityLabel(Text("Quality"))
                        }
                    }
                }
            }

            SidebarControlRow("Strip EXIF metadata") {
                EmptyView()
            } trailingValue: {
                StyledToggle(isOn: noMetadataBinding)
                    .padding(.trailing, 1)
            }
        }
    }

    private var jpegQuality: Double? {
        InspectorOutputControlState.jpegQuality(for: appState.currentConfig.outputFormat)
    }

    private var jpegQualityBinding: Binding<Double> {
        Binding(
            get: { jpegQuality ?? 100 },
            set: { InspectorOutputControlState.setJPEGQuality($0, on: &appState.currentConfig) }
        )
    }

    private var noMetadataBinding: Binding<Bool> {
        Binding(
            get: { appState.currentConfig.noMetadata },
            set: { appState.currentConfig.noMetadata = $0 }
        )
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { InspectorOutputControlState.formatSelection(for: appState.currentConfig.outputFormat) },
            set: { InspectorOutputControlState.applyFormatSelection($0, to: &appState.currentConfig) }
        )
    }
}
