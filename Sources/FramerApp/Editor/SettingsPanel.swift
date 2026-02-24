import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState
    @State private var thicknessMode: ThicknessMode = .pixels
    @State private var fontSizeMode: FontSizeMode = .auto
    @State private var paperSizePreset: Int = 99

    private enum ThicknessMode: String, CaseIterable {
        case pixels = "px"
        case percent = "%"
    }

    private enum FontSizeMode: String, CaseIterable {
        case auto = "Auto"
        case custom = "Custom"
    }

    // Cached monospaced fonts — queried once
    private static let cachedMonospacedFonts: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
            .sorted()
    }()

    /// Font list that always includes the current selection to avoid invalid picker tag warnings.
    private var monospacedFontList: [String] {
        let current = appState.currentConfig.fontName
        if Self.cachedMonospacedFonts.contains(current) {
            return Self.cachedMonospacedFonts
        }
        return ([current] + Self.cachedMonospacedFonts).sorted()
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

                        if thicknessMode == .pixels {
                            sliderWithInput(
                                value: thicknessBinding,
                                range: 0...300,
                                step: 5,
                                suffix: "px"
                            )
                        } else {
                            sliderWithInput(
                                value: thicknessBinding,
                                range: 0...20,
                                step: 0.5,
                                suffix: "%"
                            )
                        }
                    }
                }

                Picker("Background", selection: $state.currentConfig.backgroundMode) {
                    Text("Solid Color").tag(BackgroundMode.color)
                    Text("Dominant Color").tag(BackgroundMode.dominant)
                    Text("Linear Gradient").tag(BackgroundMode.gradientLinear)
                    Text("Radial Gradient").tag(BackgroundMode.gradientRadial)
                }

                ColorPicker("Border Color", selection: colorBinding(for: \.borderColor))

                if appState.currentConfig.borderStyle == .solid {
                    LabeledContent("Padding") {
                        sliderWithInput(
                            value: intBinding(\.padding),
                            range: 0...400,
                            step: 10,
                            suffix: "px"
                        )
                    }
                }
            }

            // Print-specific controls
            if case .print = appState.currentConfig.borderStyle {
                Section("Print Format") {
                    Picker("Paper Size", selection: $paperSizePreset) {
                        Text("10x15 cm").tag(0)
                        Text("13x18 cm").tag(1)
                        Text("20x30 cm").tag(2)
                        Text("A4").tag(3)
                        Text("Custom").tag(99)
                    }
                    .onChange(of: paperSizePreset) { _, preset in
                        applyPaperSizePreset(preset)
                    }

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
                        sliderWithInput(
                            value: intBinding(\.outerPadding),
                            range: 0...200,
                            step: 5,
                            suffix: "px"
                        )
                    }

                    LabeledContent("Caption Padding") {
                        sliderWithInput(
                            value: intBinding(\.captionPadding),
                            range: 0...100,
                            step: 5,
                            suffix: "px"
                        )
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
                    ForEach(monospacedFontList, id: \.self) { name in
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
                        sliderWithInput(
                            value: Binding(
                                get: { Double(pts) },
                                set: { appState.currentConfig.fontSize = .fixed(Int($0)) }
                            ),
                            range: 8...120,
                            step: 1,
                            suffix: "pt"
                        )
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
            HStack {
                Button("Export Selected") {
                    promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
                }
                .disabled(appState.selectedItems.isEmpty)
                Spacer()
                Button("Export All") {
                    promptAndExport(appState.library)
                }
                .disabled(appState.library.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
        }
        .onChange(of: appState.currentConfig) { _, newConfig in
            switch newConfig.borderThickness {
            case .pixels: thicknessMode = .pixels
            case .percent: thicknessMode = .percent
            }
            switch newConfig.fontSize {
            case .auto: fontSizeMode = .auto
            case .fixed: fontSizeMode = .custom
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportSelected)) { _ in
            promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportAll)) { _ in
            promptAndExport(appState.library)
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

    /// Convenience binding for Int config properties used with Double sliders/text fields.
    private func intBinding(_ keyPath: WritableKeyPath<ProcessingConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(appState.currentConfig[keyPath: keyPath]) },
            set: { appState.currentConfig[keyPath: keyPath] = Int($0) }
        )
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

    private func applyPaperSizePreset(_ preset: Int) {
        guard case .print(var f) = appState.currentConfig.borderStyle else { return }
        switch preset {
        case 0: f.widthMM = 150; f.heightMM = 100
        case 1: f.widthMM = 180; f.heightMM = 130
        case 2: f.widthMM = 300; f.heightMM = 200
        case 3: f.widthMM = 297; f.heightMM = 210
        default: return // Custom — leave as-is
        }
        appState.currentConfig.borderStyle = .print(f)
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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
