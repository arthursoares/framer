import SwiftUI
import FramerCore

// MARK: - Caption Controls

struct CaptionControls: View {
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

                // Font
                ControlRow(label: "Font") {
                    Picker("", selection: Binding(
                        get: { params.fontName },
                        set: { var p = params; p.fontName = $0; onChange(p) }
                    )) {
                        ForEach(monospacedFontList, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                // Style
                ControlRow(label: "Style") {
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
                }

                // Font size
                ControlRow(label: "Size") {
                    Picker("", selection: Binding(
                        get: {
                            switch params.fontSize {
                            case .auto: return 0
                            case .fixed: return 1
                            }
                        },
                        set: { idx in
                            var p = params
                            p.fontSize = idx == 0 ? .auto : .fixed(24)
                            onChange(p)
                        }
                    )) {
                        Text("Auto").tag(0)
                        Text("Custom").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if case .fixed(let pts) = params.fontSize {
                    ControlRow(label: "Font Size") {
                        HStack {
                            Slider(value: Binding(
                                get: { Double(pts) },
                                set: { var p = params; p.fontSize = .fixed(Int($0)); onChange(p) }
                            ), in: 6...120)
                            Text("\(pts)pt")
                                .font(AppFont.mono(12))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var monospacedFontList: [String] {
        let current = params.fontName
        if Self.cachedMonospacedFonts.contains(current) {
            return Self.cachedMonospacedFonts
        }
        return ([current] + Self.cachedMonospacedFonts).sorted()
    }

    private static let cachedMonospacedFonts: [String] = {
        UIFont.familyNames
            .filter { family in
                guard let font = UIFont(name: family, size: 12) else {
                    // Family name doesn't work as a font name — check first face
                    let faces = UIFont.fontNames(forFamilyName: family)
                    guard let first = faces.first,
                          let f = UIFont(name: first, size: 12) else { return false }
                    return f.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
                }
                return font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
            }
            .sorted()
    }()

    private func fontStyleBinding(_ style: FontStyle) -> Binding<Bool> {
        Binding(
            get: { params.fontStyle.contains(style) },
            set: { on in
                var p = params
                if on { p.fontStyle.insert(style) } else { p.fontStyle.remove(style) }
                onChange(p)
            }
        )
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

