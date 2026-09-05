import SwiftUI
import AppKit
import FramerCore

struct CaptionLayerControls: View {
    var params: CaptionLayerParams
    var onChange: (CaptionLayerParams) -> Void

    @State private var fontSizeMode: FontSizeMode = .auto

    private enum FontSizeMode: String, CaseIterable {
        case auto = "Auto"
        case custom = "Custom"
    }

    init(params: CaptionLayerParams, onChange: @escaping (CaptionLayerParams) -> Void) {
        self.params = params
        self.onChange = onChange
        _fontSizeMode = State(initialValue: Self.fontSizeMode(for: params.fontSize))
    }

    private static let signedIntFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.allowsFloats = false
        return f
    }()

    private static let cachedMonospacedFonts: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
            .sorted()
    }()

    private var monospacedFontList: [String] {
        let current = params.fontName
        if Self.cachedMonospacedFonts.contains(current) {
            return Self.cachedMonospacedFonts
        }
        return ([current] + Self.cachedMonospacedFonts).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: captionModeIndex) {
                Text("Template").tag(0)
                Text("Custom").tag(1)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .denseControlRow("Mode")

            switch params.mode {
            case .template:
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    TextField("Template", text: captionTemplateText)
                        .font(.system(.body, design: .monospaced))
                        .denseControlRow("Template")
                } secondary: {
                    TemplateTokenBar(text: captionTemplateText)
                        .denseSupportingRow("Tokens")
                }
            case .custom:
                SimpleLayerEditorDivider()

                TextField("Caption text", text: captionCustomText)
                    .denseControlRow("Caption")
            case .none:
                EmptyView()
            }

            if captionEnabled {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    Picker("", selection: positionBinding) {
                        Text("Bottom").tag(CaptionPosition.bottom)
                        Text("Top").tag(CaptionPosition.top)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Position")
                } secondary: {
                    Picker("", selection: alignmentBinding) {
                        Text("Left").tag(CaptionAlignment.left)
                        Text("Center").tag(CaptionAlignment.center)
                        Text("Right").tag(CaptionAlignment.right)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Alignment")
                }

                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    DenseSliderControlRow(
                        title: "Offset X",
                        value: offsetXBinding,
                        range: -200...200,
                        step: 1,
                        unit: "px"
                    )
                } secondary: {
                    DenseSliderControlRow(
                        title: "Offset Y",
                        value: offsetYBinding,
                        range: -200...200,
                        step: 1,
                        unit: "px"
                    )
                }

                SimpleLayerEditorDivider()

                Picker("", selection: fontNameBinding) {
                    ForEach(monospacedFontList, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Font")

                SimpleLayerEditorDivider()

                HStack(spacing: 8) {
                    Toggle(isOn: fontStyleBinding(.bold)) {
                        Text("B").bold()
                    }
                    .toggleStyle(.button)

                    Toggle(isOn: fontStyleBinding(.italic)) {
                        Text("I").italic()
                    }
                    .toggleStyle(.button)
                }
                .denseControlRow("Style")

                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    Picker("", selection: $fontSizeMode) {
                        ForEach(FontSizeMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Size")
                    .onChange(of: fontSizeMode) { _, newValue in
                        var p = params
                        switch newValue {
                        case .auto:
                            p.fontSize = .auto
                        case .custom:
                            if case .auto = params.fontSize {
                                p.fontSize = .fixed(24)
                            }
                        }
                        onChange(p)
                    }
                } secondary: {
                    if case .fixed(let pts) = params.fontSize {
                        DenseSliderControlRow(
                            title: "Font Size",
                            value: fontSizeBinding(pts),
                            range: 8...120,
                            step: 1,
                            unit: "pt"
                        )
                    }
                }

                SimpleLayerEditorDivider()

                Picker("", selection: fontColorModeIndex) {
                    Text("Custom").tag(0)
                    Text("Dominant").tag(1)
                    Text("Invert").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Font Color")

                if case .fixed = params.fontColorMode {
                    SimpleLayerEditorDivider()

                    labeledColorPicker("Color", selection: fontColorBinding)
                }

                if case .dominant(let sat, let light) = params.fontColorMode {
                    SimpleLayerEditorDivider()

                    captionColorAdjustmentSliders(saturation: sat, lightness: light) { s, l in
                        var p = params
                        p.fontColorMode = .dominant(saturationShift: s, lightnessShift: l)
                        onChange(p)
                    }
                }

                if case .dominantInverted(let sat, let light) = params.fontColorMode {
                    SimpleLayerEditorDivider()

                    captionColorAdjustmentSliders(saturation: sat, lightness: light) { s, l in
                        var p = params
                        p.fontColorMode = .dominantInverted(saturationShift: s, lightnessShift: l)
                        onChange(p)
                    }
                }
            }
        }
        .onChange(of: params.fontSize) { _, newFontSize in
            fontSizeMode = Self.fontSizeMode(for: newFontSize)
        }
        .onAppear {
            // Migrate legacy `.none` captions to `.template` on first render so
            // the picker's selected value and the body's rendered content stay
            // in sync. Users disable a caption layer via the row's visibility
            // toggle, not by keeping it in `.none` mode.
            if case .none = params.mode {
                var p = params
                p.mode = .template(" - {{mon}} '{{year2}} -")
                onChange(p)
            }
        }
    }

    private static func fontSizeMode(for fontSize: FontSize) -> FontSizeMode {
        switch fontSize {
        case .auto:
            .auto
        case .fixed:
            .custom
        }
    }

    @ViewBuilder
    private func captionColorAdjustmentSliders(saturation: Double, lightness: Double, onChange: @escaping (Double, Double) -> Void) -> some View {
        SidebarCompoundControlBlock {
            DenseSliderControlRow(
                title: "Saturation",
                value: Binding(get: { saturation }, set: { onChange($0, lightness) }),
                range: -50...50,
                step: 1
            )
        } secondary: {
            DenseSliderControlRow(
                title: "Brightness",
                value: Binding(get: { lightness }, set: { onChange(saturation, $0) }),
                range: -50...50,
                step: 1
            )
        }
    }

    // MARK: - Helpers

    private var captionEnabled: Bool {
        if case .none = params.mode { return false }
        return true
    }

    // MARK: - Bindings

    private var captionModeIndex: Binding<Int> {
        Binding(
            get: {
                switch params.mode {
                case .template: 0
                case .custom: 1
                // Legacy `.none` layers (from older preset YAML) surface as
                // Template in the picker so users never see an empty
                // selection. The body below migrates them on first render
                // via `.onAppear`, and if the user interacts with the picker
                // they overwrite it either way. `.none` stays in the model
                // for preset back-compat but is no longer a user choice.
                case .none: 0
                }
            },
            set: { idx in
                var p = params
                switch idx {
                case 0:
                    if case .template = params.mode { return }
                    p.mode = .template(" - {{mon}} '{{year2}} -")
                case 1:
                    if case .custom = params.mode { return }
                    p.mode = .custom("")
                default:
                    return
                }
                onChange(p)
            }
        )
    }

    private var captionTemplateText: Binding<String> {
        Binding(
            get: {
                if case .template(let t) = params.mode { return t }
                return ""
            },
            set: {
                var p = params
                p.mode = .template($0)
                onChange(p)
            }
        )
    }

    private var captionCustomText: Binding<String> {
        Binding(
            get: {
                if case .custom(let s) = params.mode { return s }
                return ""
            },
            set: {
                var p = params
                p.mode = .custom($0)
                onChange(p)
            }
        )
    }

    private var positionBinding: Binding<CaptionPosition> {
        Binding(
            get: { params.position },
            set: {
                var p = params
                p.position = $0
                onChange(p)
            }
        )
    }

    private var alignmentBinding: Binding<CaptionAlignment> {
        Binding(
            get: { params.alignment },
            set: {
                var p = params
                p.alignment = $0
                onChange(p)
            }
        )
    }

    private var offsetXBinding: Binding<Double> {
        Binding(
            get: { Double(params.offsetX) },
            set: {
                var p = params
                p.offsetX = Int($0)
                onChange(p)
            }
        )
    }

    private var offsetYBinding: Binding<Double> {
        Binding(
            get: { Double(params.offsetY) },
            set: {
                var p = params
                p.offsetY = Int($0)
                onChange(p)
            }
        )
    }

    private var fontNameBinding: Binding<String> {
        Binding(
            get: { params.fontName },
            set: {
                var p = params
                p.fontName = $0
                onChange(p)
            }
        )
    }

    private func fontStyleBinding(_ trait: FontStyle) -> Binding<Bool> {
        Binding(
            get: { params.fontStyle.contains(trait) },
            set: { enabled in
                var p = params
                if enabled {
                    p.fontStyle.insert(trait)
                } else {
                    p.fontStyle.remove(trait)
                }
                onChange(p)
            }
        )
    }

    private func fontSizeBinding(_ currentPts: Int) -> Binding<Double> {
        Binding(
            get: { Double(currentPts) },
            set: {
                var p = params
                p.fontSize = .fixed(Int($0))
                onChange(p)
            }
        )
    }

    private var fontColorModeIndex: Binding<Int> {
        Binding(
            get: {
                switch params.fontColorMode {
                case .fixed: return 0
                case .dominant: return 1
                case .dominantInverted: return 2
                }
            },
            set: { idx in
                var p = params
                switch idx {
                case 1: p.fontColorMode = .dominant()
                case 2: p.fontColorMode = .dominantInverted()
                default: p.fontColorMode = .fixed(params.fontColor)
                }
                onChange(p)
            }
        )
    }

    private var fontColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: params.fontColor.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.fontColorMode = .fixed(c)
                onChange(p)
            }
        )
    }
}

