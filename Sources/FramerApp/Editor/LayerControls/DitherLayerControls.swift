import SwiftUI
import AppKit
import FramerCore

// MARK: - DitherLayerControls

struct DitherLayerControls: View {
    @Environment(\.sidebarMetrics) private var metrics
    var params: DitherLayerParams
    var onChange: (DitherLayerParams) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BlendModeControls(
                blendMode: Binding(
                    get: { params.blendMode },
                    set: { var p = params; p.blendMode = $0; onChange(p) }
                ),
                opacity: Binding(
                    get: { params.opacity },
                    set: { var p = params; p.opacity = $0; onChange(p) }
                )
            )

            SimpleLayerEditorDivider()

            Picker("", selection: algorithmBinding) {
                ForEach(DitherAlgorithm.allCases, id: \.self) { algo in
                    Text(algo.label).tag(algo)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .denseControlRow("Algorithm")

            SimpleLayerEditorDivider()

            Picker("", selection: colorModeTag) {
                Text("B&W").tag(0)
                Text("Two-Tone").tag(1)
                Text("Dominant").tag(3)
                Text("Color").tag(2)
                Text("Palette").tag(4)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .denseControlRow("Color Mode")

            if params.algorithm == .bayer {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    Picker("", selection: bayerLevelBinding) {
                        ForEach(1...4, id: \.self) { level in
                            Text("Level \(level)").tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Bayer Level")
                } secondary: {
                    Text("\(1 << (params.bayerLevel + 1))×\(1 << (params.bayerLevel + 1)) matrix")
                        .font(AppFont.numericInput)
                        .foregroundStyle(Color.text2)
                        .denseSupportingRow("Pattern")
                }
            }

            SimpleLayerEditorDivider()

            DenseSliderControlRow(
                title: "Pixel Scale",
                value: Binding(
                    get: { Double(params.pixelScale) },
                    set: { pixelScaleBinding.wrappedValue = Int($0.rounded()) }
                ),
                range: 1...8,
                step: 1,
                unit: "×"
            )

            if case .twoTone(let fg, let bg) = params.colorMode {
                SimpleLayerEditorDivider()
                labeledColorPicker("Foreground", selection: foregroundBinding(fg: fg, bg: bg))

                SimpleLayerEditorDivider()
                labeledColorPicker("Background", selection: backgroundBinding(fg: fg, bg: bg))
            }

            if case .dominantTwoTone(let flipped, let sat, let light) = params.colorMode {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    SidebarControlRow("Flip Colors") {
                        EmptyView()
                    } trailingValue: {
                        StyledToggle(isOn: Binding(
                            get: { flipped },
                            set: { var p = params; p.colorMode = .dominantTwoTone(flipped: $0, saturationShift: sat, lightnessShift: light); onChange(p) }
                        ))
                    }
                } secondary: {
                    Text("Swap foreground and background")
                        .font(AppFont.body(10))
                        .foregroundStyle(Color.text2)
                        .denseSupportingRow("Details")
                }

                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    DenseSliderControlRow(
                        title: "Saturation",
                        value: Binding(
                            get: { sat },
                            set: { var p = params; p.colorMode = .dominantTwoTone(flipped: flipped, saturationShift: $0, lightnessShift: light); onChange(p) }
                        ),
                        range: -50...50,
                        step: 1
                    )
                } secondary: {
                    DenseSliderControlRow(
                        title: "Brightness",
                        value: Binding(
                            get: { light },
                            set: { var p = params; p.colorMode = .dominantTwoTone(flipped: flipped, saturationShift: sat, lightnessShift: $0); onChange(p) }
                        ),
                        range: -50...50,
                        step: 1
                    )
                }
            }

            if case .color(let levels) = params.colorMode {
                SimpleLayerEditorDivider()

                DenseSliderControlRow(
                    title: "Levels",
                    value: Binding(
                        get: { Double(levels) },
                        set: { levelsBinding(levels).wrappedValue = Int($0.rounded()) }
                    ),
                    range: 2...8,
                    step: 1
                )
            }

            if case .palette(let colors) = params.colorMode {
                SimpleLayerEditorDivider()
                paletteEditor(colors: colors)
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                DenseSliderControlRow(
                    title: "Threshold",
                    value: thresholdBinding,
                    range: 0.1...0.9,
                    step: 0.05
                )
            } secondary: {
                Text("Lower = darker, higher = brighter")
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text2)
                    .denseSupportingRow("Details")
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                DenseSliderControlRow(
                    title: "Sharpen",
                    value: Binding(
                        get: { params.sharpen * 100 },
                        set: { sharpenBinding.wrappedValue = $0 / 100 }
                    ),
                    range: 0...100,
                    step: 10,
                    unit: "%"
                )
            } secondary: {
                Text("Pre-sharpen to preserve edge detail")
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text2)
                    .denseSupportingRow("Details")
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                DenseSliderControlRow(
                    title: "Contrast",
                    value: Binding(
                        get: { params.contrast * 100 },
                        set: { contrastBinding.wrappedValue = $0 / 100 }
                    ),
                    range: 0...100,
                    step: 10,
                    unit: "%"
                )
            } secondary: {
                Text("Boost contrast before dithering")
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text2)
                    .denseSupportingRow("Details")
            }
        }
    }

    // MARK: - Bindings

    private var algorithmBinding: Binding<DitherAlgorithm> {
        Binding(
            get: { params.algorithm },
            set: { newValue in
                var p = params
                p.algorithm = newValue
                onChange(p)
            }
        )
    }

    private var colorModeTag: Binding<Int> {
        Binding(
            get: {
                switch params.colorMode {
                case .bw: return 0
                case .twoTone: return 1
                case .dominantTwoTone: return 3
                case .color: return 2
                case .palette: return 4
                }
            },
            set: { tag in
                var p = params
                switch tag {
                case 0: p.colorMode = .bw
                case 1: p.colorMode = .twoTone(foreground: (try? CodableColor(hex: "#0251FF")) ?? .black, background: .black)
                case 2: p.colorMode = .color(levels: 4)
                case 3: p.colorMode = .dominantTwoTone(flipped: false)
                case 4: p.colorMode = .palette(VintagePalette.gameBoy)
                default: break
                }
                onChange(p)
            }
        )
    }

    private var bayerLevelBinding: Binding<Int> {
        Binding(
            get: { params.bayerLevel },
            set: { newValue in
                var p = params
                p.bayerLevel = newValue
                onChange(p)
            }
        )
    }

    private var pixelScaleBinding: Binding<Int> {
        Binding(
            get: { params.pixelScale },
            set: { newValue in
                var p = params
                p.pixelScale = newValue
                onChange(p)
            }
        )
    }

    private func foregroundBinding(fg: CodableColor, bg: CodableColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: fg.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.colorMode = .twoTone(foreground: c, background: bg)
                onChange(p)
            }
        )
    }

    private func backgroundBinding(fg: CodableColor, bg: CodableColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: bg.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.colorMode = .twoTone(foreground: fg, background: c)
                onChange(p)
            }
        )
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { params.threshold },
            set: { newValue in
                var p = params
                p.threshold = newValue
                onChange(p)
            }
        )
    }

    private var sharpenBinding: Binding<Double> {
        Binding(
            get: { params.sharpen },
            set: { newValue in
                var p = params
                p.sharpen = newValue
                onChange(p)
            }
        )
    }

    private var contrastBinding: Binding<Double> {
        Binding(
            get: { params.contrast },
            set: { newValue in
                var p = params
                p.contrast = newValue
                onChange(p)
            }
        )
    }

    private func flippedBinding(_ currentFlipped: Bool) -> Binding<Bool> {
        Binding(
            get: { currentFlipped },
            set: { newValue in
                var p = params
                p.colorMode = .dominantTwoTone(flipped: newValue)
                onChange(p)
            }
        )
    }

    private func levelsBinding(_ currentLevels: Int) -> Binding<Int> {
        Binding(
            get: { currentLevels },
            set: { newValue in
                var p = params
                p.colorMode = .color(levels: newValue)
                onChange(p)
            }
        )
    }

    /// Preset dropdown + per-colour editor for `.palette` colour mode.
    /// Preset selection is derived from the current colours — editing a
    /// swatch that no longer matches a preset flips the picker to
    /// `.custom` on the next render. Up to `DitherColorMode.MAX_PALETTE_COLORS`
    /// entries; "+ Add" duplicates the last colour and "−" removes the
    /// last entry (minimum 2 colours to preserve a usable palette).
    @ViewBuilder
    private func paletteEditor(colors: [CodableColor]) -> some View {
        let selectedPreset = VintagePalette.Preset.matching(colors)

        SidebarFullWidthRow("Palette") {
            VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
                Picker("Preset", selection: Binding<VintagePalette.Preset>(
                    get: { selectedPreset },
                    set: { newValue in
                        // Picking the same preset is a no-op. Prevents the
                        // .custom branch below from mutating when the user
                        // didn't actually change anything.
                        guard newValue != selectedPreset else { return }

                        var p = params
                        switch newValue {
                        case .custom:
                            // Seed Custom with the CURRENT colours plus an
                            // extra neutral swatch. Two requirements drive this:
                            //   1. Don't throw away what the user is editing —
                            //      if they were on Game Boy, keep those colours
                            //      as the starting point.
                            //   2. The resulting palette must NOT match any
                            //      preset, otherwise `VintagePalette.Preset.matching()`
                            //      returns that preset on the next render and
                            //      snaps the picker back, silently reverting
                            //      the user's "Custom" click.
                            // Trim to MAX-1 before appending so the neutral
                            // swatch is always kept (a naive prefix(MAX) would
                            // silently drop the appended neutral when the
                            // current palette is already at MAX, leaving the
                            // preset unchanged and the picker snapping back).
                            let base = colors.isEmpty ? VintagePalette.gameBoy : colors
                            let maxBaseCount = DitherColorMode.MAX_PALETTE_COLORS - 1
                            let trimmedBase = Array(base.prefix(maxBaseCount))
                            let seed = trimmedBase + [CodableColor(unchecked: "#808080")]
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

                UserPaletteMenu(currentColors: colors) { applied in
                    var p = params
                    p.colorMode = .palette(applied)
                    onChange(p)
                }

                SidebarPaletteEditor(
                    colors: paletteBinding(currentColors: colors),
                    maxColors: DitherColorMode.MAX_PALETTE_COLORS,
                    minColors: 2,
                    defaultNewColor: colors.last ?? CodableColor(unchecked: "#000000")
                )
            }
        }
    }

    /// Adapter that turns `params.colorMode = .palette([...])` into a
    /// `Binding<[CodableColor]>` for `SidebarPaletteEditor`. The captured
    /// `colors` snapshot is the getter's source of truth each render pass;
    /// the setter routes updates back through `onChange`.
    private func paletteBinding(currentColors colors: [CodableColor]) -> Binding<[CodableColor]> {
        Binding(
            get: { colors },
            set: { newColors in
                var p = params
                p.colorMode = .palette(newColors)
                onChange(p)
            }
        )
    }
}
