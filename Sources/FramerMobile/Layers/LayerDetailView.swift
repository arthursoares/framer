import SwiftUI
import FramerCore

struct LayerDetailView: View {
    @Environment(AppState.self) var appState
    @Binding var layer: CompositionLayer
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var miniPreview: UIImage?
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Mini live preview
                ZStack {
                    Color.surface1
                    if let miniPreview {
                        Image(uiImage: miniPreview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    } else if appState.selectedPhoto != nil {
                        ProgressView()
                            .tint(Color.text3)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .padding(.horizontal, 16)

                // Layer header
                HStack(spacing: 12) {
                    Image(systemName: layer.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accent)
                        .frame(width: 36, height: 36)
                        .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))

                    Text(layer.label)
                        .font(AppFont.body(22, weight: .bold))
                        .foregroundStyle(Color.text0)

                    Spacer()

                    Button {
                        layer.isEnabled.toggle()
                    } label: {
                        Image(systemName: layer.isEnabled ? "eye" : "eye.slash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(layer.isEnabled ? Color.text1 : Color.text3)
                            .frame(width: 36, height: 36)
                            .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                // Layer-specific controls
                layerControls
                    .padding(.horizontal, 16)
                    .opacity(layer.isEnabled ? 1.0 : 0.55)
                    .allowsHitTesting(layer.isEnabled)

                Spacer(minLength: 20)

                // Delete button
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Text("Delete Layer")
                        .font(AppFont.buttonText)
                        .foregroundStyle(Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(Color.surface0)
        .navigationTitle(layer.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.surface1, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .foregroundStyle(Color.text1)
        .tint(Color.accent)
        .onChange(of: layer) { _, _ in updateMiniPreview() }
        .onAppear { updateMiniPreview() }
    }

    private func updateMiniPreview() {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let photo = appState.selectedPhoto else { return }
            let processor = FrameProcessor()
            let url = photo.url
            let config = appState.currentConfig
            let rotation = photo.rotation
            let compactPreviewMaxDimension = 320
            do {
                let cgImage = try await Task.detached {
                    try await processor.previewCGImage(
                        for: url,
                        config: config,
                        rotation: rotation,
                        maxDimension: compactPreviewMaxDimension
                    )
                }.value
                guard !Task.isCancelled else { return }
                miniPreview = UIImage(cgImage: cgImage)
            } catch { }
        }
    }

    @ViewBuilder
    private var layerControls: some View {
        switch layer {
        case .border(let params):
            BorderControls(params: params) { layer = .border($0) }
        case .padding(let params):
            PaddingControls(params: params) { layer = .padding($0) }
        case .canvas(let params):
            CanvasControls(params: params) { layer = .canvas($0) }
        case .resize(let params):
            ResizeControls(params: params) { layer = .resize($0) }
        case .aspectRatio(let params):
            AspectRatioControls(params: params) { layer = .aspectRatio($0) }
        case .orientation(let params):
            OrientationControls(params: params) { layer = .orientation($0) }
        case .caption(let params):
            CaptionControls(params: params) { layer = .caption($0) }
        case .dither(let params):
            DitherControls(params: params) { layer = .dither($0) }
        case .overlay(let params):
            OverlayControls(params: params) { layer = .overlay($0) }
        case .lut(let params):
            LUTControls(params: params) { layer = .lut($0) }
        case .shader(let params):
            ShaderControls(params: params) { layer = .shader($0) }
        }
    }
}

// MARK: - Shared Helpers

private struct ControlRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""

    var body: some View {
        ControlRow(label: label) {
            HStack {
                Slider(value: $value, in: range)
                Text("\(Int(value))\(unit)")
                    .font(AppFont.mono(12))
                    .foregroundStyle(Color.text1)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}

// MARK: - Border Controls

private struct BorderControls: View {
    var params: BorderLayerParams
    var onChange: (BorderLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Thickness") {
                HStack {
                    Slider(value: thicknessValue, in: thicknessRange)
                    Text("\(Int(thicknessValue.wrappedValue))\(thicknessUnit)")
                        .font(AppFont.mono(12))
                        .foregroundStyle(Color.text1)
                        .frame(width: 50, alignment: .trailing)
                }
            }

            ControlRow(label: "Color") {
                ColorPicker("", selection: colorBinding)
                    .labelsHidden()
                    .accessibilityLabel("Border Color")
            }
        }
    }

    private var thicknessUnit: String {
        if case .percent = params.thickness { return "%" }
        return "px"
    }

    private var thicknessRange: ClosedRange<Double> {
        if case .percent = params.thickness { return 0...20 }
        return 0...300
    }

    private var thicknessValue: Binding<Double> {
        Binding(
            get: {
                switch params.thickness {
                case .pixels(let px): return Double(px)
                case .percent(let p): return p
                }
            },
            set: { val in
                var p = params
                switch params.thickness {
                case .pixels: p.thickness = .pixels(Int(val))
                case .percent: p.thickness = .percent(val)
                }
                onChange(p)
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(cgColor: params.color.cgColor) },
            set: { newColor in
                guard let hex = newColor.hexString, let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.color = c
                onChange(p)
            }
        )
    }
}

// MARK: - Padding Controls

private struct PaddingControls: View {
    var params: PaddingLayerParams
    var onChange: (PaddingLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Thickness") {
                HStack {
                    Slider(value: Binding(
                        get: { Double(params.thickness) },
                        set: { var p = params; p.thickness = Int($0); onChange(p) }
                    ), in: 0...400)
                    Text("\(params.thickness)px")
                        .font(AppFont.mono(12))
                        .foregroundStyle(Color.text1)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            FillPicker(fill: params.fill) { newFill in
                var p = params; p.fill = newFill; onChange(p)
            }
        }
    }
}

// MARK: - Canvas Controls

private struct CanvasControls: View {
    var params: CanvasLayerParams
    var onChange: (CanvasLayerParams) -> Void

    private let presets: [(String, Int, Int)] = [
        ("Instagram 4:5", 1080, 1350),
        ("10×15cm 300dpi", 1772, 1181),
        ("Square 1080", 1080, 1080),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Size Presets") {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { name, w, h in
                        Button {
                            var p = params; p.width = w; p.height = h; onChange(p)
                        } label: {
                            Text(name)
                                .font(AppFont.body(11))
                                .foregroundStyle(params.width == w && params.height == h ? Color.accent : Color.text2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    params.width == w && params.height == h ? Color.accentSubtle : Color.surface3,
                                    in: RoundedRectangle(cornerRadius: CornerRadius.md)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                ControlRow(label: "Width") {
                    TextField("", value: Binding(
                        get: { params.width },
                        set: { var p = params; p.width = $0; onChange(p) }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
                ControlRow(label: "Height") {
                    TextField("", value: Binding(
                        get: { params.height },
                        set: { var p = params; p.height = $0; onChange(p) }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
            }

            FillPicker(fill: params.fill) { newFill in
                var p = params; p.fill = newFill; onChange(p)
            }
        }
    }
}

// MARK: - Resize Controls

private struct ResizeControls: View {
    var params: ResizeLayerParams
    var onChange: (ResizeLayerParams) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ControlRow(label: "Max Width") {
                TextField("", value: Binding(
                    get: { params.maxWidth },
                    set: { var p = params; p.maxWidth = $0; onChange(p) }
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
            }
            ControlRow(label: "Max Height") {
                TextField("", value: Binding(
                    get: { params.maxHeight },
                    set: { var p = params; p.maxHeight = $0; onChange(p) }
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
            }
        }
    }
}

// MARK: - Aspect Ratio Controls

private struct AspectRatioControls: View {
    var params: AspectRatioLayerParams
    var onChange: (AspectRatioLayerParams) -> Void

    private let presets: [(String, Int, Int)] = [
        ("1:1", 1, 1), ("4:5", 4, 5), ("5:4", 5, 4),
        ("3:2", 3, 2), ("2:3", 2, 3), ("16:9", 16, 9), ("9:16", 9, 16),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Ratio") {
                Picker("", selection: Binding(
                    get: {
                        presets.first { $0.1 == params.ratioWidth && $0.2 == params.ratioHeight }?.0 ?? "Custom"
                    },
                    set: { val in
                        if let preset = presets.first(where: { $0.0 == val }) {
                            onChange(AspectRatioLayerParams(id: params.id, ratioWidth: preset.1, ratioHeight: preset.2, offsetX: params.offsetX, offsetY: params.offsetY))
                        }
                    }
                )) {
                    ForEach(presets, id: \.0) { Text($0.0).tag($0.0) }
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.menu)
            }

            ControlRow(label: "Offset X") {
                HStack {
                    Slider(value: Binding(
                        get: { params.offsetX },
                        set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: params.ratioHeight, offsetX: $0, offsetY: params.offsetY)) }
                    ), in: -1...1)
                    Text(String(format: "%.1f", params.offsetX))
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }

            ControlRow(label: "Offset Y") {
                HStack {
                    Slider(value: Binding(
                        get: { params.offsetY },
                        set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: params.ratioHeight, offsetX: params.offsetX, offsetY: $0)) }
                    ), in: -1...1)
                    Text(String(format: "%.1f", params.offsetY))
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Orientation Controls

private struct OrientationControls: View {
    var params: OrientationLayerParams
    var onChange: (OrientationLayerParams) -> Void

    var body: some View {
        ControlRow(label: "Target Orientation") {
            Picker("", selection: Binding(
                get: { params.target },
                set: { var p = params; p.target = $0; onChange(p) }
            )) {
                ForEach(OrientationTarget.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Caption Controls

private struct CaptionControls: View {
    var params: CaptionLayerParams
    var onChange: (CaptionLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Mode") {
                Picker("", selection: Binding(
                    get: {
                        switch params.mode {
                        case .template: return 0
                        case .custom: return 1
                        case .none: return 2
                        }
                    },
                    set: { idx in
                        var p = params
                        switch idx {
                        case 0:
                            if case .template = p.mode { } else {
                                p.mode = .template("{{camera}} {{focal}}")
                            }
                        case 1:
                            if case .custom = p.mode { } else {
                                p.mode = .custom("")
                            }
                        default: p.mode = .none
                        }
                        onChange(p)
                    }
                )) {
                    Text("Template").tag(0)
                    Text("Custom").tag(1)
                    Text("None").tag(2)
                }
                .pickerStyle(.segmented)
            }

            if case .template(let t) = params.mode {
                ControlRow(label: "Template") {
                    TextField("Template", text: Binding(
                        get: { t },
                        set: { var p = params; p.mode = .template($0); onChange(p) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if case .custom(let t) = params.mode {
                ControlRow(label: "Caption Text") {
                    TextField("Caption", text: Binding(
                        get: { t },
                        set: { var p = params; p.mode = .custom($0); onChange(p) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if case .none = params.mode { } else {
                ControlRow(label: "Position") {
                    Picker("", selection: Binding(
                        get: { params.position },
                        set: { var p = params; p.position = $0; onChange(p) }
                    )) {
                        Text("Bottom").tag(CaptionPosition.bottom)
                        Text("Top").tag(CaptionPosition.top)
                    }
                    .pickerStyle(.segmented)
                }

                ControlRow(label: "Alignment") {
                    Picker("", selection: Binding(
                        get: { params.alignment },
                        set: { var p = params; p.alignment = $0; onChange(p) }
                    )) {
                        Text("Left").tag(CaptionAlignment.left)
                        Text("Center").tag(CaptionAlignment.center)
                        Text("Right").tag(CaptionAlignment.right)
                    }
                    .pickerStyle(.segmented)
                }

                ControlRow(label: "Font Color") {
                    Picker("", selection: Binding(
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
                            default: p.fontColorMode = .fixed(p.fontColor)
                            }
                            onChange(p)
                        }
                    )) {
                        Text("Custom").tag(0)
                        Text("Dominant").tag(1)
                        Text("Invert").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                // Saturation/lightness for dominant caption colors
                if case .dominant(let sat, let light) = params.fontColorMode {
                    captionAdjustmentSliders(sat: sat, light: light) { s, l in
                        var p = params; p.fontColorMode = .dominant(saturationShift: s, lightnessShift: l); onChange(p)
                    }
                }
                if case .dominantInverted(let sat, let light) = params.fontColorMode {
                    captionAdjustmentSliders(sat: sat, light: light) { s, l in
                        var p = params; p.fontColorMode = .dominantInverted(saturationShift: s, lightnessShift: l); onChange(p)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func captionAdjustmentSliders(sat: Double, light: Double, onChange: @escaping (Double, Double) -> Void) -> some View {
        ControlRow(label: "Saturation") {
            HStack {
                Slider(value: Binding(get: { sat }, set: { onChange($0, light) }), in: -50...50)
                Text("\(Int(sat))")
                    .font(AppFont.mono(12))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        ControlRow(label: "Brightness") {
            HStack {
                Slider(value: Binding(get: { light }, set: { onChange(sat, $0) }), in: -50...50)
                Text("\(Int(light))")
                    .font(AppFont.mono(12))
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Overlay Controls

private struct OverlayControls: View {
    var params: OverlayLayerParams
    var onChange: (OverlayLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Category") {
                Picker("", selection: Binding(
                    get: { params.kind },
                    set: { var p = params; p.kind = $0; p.overlayName = ""; onChange(p) }
                )) {
                    Text("Frames").tag(OverlayKind.frame)
                    Text("Dust").tag(OverlayKind.dust)
                    Text("Light Leaks").tag(OverlayKind.lightLeak)
                    Text("Wet Plate").tag(OverlayKind.wetPlate)
                }
                .pickerStyle(.menu)
            }

            ControlRow(label: "Overlay") {
                let overlays = TextureFrameProvider.overlays(ofKind: params.kind)
                Picker("", selection: Binding(
                    get: { params.overlayName },
                    set: { var p = params; p.overlayName = $0; onChange(p) }
                )) {
                    Text("None").tag("")
                    ForEach(overlays, id: \.id) { overlay in
                        Text(overlay.displayName).tag(overlay.id)
                    }
                }
                .pickerStyle(.menu)
            }

            ControlRow(label: "Opacity") {
                HStack {
                    Slider(value: Binding(
                        get: { params.opacity },
                        set: { var p = params; p.opacity = $0; onChange(p) }
                    ), in: 0...100)
                    Text("\(Int(params.opacity))%")
                        .font(AppFont.mono(12))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            ControlRow(label: "Blend Mode") {
                Picker("", selection: Binding(
                    get: { params.blendMode },
                    set: { var p = params; p.blendMode = $0; onChange(p) }
                )) {
                    ForEach(OverlayBlendMode.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

// MARK: - Dither Controls

private struct DitherControls: View {
    var params: DitherLayerParams
    var onChange: (DitherLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Algorithm") {
                Picker("", selection: Binding(
                    get: { params.algorithm },
                    set: { var p = params; p.algorithm = $0; onChange(p) }
                )) {
                    ForEach(DitherAlgorithm.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }

            ControlRow(label: "Color Mode") {
                Picker("", selection: Binding(
                    get: {
                        switch params.colorMode {
                        case .bw: return 0
                        case .twoTone: return 1
                        case .color: return 2
                        case .dominantTwoTone: return 3
                        }
                    },
                    set: { tag in
                        var p = params
                        switch tag {
                        case 0: p.colorMode = .bw
                        case 1: p.colorMode = .twoTone(foreground: (try? CodableColor(hex: "#0251FF")) ?? .black, background: .black)
                        case 2: p.colorMode = .color(levels: 4)
                        case 3: p.colorMode = .dominantTwoTone(flipped: false, saturationShift: 0, lightnessShift: 0)
                        default: break
                        }
                        onChange(p)
                    }
                )) {
                    Text("B&W").tag(0)
                    Text("Two-Tone").tag(1)
                    Text("Color").tag(2)
                    Text("Dominant").tag(3)
                }
                .pickerStyle(.segmented)
            }

            if params.algorithm == .bayer {
                ControlRow(label: "Bayer Level: \(params.bayerLevel)") {
                    Stepper("", value: Binding(
                        get: { params.bayerLevel },
                        set: { var p = params; p.bayerLevel = $0; onChange(p) }
                    ), in: 1...4)
                    .labelsHidden()
                    .accessibilityLabel("Bayer Level")
                }
            }

            ControlRow(label: "Pixel Scale: \(params.pixelScale)×") {
                Stepper("", value: Binding(
                    get: { params.pixelScale },
                    set: { var p = params; p.pixelScale = $0; onChange(p) }
                ), in: 1...8)
                .labelsHidden()
                .accessibilityLabel("Pixel Scale")
            }

            // Two-Tone color pickers
            if case .twoTone(let fg, let bg) = params.colorMode {
                ControlRow(label: "Foreground") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: fg.cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let c = try? CodableColor(hex: hex) else { return }
                            var p = params; p.colorMode = .twoTone(foreground: c, background: bg); onChange(p)
                        }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Foreground Color")
                }
                ControlRow(label: "Background") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: bg.cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let c = try? CodableColor(hex: hex) else { return }
                            var p = params; p.colorMode = .twoTone(foreground: fg, background: c); onChange(p)
                        }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Background Color")
                }
            }

            // Dominant two-tone controls
            if case .dominantTwoTone(let flipped, let sat, let light) = params.colorMode {
                ControlRow(label: "Flip Colors") {
                    Toggle("", isOn: Binding(
                        get: { flipped },
                        set: { var p = params; p.colorMode = .dominantTwoTone(flipped: $0, saturationShift: sat, lightnessShift: light); onChange(p) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Flip Colors")
                }
                ControlRow(label: "Saturation") {
                    HStack {
                        Slider(value: Binding(
                            get: { sat },
                            set: { var p = params; p.colorMode = .dominantTwoTone(flipped: flipped, saturationShift: $0, lightnessShift: light); onChange(p) }
                        ), in: -50...50)
                        Text("\(Int(sat))")
                            .font(AppFont.mono(12))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                ControlRow(label: "Brightness") {
                    HStack {
                        Slider(value: Binding(
                            get: { light },
                            set: { var p = params; p.colorMode = .dominantTwoTone(flipped: flipped, saturationShift: sat, lightnessShift: $0); onChange(p) }
                        ), in: -50...50)
                        Text("\(Int(light))")
                            .font(AppFont.mono(12))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            // Color levels
            if case .color(let levels) = params.colorMode {
                ControlRow(label: "Levels: \(levels) per channel") {
                    Stepper("", value: Binding(
                        get: { levels },
                        set: { var p = params; p.colorMode = .color(levels: $0); onChange(p) }
                    ), in: 2...8)
                    .labelsHidden()
                    .accessibilityLabel("Color Levels")
                }
            }

            ControlRow(label: "Threshold (\(String(format: "%.2f", params.threshold)))") {
                Slider(value: Binding(
                    get: { params.threshold },
                    set: { var p = params; p.threshold = $0; onChange(p) }
                ), in: 0.1...0.9, step: 0.05)
            }

            ControlRow(label: "Sharpen (\(Int(params.sharpen * 100))%)") {
                Slider(value: Binding(
                    get: { params.sharpen },
                    set: { var p = params; p.sharpen = $0; onChange(p) }
                ), in: 0...1, step: 0.1)
            }

            ControlRow(label: "Contrast (\(Int(params.contrast * 100))%)") {
                Slider(value: Binding(
                    get: { params.contrast },
                    set: { var p = params; p.contrast = $0; onChange(p) }
                ), in: 0...1, step: 0.1)
            }
        }
    }
}

// MARK: - Fill Picker (shared)

private struct FillPicker: View {
    var fill: LayerFill
    var onChange: (LayerFill) -> Void

    var body: some View {
        ControlRow(label: "Fill") {
            Picker("", selection: Binding(
                get: {
                    switch fill {
                    case .color: return 0
                    case .dominantColor: return 1
                    case .gradientLinear: return 2
                    case .gradientRadial: return 3
                    }
                },
                set: { idx in
                    let existing = fill.gradientParams ?? GradientParams()
                    switch idx {
                    case 0: onChange(.color(.white))
                    case 1: onChange(.dominantColor(existing))
                    case 2: onChange(.gradientLinear(existing))
                    case 3: onChange(.gradientRadial(existing))
                    default: break
                    }
                }
            )) {
                Text("Solid").tag(0)
                Text("Dominant").tag(1)
                Text("Linear").tag(2)
                Text("Radial").tag(3)
            }
            .pickerStyle(.segmented)
        }

        if case .color(let c) = fill {
            ControlRow(label: "Color") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: c.cgColor) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        onChange(.color(codable))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Fill Color")
            }
        }

        if let params = fill.gradientParams {
            ControlRow(label: "Saturation") {
                HStack {
                    Slider(value: Binding(
                        get: { params.saturationShift },
                        set: { val in
                            let newParams = GradientParams(saturationShift: val, lightnessShift: params.lightnessShift)
                            switch fill {
                            case .dominantColor: onChange(.dominantColor(newParams))
                            case .gradientLinear: onChange(.gradientLinear(newParams))
                            case .gradientRadial: onChange(.gradientRadial(newParams))
                            default: break
                            }
                        }
                    ), in: -50...50)
                    Text("\(Int(params.saturationShift))")
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }

            ControlRow(label: "Brightness") {
                HStack {
                    Slider(value: Binding(
                        get: { params.lightnessShift },
                        set: { val in
                            let newParams = GradientParams(saturationShift: params.saturationShift, lightnessShift: val)
                            switch fill {
                            case .dominantColor: onChange(.dominantColor(newParams))
                            case .gradientLinear: onChange(.gradientLinear(newParams))
                            case .gradientRadial: onChange(.gradientRadial(newParams))
                            default: break
                            }
                        }
                    ), in: -50...50)
                    Text("\(Int(params.lightnessShift))")
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Shader Controls

private struct ShaderControls: View {
    var params: ShaderLayerParams
    var onChange: (ShaderLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Style") {
                Picker("", selection: Binding(
                    get: { params.style },
                    set: { onChange(params.withStyle($0)) }
                )) {
                    ForEach(ShaderStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }

            sliderRow(
                label: "Intensity",
                value: params.intensity,
                range: 0...1,
                step: 0.05
            ) { value in
                var updated = params
                updated.intensity = value
                onChange(updated)
            }

            switch params.params {
            case .ascii(let asciiParams):
                asciiControls(asciiParams)
            case .crimewave(let crimewaveParams):
                crimewaveControls(crimewaveParams)
            case .narc(let narcParams):
                narcControls(narcParams)
            case .shiba(let shibaParams):
                shibaControls(shibaParams)
            case .pixelSort(let pixelSortParams):
                pixelSortControls(pixelSortParams)
            case .distantPast(let distantPastParams):
                distantPastControls(distantPastParams)
            case .crt(let crtParams):
                crtControls(crtParams)
            case .halftone(let halftoneParams):
                halftoneControls(halftoneParams)
            case .kuwahara(let kuwaharaParams):
                kuwaharaControls(kuwaharaParams)
            }
        }
    }

    @ViewBuilder
    private func asciiControls(_ asciiParams: ASCIIShaderParams) -> some View {
        sliderRow(
            label: "Cell Size",
            value: Double(asciiParams.cellSize),
            range: expandedRange(4...24, including: Double(asciiParams.cellSize)),
            step: 1
        ) { value in
            updateASCII(asciiParams, cellSize: Int(value.rounded()))
        }

        sliderRow(
            label: "Edge Bias",
            value: asciiParams.edgeBias,
            range: expandedRange(0...1, including: asciiParams.edgeBias),
            step: 0.05
        ) { value in
            updateASCII(asciiParams, edgeBias: value)
        }

        sliderRow(
            label: "Exposure",
            value: asciiParams.exposure,
            range: expandedRange(0...5, including: asciiParams.exposure),
            step: 0.1
        ) { value in
            updateASCII(asciiParams, exposure: value)
        }

        sliderRow(
            label: "Attenuation",
            value: asciiParams.attenuation,
            range: expandedRange(0...5, including: asciiParams.attenuation),
            step: 0.1
        ) { value in
            updateASCII(asciiParams, attenuation: value)
        }

        ControlRow(label: "Colors") {
            Picker("", selection: Binding(
                get: {
                    switch asciiParams.colorMode {
                    case .manual: return 0
                    case .dominantTwoTone: return 1
                    case .source: return 2
                    case .gradient: return 3
                    }
                },
                set: { mode in
                    switch mode {
                    case 1:
                        updateASCII(asciiParams, colorMode: .dominantTwoTone())
                    case 2:
                        updateASCII(asciiParams, colorMode: .source())
                    case 3:
                        updateASCII(asciiParams, colorMode: .gradient(color1: .black, color2: .white))
                    default:
                        updateASCII(asciiParams, colorMode: .manual(foreground: .white, background: .black))
                    }
                }
            )) {
                Text("Manual").tag(0)
                Text("Dominant").tag(1)
                Text("Source").tag(2)
                Text("Gradient").tag(3)
            }
            .pickerStyle(.segmented)
        }

        switch asciiParams.colorMode {
        case .manual(let foreground, let background):
            ControlRow(label: "Foreground") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: foreground.cgColor) },
                    set: { value in
                        guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                        updateASCII(asciiParams, colorMode: .manual(foreground: color, background: background))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("ASCII Foreground")
            }

            ControlRow(label: "Background") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: background.cgColor) },
                    set: { value in
                        guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                        updateASCII(asciiParams, colorMode: .manual(foreground: foreground, background: color))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("ASCII Background")
            }
        case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift):
            ControlRow(label: "Flip Palette") {
                Toggle("", isOn: Binding(
                    get: { flipped },
                    set: { value in
                        updateASCII(asciiParams, colorMode: .dominantTwoTone(
                            flipped: value,
                            saturationShift: saturationShift,
                            lightnessShift: lightnessShift
                        ))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Flip ASCII Palette")
            }

            sliderRow(
                label: "Saturation",
                value: saturationShift,
                range: expandedRange(-50...50, including: saturationShift),
                step: 1
            ) { value in
                updateASCII(asciiParams, colorMode: .dominantTwoTone(
                    flipped: flipped,
                    saturationShift: value,
                    lightnessShift: lightnessShift
                ))
            }

            sliderRow(
                label: "Brightness",
                value: lightnessShift,
                range: expandedRange(-50...50, including: lightnessShift),
                step: 1
            ) { value in
                updateASCII(asciiParams, colorMode: .dominantTwoTone(
                    flipped: flipped,
                    saturationShift: saturationShift,
                    lightnessShift: value
                ))
            }
        case .source(let background):
            ControlRow(label: "Background") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: background.cgColor) },
                    set: { value in
                        guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                        updateASCII(asciiParams, colorMode: .source(background: color))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("ASCII Source Background")
            }
        case .gradient(let color1, let color2, let background):
            ControlRow(label: "Dark Color") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: color1.cgColor) },
                    set: { value in
                        guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                        updateASCII(asciiParams, colorMode: .gradient(color1: color, color2: color2, background: background))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("ASCII Gradient Dark")
            }

            ControlRow(label: "Bright Color") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: color2.cgColor) },
                    set: { value in
                        guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                        updateASCII(asciiParams, colorMode: .gradient(color1: color1, color2: color, background: background))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("ASCII Gradient Bright")
            }

            ControlRow(label: "Background") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: background.cgColor) },
                    set: { value in
                        guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                        updateASCII(asciiParams, colorMode: .gradient(color1: color1, color2: color2, background: color))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("ASCII Gradient Background")
            }
        }

        ControlRow(label: "Invert") {
            Toggle("", isOn: Binding(
                get: { asciiParams.invert },
                set: { value in
                    updateASCII(asciiParams, invert: value)
                }
            ))
            .labelsHidden()
            .accessibilityLabel("Invert ASCII")
        }
    }

    private func updateASCII(
        _ asciiParams: ASCIIShaderParams,
        cellSize: Int? = nil,
        edgeBias: Double? = nil,
        colorMode: ASCIIColorMode? = nil,
        invert: Bool? = nil,
        exposure: Double? = nil,
        attenuation: Double? = nil
    ) {
        onChange(params.withParams(.ascii(ASCIIShaderParams(
            cellSize: cellSize ?? asciiParams.cellSize,
            edgeBias: edgeBias ?? asciiParams.edgeBias,
            colorMode: colorMode ?? asciiParams.colorMode,
            invert: invert ?? asciiParams.invert,
            exposure: exposure ?? asciiParams.exposure,
            attenuation: attenuation ?? asciiParams.attenuation
        ))))
    }

    @ViewBuilder
    private func crimewaveControls(_ crimewaveParams: CrimewaveShaderParams) -> some View {
        styleSliderRows(
            [("Neon", crimewaveParams.neon, 0...2, 0.05),
             ("Softness", crimewaveParams.softness, 0...1, 0.05),
             ("Contrast", crimewaveParams.contrast, 0.5...3, 0.05),
             ("Grain", crimewaveParams.grain, 0...1, 0.05)]
        ) { label, value in
            var updated = crimewaveParams
            switch label {
            case "Neon": updated.neon = value
            case "Softness": updated.softness = value
            case "Contrast": updated.contrast = value
            default: updated.grain = value
            }
            onChange(params.withParams(.crimewave(updated)))
        }
    }

    @ViewBuilder
    private func narcControls(_ narcParams: NarcShaderParams) -> some View {
        styleSliderRows(
            [("Contrast", narcParams.contrast, 0.5...3, 0.05),
             ("Crush", narcParams.crush, 0...1, 0.05),
             ("Temperature", narcParams.temperature, -1...1, 0.05),
             ("Grain", narcParams.grain, 0...1, 0.05)]
        ) { label, value in
            var updated = narcParams
            switch label {
            case "Contrast": updated.contrast = value
            case "Crush": updated.crush = value
            case "Temperature": updated.temperature = value
            default: updated.grain = value
            }
            onChange(params.withParams(.narc(updated)))
        }
    }

    @ViewBuilder
    private func shibaControls(_ shibaParams: ShibaShaderParams) -> some View {
        styleSliderRows(
            [("Warmth", shibaParams.warmth, -1...1, 0.05),
             ("Softness", shibaParams.softness, 0...1, 0.05),
             ("Saturation", shibaParams.saturation, 0...2, 0.05),
             ("Grain", shibaParams.grain, 0...1, 0.05)]
        ) { label, value in
            var updated = shibaParams
            switch label {
            case "Warmth": updated.warmth = value
            case "Softness": updated.softness = value
            case "Saturation": updated.saturation = value
            default: updated.grain = value
            }
            onChange(params.withParams(.shiba(updated)))
        }
    }

    @ViewBuilder
    private func pixelSortControls(_ pixelSortParams: PixelSortShaderParams) -> some View {
        ControlRow(label: "Direction") {
            Picker("", selection: Binding(
                get: { pixelSortParams.direction },
                set: { value in
                    var updated = pixelSortParams
                    updated.direction = value
                    onChange(params.withParams(.pixelSort(updated)))
                }
            )) {
                ForEach(PixelSortDirection.allCases, id: \.self) { direction in
                    Text(direction.rawValue.capitalized).tag(direction)
                }
            }
            .pickerStyle(.segmented)
        }

        sliderRow(
            label: "Threshold",
            value: pixelSortParams.threshold,
            range: expandedRange(0...1, including: pixelSortParams.threshold),
            step: 0.05
        ) { value in
            var updated = pixelSortParams
            updated.threshold = value
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            label: "Span",
            value: Double(pixelSortParams.span),
            range: expandedRange(4...256, including: Double(pixelSortParams.span)),
            step: 1
        ) { value in
            var updated = pixelSortParams
            updated.span = Int(value.rounded())
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            label: "Amount",
            value: pixelSortParams.amount,
            range: expandedRange(0...1, including: pixelSortParams.amount),
            step: 0.05
        ) { value in
            var updated = pixelSortParams
            updated.amount = value
            onChange(params.withParams(.pixelSort(updated)))
        }
    }

    @ViewBuilder
    private func crtControls(_ crtParams: CRTShaderParams) -> some View {
        sliderRow(
            label: "Curvature",
            value: crtParams.curvature,
            range: expandedRange(1...10, including: crtParams.curvature),
            step: 0.5
        ) { value in
            var updated = crtParams; updated.curvature = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Line Size",
            value: Double(crtParams.lineSize),
            range: 0...4,
            step: 1
        ) { value in
            var updated = crtParams; updated.lineSize = Int(value.rounded())
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Line Strength",
            value: crtParams.lineStrength,
            range: expandedRange(0...5, including: crtParams.lineStrength),
            step: 0.1
        ) { value in
            var updated = crtParams; updated.lineStrength = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Brightness",
            value: crtParams.brightness,
            range: expandedRange(-1...1, including: crtParams.brightness),
            step: 0.05
        ) { value in
            var updated = crtParams; updated.brightness = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Vignette",
            value: crtParams.vignette,
            range: expandedRange(1...100, including: crtParams.vignette),
            step: 1
        ) { value in
            var updated = crtParams; updated.vignette = value
            onChange(params.withParams(.crt(updated)))
        }
    }

    @ViewBuilder
    private func halftoneControls(_ halftoneParams: HalftoneShaderParams) -> some View {
        sliderRow(
            label: "Dot Size",
            value: halftoneParams.dotSize,
            range: expandedRange(0.1...3, including: halftoneParams.dotSize),
            step: 0.1
        ) { value in
            var updated = halftoneParams; updated.dotSize = value
            onChange(params.withParams(.halftone(updated)))
        }
        sliderRow(
            label: "Contrast",
            value: halftoneParams.contrast,
            range: expandedRange(0.1...3, including: halftoneParams.contrast),
            step: 0.1
        ) { value in
            var updated = halftoneParams; updated.contrast = value
            onChange(params.withParams(.halftone(updated)))
        }
        ControlRow(label: "Monochrome") {
            Toggle("", isOn: Binding(
                get: { halftoneParams.monochrome },
                set: { value in
                    var updated = halftoneParams; updated.monochrome = value
                    onChange(params.withParams(.halftone(updated)))
                }
            ))
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func kuwaharaControls(_ kuwaharaParams: KuwaharaShaderParams) -> some View {
        sliderRow(
            label: "Kernel Size",
            value: Double(kuwaharaParams.kernelSize),
            range: expandedRange(1...15, including: Double(kuwaharaParams.kernelSize)),
            step: 1
        ) { value in
            var updated = kuwaharaParams; updated.kernelSize = Int(value.rounded())
            onChange(params.withParams(.kuwahara(updated)))
        }
        sliderRow(
            label: "Sharpness",
            value: kuwaharaParams.sharpness,
            range: expandedRange(1...16, including: kuwaharaParams.sharpness),
            step: 0.5
        ) { value in
            var updated = kuwaharaParams; updated.sharpness = value
            onChange(params.withParams(.kuwahara(updated)))
        }
    }

    @ViewBuilder
    private func distantPastControls(_ distantPastParams: DistantPastShaderParams) -> some View {
        styleSliderRows(
            [("Palette Depth", Double(distantPastParams.paletteDepth), 2...6, 1),
             ("Fade", distantPastParams.fade, 0...1, 0.05),
             ("Softness", distantPastParams.softness, 0...1, 0.05),
             ("Grain", distantPastParams.grain, 0...1, 0.05)]
        ) { label, value in
            var updated = distantPastParams
            switch label {
            case "Palette Depth": updated.paletteDepth = Int(value.rounded())
            case "Fade": updated.fade = value
            case "Softness": updated.softness = value
            default: updated.grain = value
            }
            onChange(params.withParams(.distantPast(updated)))
        }
    }

    @ViewBuilder
    private func styleSliderRows(
        _ rows: [(String, Double, ClosedRange<Double>, Double)],
        onSet: @escaping (String, Double) -> Void
    ) -> some View {
        ForEach(rows, id: \.0) { row in
            sliderRow(
                label: row.0,
                value: row.1,
                range: expandedRange(row.2, including: row.1),
                step: row.3
            ) { onSet(row.0, $0) }
        }
    }

    private func expandedRange(_ base: ClosedRange<Double>, including value: Double) -> ClosedRange<Double> {
        min(base.lowerBound, value)...max(base.upperBound, value)
    }

    private func sliderRow(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        onSet: @escaping @Sendable (Double) -> Void
    ) -> some View {
        ControlRow(label: label) {
            HStack {
                Slider(value: Binding(get: { value }, set: onSet), in: range, step: step)
                Text(step >= 1 ? "\(Int(value.rounded()))" : String(format: "%.2f", value))
                    .font(AppFont.mono(12))
                    .foregroundStyle(Color.text1)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

// MARK: - LUT Controls

private struct LUTControls: View {
    var params: LUTLayerParams
    var onChange: (LUTLayerParams) -> Void

    @State private var availableLUTs: [LUTInfo] = []
    @State private var showingPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 8) {
            if availableLUTs.isEmpty {
                emptyState
            } else {
                ControlRow(label: "LUT") {
                    Picker("", selection: Binding(
                        get: { params.lutFileName },
                        set: { newValue in
                            var p = params
                            p.lutFileName = newValue
                            if let lut = availableLUTs.first(where: { $0.id == newValue }) {
                                p.lutName = lut.displayName
                            }
                            onChange(p)
                        }
                    )) {
                        Text("None").tag("")
                        ForEach(availableLUTs, id: \.id) { lut in
                            Text(lut.displayName).tag(lut.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            ControlRow(label: "Intensity") {
                HStack {
                    Slider(value: Binding(
                        get: { params.intensity },
                        set: { var p = params; p.intensity = $0; onChange(p) }
                    ), in: 0...1)
                    Text("\(Int(params.intensity * 100))%")
                        .font(AppFont.mono(12))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Button {
                showingPicker = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import LUT")
                }
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.accent)
            }
            .sheet(isPresented: $showingPicker) {
                DocumentPickerView { url in
                    importLUT(from: url)
                }
            }
        }
        .onAppear {
            loadLUTs()
        }
        .alert("Import Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(Color.text3)
            Text("No LUTs available")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text3)
            Text("Import .cube files to get started")
                .font(.caption)
                .foregroundStyle(Color.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func loadLUTs() {
        availableLUTs = LUTProvider.availableLUTs()
    }

    private func importLUT(from url: URL) {
        do {
            let info = try LUTProvider.importLUT(from: url)
            LUTProvider.invalidateCache()
            loadLUTs()
            var p = params
            p.lutName = info.displayName
            p.lutFileName = info.id
            onChange(p)
        } catch {
            errorMessage = "Failed to import LUT: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Document Picker

private struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    fileprivate func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    fileprivate final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPick(url)
        }
    }
}

// MARK: - Color hex helper

extension Color {
    var hexString: String? {
        guard let cgColor = cgColor?.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ),
        let components = cgColor.components,
        components.count >= 3 else { return nil }
        let r = Int(max(0, min(255, components[0] * 255)))
        let g = Int(max(0, min(255, components[1] * 255)))
        let b = Int(max(0, min(255, components[2] * 255)))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
