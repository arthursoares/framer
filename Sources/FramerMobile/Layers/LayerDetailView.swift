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
                }
                .padding(.horizontal, 16)

                // Layer-specific controls
                layerControls
                    .padding(.horizontal, 16)

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
        ControlRow(label: "Lightness") {
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
                ControlRow(label: "Lightness") {
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

            ControlRow(label: "Lightness") {
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
