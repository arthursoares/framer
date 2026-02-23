import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            // Border
            Section("Border") {
                Picker("Style", selection: $state.currentConfig.borderStyle) {
                    Text("Solid").tag(BorderStyle.solid)
                    Text("Instagram (4:5)").tag(BorderStyle.instagram)
                }
                .pickerStyle(.segmented)

                LabeledContent("Thickness") {
                    HStack {
                        Slider(
                            value: thicknessBinding,
                            in: 0...300,
                            step: 5
                        )
                        Text(thicknessLabel)
                            .monospacedDigit()
                            .frame(width: 55)
                    }
                }

                ColorPicker("Border Color", selection: colorBinding(for: \.borderColor))

                if appState.currentConfig.borderStyle == .solid {
                    LabeledContent("Padding") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(appState.currentConfig.padding) },
                                    set: { appState.currentConfig.padding = Int($0) }
                                ),
                                in: 0...400,
                                step: 10
                            )
                            Text("\(appState.currentConfig.padding)px")
                                .monospacedDigit()
                                .frame(width: 55)
                        }
                    }
                }
            }

            // Caption
            Section("Caption") {
                Picker("Mode", selection: captionModeIndex) {
                    Text("Template").tag(0)
                    Text("Custom").tag(1)
                    Text("None").tag(2)
                }
                .pickerStyle(.segmented)

                switch appState.currentConfig.captionMode {
                case .template:
                    TextField("Template", text: captionTemplateText)
                        .font(.system(.body, design: .monospaced))
                        .help("Use {{camera}}, {{lens}}, {{iso}}, {{aperture}}, {{shutter}}, {{focal}}, {{mon}}, {{year2}}")
                case .custom:
                    TextField("Caption text", text: captionCustomText)
                case .none:
                    EmptyView()
                }
            }

            // Font
            Section("Font") {
                Picker("Font", selection: $state.currentConfig.fontName) {
                    ForEach(availableMonospacedFonts(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                ColorPicker("Font Color", selection: colorBinding(for: \.fontColor))
            }

            // Output
            Section("Output") {
                Picker("Format", selection: outputFormatBinding) {
                    Text("JPEG").tag("jpeg")
                    Text("PNG").tag("png")
                }

                if case .jpeg(let q) = appState.currentConfig.outputFormat {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(q) },
                                    set: { appState.currentConfig.outputFormat = .jpeg(quality: Int($0)) }
                                ),
                                in: 60...100,
                                step: 5
                            )
                            Text("\(q)%")
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                    }
                }
            }

            // Actions
            Section {
                HStack {
                    Button("Export Selected") {
                        NotificationCenter.default.post(name: .framerExportSelected, object: nil)
                    }
                    .disabled(appState.selectedItems.isEmpty)

                    Button("Export All") {
                        NotificationCenter.default.post(name: .framerExportAll, object: nil)
                    }
                    .disabled(appState.library.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 260)
        .onReceive(NotificationCenter.default.publisher(for: .framerExportSelected)) { _ in
            let items = appState.library.filter { appState.selectedItems.contains($0.id) }
            exportItems(items)
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportAll)) { _ in
            exportItems(appState.library)
        }
    }

    // MARK: - Bindings

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: {
                switch appState.currentConfig.borderThickness {
                case .pixels(let px): Double(px)
                case .percent(let p): p * 10
                }
            },
            set: { appState.currentConfig.borderThickness = .pixels(Int($0)) }
        )
    }

    private var thicknessLabel: String {
        switch appState.currentConfig.borderThickness {
        case .pixels(let px): "\(px)px"
        case .percent(let p): "\(String(format: "%.1f", p))%"
        }
    }

    private var captionModeIndex: Binding<Int> {
        Binding(
            get: {
                switch appState.currentConfig.captionMode {
                case .template: 0
                case .custom: 1
                case .none: 2
                }
            },
            set: { idx in
                switch idx {
                case 0:
                    if case .template = appState.currentConfig.captionMode { return }
                    appState.currentConfig.captionMode = .template(" - {{mon}} '{{year2}} -")
                case 1:
                    if case .custom = appState.currentConfig.captionMode { return }
                    appState.currentConfig.captionMode = .custom("")
                default:
                    appState.currentConfig.captionMode = .none
                }
            }
        )
    }

    private var captionTemplateText: Binding<String> {
        Binding(
            get: {
                if case .template(let t) = appState.currentConfig.captionMode { return t }
                return ""
            },
            set: { appState.currentConfig.captionMode = .template($0) }
        )
    }

    private var captionCustomText: Binding<String> {
        Binding(
            get: {
                if case .custom(let s) = appState.currentConfig.captionMode { return s }
                return ""
            },
            set: { appState.currentConfig.captionMode = .custom($0) }
        )
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { appState.currentConfig.outputFormat == .png ? "png" : "jpeg" },
            set: { appState.currentConfig.outputFormat = $0 == "png" ? .png : .jpeg(quality: 100) }
        )
    }

    private func colorBinding(for keyPath: WritableKeyPath<ProcessingConfig, CodableColor>) -> Binding<Color> {
        Binding(
            get: {
                let c = appState.currentConfig[keyPath: keyPath]
                return Color(nsColor: NSColor(cgColor: c.cgColor) ?? .white)
            },
            set: { newColor in
                if let cgColor = NSColor(newColor).cgColor.converted(
                    to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
                   let comps = cgColor.components, comps.count >= 3 {
                    let r = Int(comps[0] * 255)
                    let g = Int(comps[1] * 255)
                    let b = Int(comps[2] * 255)
                    let hex = String(format: "#%02X%02X%02X", r, g, b)
                    if let color = try? CodableColor(hex: hex) {
                        appState.currentConfig[keyPath: keyPath] = color
                    }
                }
            }
        )
    }

    private func availableMonospacedFonts() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
            .sorted()
    }

    // MARK: - Export

    private func exportItems(_ items: [PhotoItem]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        var job = ExportJob(items: items, config: appState.currentConfig, outputDirectory: dir)
        job.status = .running
        appState.exportQueue.append(job)
        appState.activeTab = .queue

        let jobId = job.id
        let config = appState.currentConfig

        Task {
            let processor = FrameProcessor()
            for (i, item) in items.enumerated() {
                let ext: String = config.outputFormat == .png ? "png" : "jpg"
                let stem = item.url.deletingPathExtension().lastPathComponent
                let suffix = config.borderStyle == .instagram ? "_instagram" : "_solid"
                let outURL = dir.appendingPathComponent("\(stem)\(suffix).\(ext)")
                try? await processor.process(input: item.url, output: outURL, config: config)

                await MainActor.run {
                    if let idx = appState.exportQueue.firstIndex(where: { $0.id == jobId }) {
                        appState.exportQueue[idx].completedCount = i + 1
                        appState.exportQueue[idx].progress = Double(i + 1) / Double(items.count)
                    }
                }
            }
            await MainActor.run {
                if let idx = appState.exportQueue.firstIndex(where: { $0.id == jobId }) {
                    appState.exportQueue[idx].status = .done
                }
            }
        }
    }
}