// MARK: - TemplateTokenBar

private struct TemplateToken: Identifiable, Hashable {
    let id: String
    let token: String
    let label: String
    let category: Category

    enum Category: String, CaseIterable, Hashable {
        case camera = "Camera"
        case date = "Date"
    }

    static let all: [TemplateToken] = [
        // Camera
        TemplateToken(id: "camera", token: "{{camera}}", label: "Camera", category: .camera),
        TemplateToken(id: "lens", token: "{{lens}}", label: "Lens", category: .camera),
        TemplateToken(id: "iso", token: "{{iso}}", label: "ISO", category: .camera),
        TemplateToken(id: "aperture", token: "{{aperture}}", label: "Aperture", category: .camera),
        TemplateToken(id: "shutter", token: "{{shutter}}", label: "Shutter", category: .camera),
        TemplateToken(id: "focal", token: "{{focal}}", label: "Focal", category: .camera),
        // Date
        TemplateToken(id: "mon", token: "{{mon}}", label: "Mon", category: .date),
        TemplateToken(id: "month", token: "{{month}}", label: "Month", category: .date),
        TemplateToken(id: "day", token: "{{day}}", label: "Day", category: .date),
        TemplateToken(id: "year", token: "{{year}}", label: "Year", category: .date),
        TemplateToken(id: "year2", token: "{{year2}}", label: "YY", category: .date),
        TemplateToken(id: "date", token: "{{date}}", label: "Date", category: .date),
    ]
}

struct TemplateTokenBar: View {
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            ForEach(TemplateToken.Category.allCases, id: \.rawValue) { category in
                tokenRow(category)
            }
        }
    }

    private func tokenRow(_ category: TemplateToken.Category) -> some View {
        HStack(alignment: .top, spacing: metrics.expandedBodyInset) {
            Text(category.rawValue)
                .font(AppFont.body(10))
                .foregroundStyle(Color.text3)
                .frame(width: 48, alignment: .trailing)

            SidebarChipFlow(
                items: TemplateToken.all.filter { $0.category == category },
                spacing: metrics.expandedBodyInset - 2
            ) { token in
                Button {
                    text.append(token.token)
                } label: {
                    Text(token.label)
                        .font(AppFont.controlLabel)
                        .padding(.horizontal, metrics.expandedBodyInset)
                        .padding(.vertical, 2)
                        .background(Color.surface4, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Insert \(token.token)")
            }
        }
    }
}

