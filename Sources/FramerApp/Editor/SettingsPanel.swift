import SwiftUI
import FramerCore

struct SettingsPanel: View {
    @Environment(AppState.self) var appState
    @State private var fontSizeMode: FontSizeMode = .auto

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
            // Layer-based composition
            LayerListSection(layers: layersBinding)

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
                    TemplateTokenBar(text: captionTemplateText)
                case .custom:
                    TextField("Caption text", text: captionCustomText)
                case .none:
                    EmptyView()
                }

                if captionEnabled {
                    Picker("Position", selection: $state.currentConfig.captionPosition) {
                        Text("Bottom").tag(CaptionPosition.bottom)
                        Text("Top").tag(CaptionPosition.top)
                    }
                    .pickerStyle(.segmented)

                    Picker("Alignment", selection: $state.currentConfig.captionAlignment) {
                        Text("Left").tag(CaptionAlignment.left)
                        Text("Center").tag(CaptionAlignment.center)
                        Text("Right").tag(CaptionAlignment.right)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Offset X") {
                        sliderWithInput(
                            value: intBinding(\.captionOffsetX),
                            range: -200...200,
                            step: 5,
                            suffix: "px"
                        )
                    }

                    LabeledContent("Offset Y") {
                        sliderWithInput(
                            value: intBinding(\.captionOffsetY),
                            range: -200...200,
                            step: 5,
                            suffix: "px"
                        )
                    }
                }
            }

            // Font
            Section("Font") {
                Picker("Font", selection: $state.currentConfig.fontName) {
                    ForEach(monospacedFontList, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                HStack(spacing: 8) {
                    Text("Style")
                    Spacer()
                    Toggle(isOn: fontStyleBinding(.bold)) {
                        Text("B").bold()
                    }
                    .toggleStyle(.button)

                    Toggle(isOn: fontStyleBinding(.italic)) {
                        Text("I").italic()
                    }
                    .toggleStyle(.button)
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

                ColorPickerWithHex("Font Color", selection: colorBinding(for: \.fontColor))
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
                                    .background(.white.opacity(0.2), in: Capsule())
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
        .onChange(of: appState.currentConfig) { _, newConfig in
            switch newConfig.fontSize {
            case .auto: fontSizeMode = .auto
            case .fixed: fontSizeMode = .custom
            }
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

    private var captionEnabled: Bool {
        if case .none = appState.currentConfig.captionMode { return false }
        return true
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
            appState.currentConfig.layers = CompositionLayer.fromLegacyConfig(appState.currentConfig)
        }
    }

    /// Convenience binding for Int config properties used with Double sliders/text fields.
    private func intBinding(_ keyPath: WritableKeyPath<ProcessingConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(appState.currentConfig[keyPath: keyPath]) },
            set: { appState.currentConfig[keyPath: keyPath] = Int($0) }
        )
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

    private func fontStyleBinding(_ trait: FontStyle) -> Binding<Bool> {
        Binding(
            get: { appState.currentConfig.fontStyle.contains(trait) },
            set: { enabled in
                if enabled {
                    appState.currentConfig.fontStyle.insert(trait)
                } else {
                    appState.currentConfig.fontStyle.remove(trait)
                }
            }
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

// MARK: - TemplateTokenBar

private struct TemplateToken: Identifiable {
    let id: String
    let token: String
    let label: String
    let category: Category

    enum Category: String, CaseIterable {
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
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TemplateToken.Category.allCases, id: \.rawValue) { category in
                tokenRow(category)
            }
        }
    }

    private func tokenRow(_ category: TemplateToken.Category) -> some View {
        HStack(spacing: 4) {
            Text(category.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .trailing)

            FlowLayout(spacing: 4) {
                ForEach(TemplateToken.all.filter { $0.category == category }) { token in
                    Button {
                        text.append(token.token)
                    } label: {
                        Text(token.label)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Insert \(token.token)")
                }
            }
        }
    }
}

/// Simple horizontal flow layout for wrapping token chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), origins)
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
