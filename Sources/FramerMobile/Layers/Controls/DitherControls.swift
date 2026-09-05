import SwiftUI
import FramerCore

// MARK: - Dither Controls

struct DitherControls: View {
    var params: DitherLayerParams
    var onChange: (DitherLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            MobileBlendModeControls(
                blendMode: Binding(
                    get: { params.blendMode },
                    set: { var p = params; p.blendMode = $0; onChange(p) }
                ),
                opacity: Binding(
                    get: { params.opacity },
                    set: { var p = params; p.opacity = $0; onChange(p) }
                )
            )
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
                        case .palette: return 4
                        }
                    },
                    set: { tag in
                        var p = params
                        switch tag {
                        case 0: p.colorMode = .bw
                        case 1: p.colorMode = .twoTone(foreground: (try? CodableColor(hex: "#0251FF")) ?? .black, background: .black)
                        case 2: p.colorMode = .color(levels: 4)
                        case 3: p.colorMode = .dominantTwoTone(flipped: false, saturationShift: 0, lightnessShift: 0)
                        case 4: p.colorMode = .palette(VintagePalette.gameBoy)
                        default: break
                        }
                        onChange(p)
                    }
                )) {
                    Text("B&W").tag(0)
                    Text("Two-Tone").tag(1)
                    Text("Color").tag(2)
                    Text("Dominant").tag(3)
                    Text("Palette").tag(4)
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

            // Palette mode — preset picker + per-colour editor. Mirrors
            // LayerListSection.paletteEditor's derivation-from-stored-colours
            // pattern so the picker stays in sync with the saved palette
            // (editing a swatch flips the preset to Custom automatically).
            if case .palette(let colors) = params.colorMode {
                let selectedPreset = VintagePalette.Preset.matching(colors)
                ControlRow(label: "Preset") {
                    Picker("", selection: Binding(
                        get: { selectedPreset },
                        set: { newValue in
                            var p = params
                            switch newValue {
                            case .custom:
                                let seed = (selectedPreset == .custom) ? colors : VintagePalette.gameBoy
                                p.colorMode = .palette(seed)
                            default:
                                p.colorMode = .palette(newValue.colors)
                            }
                            onChange(p)
                        }
                    )) {
                        ForEach(VintagePalette.Preset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                }

                MobileUserPaletteRow(currentColors: colors) { applied in
                    var p = params
                    p.colorMode = .palette(applied)
                    onChange(p)
                }

                ForEach(Array(colors.enumerated()), id: \.offset) { idx, color in
                    ControlRow(label: "Colour \(idx + 1)") {
                        HStack(spacing: 8) {
                            ColorPicker("", selection: Binding(
                                get: { Color(cgColor: color.cgColor) },
                                set: { newColor in
                                    guard let hex = newColor.hexString,
                                          let codable = try? CodableColor(hex: hex) else { return }
                                    var p = params
                                    var next = colors
                                    next[idx] = codable
                                    p.colorMode = .palette(next)
                                    onChange(p)
                                }
                            ))
                            .labelsHidden()
                            if colors.count > 2 {
                                Button {
                                    var p = params
                                    var next = colors
                                    next.remove(at: idx)
                                    p.colorMode = .palette(next)
                                    onChange(p)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                if colors.count < DitherColorMode.MAX_PALETTE_COLORS {
                    Button {
                        var p = params
                        var next = colors
                        next.append(colors.last ?? CodableColor(unchecked: "#000000"))
                        p.colorMode = .palette(next)
                        onChange(p)
                    } label: {
                        Label("Add Colour", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
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

