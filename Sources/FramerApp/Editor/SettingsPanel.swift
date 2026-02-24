import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState
    @State private var thicknessMode: ThicknessMode = .pixels
    @State private var fontSizeMode: FontSizeMode = .auto

    private enum ThicknessMode: String, CaseIterable {
        case pixels = "px"
        case percent = "%"
    }

    private enum FontSizeMode: String, CaseIterable {
        case auto = "Auto"
        case custom = "Custom"
    }

    var body: some View {
        @Bindable var state = appState

        Form {
            // Border
            Section("Border") {
                Picker("Style", selection: borderStylePickerBinding) {
                    Text("Solid").tag(0)
                    Text("Instagram (4:5)").tag(1)
                    Text("Print").tag(2)
                }
                .pickerStyle(.segmented)

                LabeledContent("Thickness") {
                    VStack(spacing: 4) {
                        Picker("", selection: $thicknessMode) {
                            ForEach(ThicknessMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                        .labelsHidden()

                        HStack {
                            Slider(
                                value: thicknessBinding,
                                in: thicknessMode == .pixels ? 0...300 : 0...20,
                                step: thicknessMode == .pixels ? 5 : 0.5
                            )
                            Text(thicknessLabel)
                                .monospacedDigit()
                                .frame(width: 55)
                        }
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

            // Print-specific controls
            if case .print = appState.currentConfig.borderStyle {
                Section("Print Format") {
                    HStack {
                        LabeledContent("Width (mm)") {
                            TextField("", value: printWidthBinding, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Height (mm)") {
                            TextField("", value: printHeightBinding, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    LabeledContent("DPI") {
                        TextField("", value: printDPIBinding, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                    }

                    ColorPicker("Background", selection: colorBinding(for: \.backgroundColor))

                    LabeledContent("Outer Padding") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(appState.currentConfig.outerPadding) },
                                    set: { appState.currentConfig.outerPadding = Int($0) }
                                ),
                                in: 0...200,
                                step: 5
                            )
                            Text("\(appState.currentConfig.outerPadding)px")
                                .monospacedDigit()
                                .frame(width: 55)
                        }
                    }

                    LabeledContent("Caption Padding") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(appState.currentConfig.captionPadding) },
                                    set: { appState.currentConfig.captionPadding = Int($0) }
                                ),
                                in: 0...100,
                                step: 5
                            )
                            Text("\(appState.currentConfig.captionPadding)px")
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
                        .help("Use {{camera}}, {{lens}}, {{iso}}, {{aperture}}, {{shutter}}, {{focal}}, {{mon}}, {{month}}, {{date}}, {{year2}}")
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

                Picker("Size", selection: $fontSizeMode) {
                    ForEach(FontSizeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: fontSizeMode) { _, newValue in
                    switch newValue {
                    case .auto:
                        appState.currentConfig.fontSize = .auto
                    case .custom:
                        if case .auto = appState.currentConfig.fontSize {
                            appState.currentConfig.fontSize = .fixed(24)
                        }
                    }
                }

                if case .fixed(let pts) = appState.currentConfig.fontSize {
                    LabeledContent("Font Size") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(pts) },
                                    set: { appState.currentConfig.fontSize = .fixed(Int($0)) }
                                ),
                                in: 8...120,
                                step: 1
                            )
                            Text("\(pts)pt")
                                .monospacedDigit()
                                .frame(width: 45)
                        }
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
        .onAppear {
            // Sync local state with config
            switch appState.currentConfig.borderThickness {
            case .pixels: thicknessMode = .pixels
            case .percent: thicknessMode = .percent
            }
            switch appState.currentConfig.fontSize {
            case .auto: fontSizeMode = .auto
            case .fixed: fontSizeMode = .custom
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportSelected)) { _ in
            let items = appState.library.filter { appState.selectedItems.contains($0.id) }
            exportItems(items)
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportAll)) { _ in
            exportItems(appState.library)
        }
    }

    // MARK: - Border Style Binding

    private var borderStylePickerBinding: Binding<Int> {
        Binding(
            get: {
                switch appState.currentConfig.borderStyle {
                case .solid: 0
                case .instagram: 1
                case .print: 2
                }
            },
            set: { idx in
                switch idx {
                case 0: appState.currentConfig.borderStyle = .solid
                case 1: appState.currentConfig.borderStyle = .instagram
                case 2:
                    if case .print = appState.currentConfig.borderStyle { return }
                    appState.currentConfig.borderStyle = .print(.print10x15)
                default: break
                }
            }
        )
    }

    // MARK: - Print Format Bindings

    private var printWidthBinding: Binding<Double> {
        Binding(
            get: {
                if case .print(let f) = appState.currentConfig.borderStyle { return f.widthMM }
                return 148
            },
            set: { val in
                if case .print(var f) = appState.currentConfig.borderStyle {
                    f.widthMM = val
                    appState.currentConfig.borderStyle = .print(f)
                }
            }
        )
    }

    private var printHeightBinding: Binding<Double> {
        Binding(
            get: {
                if case .print(let f) = appState.currentConfig.borderStyle { return f.heightMM }
                return 100
            },
            set: { val in
                if case .print(var f) = appState.currentConfig.borderStyle {
                    f.heightMM = val
                    appState.currentConfig.borderStyle = .print(f)
                }
            }
        )
    }

    private var printDPIBinding: Binding<Int> {
        Binding(
            get: {
                if case .print(let f) = appState.currentConfig.borderStyle { return f.dpi }
                return 300
            },
            set: { val in
                if case .print(var f) = appState.currentConfig.borderStyle {
                    f.dpi = val
                    appState.currentConfig.borderStyle = .print(f)
                }
            }
        )
    }

    // MARK: - Thickness Bindings

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: {
                switch appState.currentConfig.borderThickness {
                case .pixels(let px): Double(px)
                case .percent(let p): p
                }
            },
            set: { val in
                switch thicknessMode {
                case .pixels:
                    appState.currentConfig.borderThickness = .pixels(Int(val))
                case .percent:
                    appState.currentConfig.borderThickness = .percent(val)
                }
            }
        )
    }

    private var thicknessLabel: String {
        switch appState.currentConfig.borderThickness {
        case .pixels(let px): "\(px)px"
        case .percent(let p): "\(String(format: "%.1f", p))%"
        }
    }

    // MARK: - Caption Bindings

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
                let suffix: String
                switch config.borderStyle {
                case .solid: suffix = "_solid"
                case .instagram: suffix = "_instagram"
                case .print: suffix = "_print"
                }
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
