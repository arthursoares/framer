import SwiftUI
import FramerCore

// MARK: - Shader Controls

struct ShaderControls: View {
    var params: ShaderLayerParams
    var onChange: (ShaderLayerParams) -> Void

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
            sliderRow(
                label: "Intensity",
                value: params.intensity,
                range: 0...1,
                step: 0.05,
                resetValue: 1.0
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
            case .roughBorder(let roughBorderParams):
                roughBorderControls(roughBorderParams)
            case .filmGrain(let filmGrainParams):
                filmGrainControls(filmGrainParams)
            case .bwFilm(let bwFilmParams):
                bwFilmControls(bwFilmParams)
            }
        }
    }

    @ViewBuilder
    private func bwFilmControls(_ bw: BWFilmShaderParams) -> some View {
        Group {
            ControlRow(label: "Film Response") {
                Picker("Film Response", selection: Binding(
                    get: { bw.response },
                    set: { value in
                        guard case .bwFilm(var current) = params.params else { return }
                        if value == .custom {
                            current.response = .custom
                            onChange(params.withParams(.bwFilm(current)))
                        } else {
                            onChange(params.withParams(.bwFilm(current.applyingResponse(value))))
                        }
                    }
                )) {
                    ForEach(BWFilmResponse.allCases, id: \.self) { response in
                        Text(response.label).tag(response)
                    }
                }
                .pickerStyle(.menu)
            }

            bwSectionHeader("SENSITIVITY")
            bwFilmSlider("Red", bw.sensRed, resetValue: bw.response.sensitivities.r, group: .film) { v, p in var u = p; u.sensRed = v; return u }
            bwFilmSlider("Yellow", bw.sensYellow, resetValue: bw.response.sensitivities.ye, group: .film) { v, p in var u = p; u.sensYellow = v; return u }
            bwFilmSlider("Green", bw.sensGreen, resetValue: bw.response.sensitivities.g, group: .film) { v, p in var u = p; u.sensGreen = v; return u }
            bwFilmSlider("Cyan", bw.sensCyan, resetValue: bw.response.sensitivities.cy, group: .film) { v, p in var u = p; u.sensCyan = v; return u }
            bwFilmSlider("Blue", bw.sensBlue, resetValue: bw.response.sensitivities.b, group: .film) { v, p in var u = p; u.sensBlue = v; return u }
            bwFilmSlider("Magenta", bw.sensMagenta, resetValue: bw.response.sensitivities.mg, group: .film) { v, p in var u = p; u.sensMagenta = v; return u }
        }

        Group {
            bwSectionHeader("TONALITY")
            bwFilmSlider("Brightness", bw.brightness) { v, p in var u = p; u.brightness = v; return u }
            bwFilmSlider("Brightness Highlights", bw.brightnessHighlights) { v, p in var u = p; u.brightnessHighlights = v; return u }
            bwFilmSlider("Brightness Midtones", bw.brightnessMidtones) { v, p in var u = p; u.brightnessMidtones = v; return u }
            bwFilmSlider("Brightness Shadows", bw.brightnessShadows) { v, p in var u = p; u.brightnessShadows = v; return u }
            bwFilmSlider("Contrast", bw.contrast) { v, p in var u = p; u.contrast = v; return u }
            bwFilmSlider("Protect Highlights", bw.protectHighlights, range: 0...100) { v, p in var u = p; u.protectHighlights = v; return u }
            bwFilmSlider("Protect Shadows", bw.protectShadows, range: 0...100) { v, p in var u = p; u.protectShadows = v; return u }
        }

        Group {
            bwSectionHeader("STRUCTURE")
            bwFilmSlider("Structure", bw.structure) { v, p in var u = p; u.structure = v; return u }
            bwFilmSlider("Structure Highlights", bw.structureHighlights) { v, p in var u = p; u.structureHighlights = v; return u }
            bwFilmSlider("Structure Midtones", bw.structureMidtones) { v, p in var u = p; u.structureMidtones = v; return u }
            bwFilmSlider("Structure Shadows", bw.structureShadows) { v, p in var u = p; u.structureShadows = v; return u }
            bwFilmSlider("Fine Structure", bw.fineStructure, range: 0...100) { v, p in var u = p; u.fineStructure = v; return u }
        }

        Group {
            bwSectionHeader("LEVELS & CURVES")
            bwFilmSlider("Gamma", bw.curveGamma, range: -1...1, step: 0.02, group: .film) { v, p in var u = p; u.curveGamma = v; return u }
            bwFilmSlider("Black Point", bw.curveLowX, range: 0...0.5, step: 0.01, group: .film) { v, p in var u = p; u.curveLowX = v; return u }
            bwFilmSlider("Black Lift", bw.curveLowY, range: 0...0.5, step: 0.01, resetValue: bw.response.measuredCurve?.lowY ?? 0, group: .film) { v, p in var u = p; u.curveLowY = v; return u }
            bwFilmSlider("White Point", bw.curveHighX, range: 0.5...1, step: 0.01, resetValue: 1, group: .film) { v, p in var u = p; u.curveHighX = v; return u }
            bwFilmSlider("White Cap", bw.curveHighY, range: 0.5...1, step: 0.01, resetValue: bw.response.measuredCurve?.highY ?? 1, group: .film) { v, p in var u = p; u.curveHighY = v; return u }
            if !bw.curvePoints.isEmpty {
                ControlRow(label: "Film Curve") {
                    Button {
                        guard case .bwFilm(var current) = params.params else { return }
                        current.curvePoints = []
                        current.curveLowY = 0
                        current.curveHighY = 1
                        current.response = .custom
                        onChange(params.withParams(.bwFilm(current)))
                    } label: {
                        Label("\(bw.curvePoints.count) points · Reset", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset film curve to linear")
                }
            }
        }

        Group {
            bwSectionHeader("TONING")
            ControlRow(label: "Preset") {
                Picker("Toning", selection: Binding(
                    get: { bw.toningPreset },
                    set: { value in
                        guard case .bwFilm(var current) = params.params else { return }
                        if value == .custom {
                            current.toningPreset = .custom
                            onChange(params.withParams(.bwFilm(current)))
                        } else {
                            onChange(params.withParams(.bwFilm(current.applyingToningPreset(value))))
                        }
                    }
                )) {
                    ForEach(BWToningPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            }
            bwFilmSlider("Strength", bw.toningStrength, range: 0...100, resetValue: bw.toningPreset.toning.strength, group: .toning) { v, p in var u = p; u.toningStrength = v; return u }
            bwFilmSlider("Silver Hue", bw.toneHueHigh, range: 0...360, resetValue: bw.toningPreset.toning.hueHigh, group: .toning) { v, p in var u = p; u.toneHueHigh = v; return u }
            bwFilmSlider("Silver Toning", bw.toneStrengthHigh, range: 0...100, resetValue: bw.toningPreset.toning.strengthHigh, group: .toning) { v, p in var u = p; u.toneStrengthHigh = v; return u }
            bwFilmSlider("Paper Hue", bw.toneHueLow, range: 0...360, resetValue: bw.toningPreset.toning.hueLow, group: .toning) { v, p in var u = p; u.toneHueLow = v; return u }
            bwFilmSlider("Paper Toning", bw.toneStrengthLow, range: 0...100, resetValue: bw.toningPreset.toning.strengthLow, group: .toning) { v, p in var u = p; u.toneStrengthLow = v; return u }
            bwFilmSlider("Balance", bw.toneBalance, resetValue: bw.toningPreset.toning.balance, group: .toning) { v, p in var u = p; u.toneBalance = v; return u }
        }

        Group {
            bwSectionHeader("VIGNETTE")
            bwFilmSlider("Vignette", bw.vigStrength) { v, p in var u = p; u.vigStrength = v; return u }
            bwFilmSlider("Vignette Size", bw.vigSize, range: 0...100, resetValue: 50) { v, p in var u = p; u.vigSize = v; return u }
            bwFilmSlider("Vignette Shape", bw.vigShape, range: 1...5, step: 0.1, resetValue: 3) { v, p in var u = p; u.vigShape = v; return u }
        }

        Group {
            bwSectionHeader("BURN EDGES")
            bwFilmSlider("Burn Top", bw.beStrengthTop, range: 0...100) { v, p in var u = p; u.beStrengthTop = v; return u }
            bwFilmSlider("Burn Bottom", bw.beStrengthBottom, range: 0...100) { v, p in var u = p; u.beStrengthBottom = v; return u }
            bwFilmSlider("Burn Left", bw.beStrengthLeft, range: 0...100) { v, p in var u = p; u.beStrengthLeft = v; return u }
            bwFilmSlider("Burn Right", bw.beStrengthRight, range: 0...100) { v, p in var u = p; u.beStrengthRight = v; return u }
            bwFilmSlider("Size (all edges)", bw.beSizeTop, range: 0...100, resetValue: 25) { v, p in
                var u = p; u.beSizeTop = v; u.beSizeBottom = v; u.beSizeLeft = v; u.beSizeRight = v; return u
            }
            bwFilmSlider("Transition (all edges)", bw.beTransitionTop, range: 0...100, resetValue: 50) { v, p in
                var u = p; u.beTransitionTop = v; u.beTransitionBottom = v; u.beTransitionLeft = v; u.beTransitionRight = v; return u
            }
        }
    }

    private func bwSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .tracking(1.5)
            .foregroundStyle(Color.text3)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum BWDialGroup { case film, toning, plain }

    private func bwFilmSlider(
        _ label: String,
        _ value: Double,
        range: ClosedRange<Double> = -100...100,
        step: Double = 1,
        resetValue: Double = 0,
        group: BWDialGroup = .plain,
        update: @escaping (Double, BWFilmShaderParams) -> BWFilmShaderParams
    ) -> some View {
        sliderRow(
            label: label,
            value: value,
            range: expandedRange(range, including: value),
            step: step,
            resetValue: resetValue
        ) { newValue in
            guard case .bwFilm(let current) = params.params else { return }
            var updated = update(newValue, current)
            switch group {
            case .film: updated.response = .custom
            case .toning: updated.toningPreset = .custom
            case .plain: break
            }
            onChange(params.withParams(.bwFilm(updated)))
        }
    }

    @ViewBuilder
    private func asciiControls(_ asciiParams: ASCIIShaderParams) -> some View {
        sliderRow(
            label: "Cell Size",
            value: Double(asciiParams.cellSize),
            range: expandedRange(4...24, including: Double(asciiParams.cellSize)),
            step: 1,
            resetValue: Double(ASCIIShaderParams().cellSize)
        ) { value in
            updateASCII(asciiParams, cellSize: Int(value.rounded()))
        }

        sliderRow(
            label: "Edge Bias",
            value: asciiParams.edgeBias,
            range: expandedRange(0...1, including: asciiParams.edgeBias),
            step: 0.05,
            resetValue: ASCIIShaderParams().edgeBias
        ) { value in
            updateASCII(asciiParams, edgeBias: value)
        }

        sliderRow(
            label: "Exposure",
            value: asciiParams.exposure,
            range: expandedRange(0...5, including: asciiParams.exposure),
            step: 0.1,
            resetValue: ASCIIShaderParams().exposure
        ) { value in
            updateASCII(asciiParams, exposure: value)
        }

        sliderRow(
            label: "Attenuation",
            value: asciiParams.attenuation,
            range: expandedRange(0...5, including: asciiParams.attenuation),
            step: 0.1,
            resetValue: ASCIIShaderParams().attenuation
        ) { value in
            updateASCII(asciiParams, attenuation: value)
        }

        sliderRow(
            label: "Black Level",
            value: asciiParams.blackLevel,
            range: 0...1,
            step: 0.05,
            resetValue: ASCIIShaderParams().blackLevel
        ) { value in
            updateASCII(asciiParams, blackLevel: value)
        }

        asciiCharactersControl(asciiParams)
        asciiFontControl(asciiParams)

        ControlRow(label: "High Detail") {
            Toggle("16×16 atlas", isOn: Binding(
                get: { asciiParams.highDetail },
                set: { updateASCII(asciiParams, highDetail: $0) }
            ))
            .labelsHidden()
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
                step: 1,
                resetValue: 0
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
                step: 1,
                resetValue: 0
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

    /// Character palette picker + Custom text field + ramp preview. Mirrors
    /// the desktop editor in LayerListSection so the two feel identical; see
    /// that file for the rationale behind the preset-derived-from-string
    /// approach (no separate persisted enum, picker always re-syncs with the
    /// stored characters).
    @ViewBuilder
    private func asciiCharactersControl(_ asciiParams: ASCIIShaderParams) -> some View {
        let selectedPreset = ASCIIPreset.matching(asciiParams.characters)
        let characterCount = (asciiParams.characters ?? "").count

        VStack(alignment: .leading, spacing: 8) {
            ControlRow(label: "Characters") {
                Picker("", selection: Binding<ASCIIPreset>(
                    get: { selectedPreset },
                    set: { newValue in
                        switch newValue {
                        case .default:
                            updateASCII(asciiParams, characters: .some(nil))
                        case .custom:
                            // Same non-preset-seed logic as desktop: seeding
                            // with Classic's literal makes `matching(...)`
                            // flip the picker back to Classic on the next
                            // render. A short non-preset starter lets the
                            // user land on Custom and then edit from there.
                            let current = asciiParams.characters
                            let alreadyCustom = current.map { ASCIIPreset.matching($0) == .custom } ?? false
                            let seed: String = alreadyCustom ? (current ?? "") : " .:*@"
                            updateASCII(asciiParams, characters: .some(seed))
                        default:
                            updateASCII(asciiParams, characters: .some(newValue.characters))
                        }
                    }
                )) {
                    ForEach(ASCIIPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if selectedPreset == .custom {
                TextField(
                    " .:-=+*#%@",
                    text: Binding(
                        get: { asciiParams.characters ?? "" },
                        set: { newValue in
                            let trimmed = String(newValue.prefix(10))
                            updateASCII(asciiParams, characters: .some(trimmed.isEmpty ? nil : trimmed))
                        }
                    )
                )
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)

                Text("\(characterCount) / 10")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                asciiRampPreview(for: asciiParams.characters ?? "")
            }
        }
    }

    @ViewBuilder
    private func asciiRampPreview(for characters: String) -> some View {
        let glyphs = ASCIIAtlasGenerator.mappedFillGlyphs(characters)
        HStack(spacing: 2) {
            ForEach(0..<glyphs.count, id: \.self) { i in
                let lum = Double(i) / Double(max(1, glyphs.count - 1))
                ZStack {
                    Rectangle()
                        .fill(Color(white: lum))
                    Text(String(glyphs[i]))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(lum < 0.5 ? Color.white : Color.black)
                }
                .frame(width: 22, height: 22)
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
            }
        }
    }

    private func updateASCII(
        _ asciiParams: ASCIIShaderParams,
        cellSize: Int? = nil,
        edgeBias: Double? = nil,
        colorMode: ASCIIColorMode? = nil,
        invert: Bool? = nil,
        exposure: Double? = nil,
        attenuation: Double? = nil,
        blackLevel: Double? = nil,
        characters: String?? = nil,
        fontName: String?? = nil,
        highDetail: Bool? = nil
    ) {
        onChange(params.withParams(.ascii(ASCIIShaderParams(
            cellSize: cellSize ?? asciiParams.cellSize,
            edgeBias: edgeBias ?? asciiParams.edgeBias,
            colorMode: colorMode ?? asciiParams.colorMode,
            invert: invert ?? asciiParams.invert,
            exposure: exposure ?? asciiParams.exposure,
            attenuation: attenuation ?? asciiParams.attenuation,
            blackLevel: blackLevel ?? asciiParams.blackLevel,
            characters: characters ?? asciiParams.characters,
            fontName: fontName ?? asciiParams.fontName,
            highDetail: highDetail ?? asciiParams.highDetail
        ))))
    }

    /// Mobile font picker. `UIFont.familyNames` is the system-installed list;
    /// nil `fontName` → "System Default" sentinel.
    @ViewBuilder
    private func asciiFontControl(_ asciiParams: ASCIIShaderParams) -> some View {
        let families = Self.systemFontFamilies
        ControlRow(label: "Font") {
            Picker("", selection: Binding<String>(
                get: { asciiParams.fontName ?? "" },
                set: { newValue in
                    updateASCII(asciiParams, fontName: .some(newValue.isEmpty ? nil : newValue))
                }
            )) {
                Text("System Default").tag("")
                ForEach(families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private static let systemFontFamilies: [String] = {
        UIFont.familyNames.sorted()
    }()

    @ViewBuilder
    private func crimewaveControls(_ crimewaveParams: CrimewaveShaderParams) -> some View {
        styleSliderRows(
            [("Neon", crimewaveParams.neon, 0...2, 0.05, CrimewaveShaderParams().neon),
             ("Softness", crimewaveParams.softness, 0...1, 0.05, CrimewaveShaderParams().softness),
             ("Contrast", crimewaveParams.contrast, 0.5...3, 0.05, CrimewaveShaderParams().contrast),
             ("Grain", crimewaveParams.grain, 0...1, 0.05, CrimewaveShaderParams().grain)]
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
            [("Contrast", narcParams.contrast, 0.5...3, 0.05, NarcShaderParams().contrast),
             ("Crush", narcParams.crush, 0...1, 0.05, NarcShaderParams().crush),
             ("Temperature", narcParams.temperature, -1...1, 0.05, NarcShaderParams().temperature),
             ("Grain", narcParams.grain, 0...1, 0.05, NarcShaderParams().grain)]
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
            [("Warmth", shibaParams.warmth, -1...1, 0.05, ShibaShaderParams().warmth),
             ("Softness", shibaParams.softness, 0...1, 0.05, ShibaShaderParams().softness),
             ("Saturation", shibaParams.saturation, 0...2, 0.05, ShibaShaderParams().saturation),
             ("Grain", shibaParams.grain, 0...1, 0.05, ShibaShaderParams().grain)]
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

        // Span criterion: Luminance (classic) + 4 Kim Asendorf modes. See
        // LayerListSection.pixelSortControls for the rationale.
        ControlRow(label: "Span Mode") {
            Picker("", selection: Binding(
                get: { pixelSortParams.spanMode },
                set: { value in
                    var updated = pixelSortParams; updated.spanMode = value
                    onChange(params.withParams(.pixelSort(updated)))
                }
            )) {
                Text("Luminance").tag(PixelSortSpanMode.luminance)
                Text("Black (Kim)").tag(PixelSortSpanMode.kimBlack)
                Text("White (Kim)").tag(PixelSortSpanMode.kimWhite)
                Text("Bright (Kim)").tag(PixelSortSpanMode.kimBright)
                Text("Dark (Kim)").tag(PixelSortSpanMode.kimDark)
            }
            .pickerStyle(.menu)
        }

        // Sort criterion — what each pixel is ranked by inside a span.
        // Orthogonal to span mode.
        ControlRow(label: "Sort By") {
            Picker("", selection: Binding(
                get: { pixelSortParams.sortBy },
                set: { value in
                    var updated = pixelSortParams; updated.sortBy = value
                    onChange(params.withParams(.pixelSort(updated)))
                }
            )) {
                Text("Luminance").tag(PixelSortCriterion.luminance)
                Text("Brightness").tag(PixelSortCriterion.brightness)
                Text("Hue").tag(PixelSortCriterion.hue)
            }
            .pickerStyle(.menu)
        }

        sliderRow(
            label: "Threshold",
            value: pixelSortParams.threshold,
            range: expandedRange(0...1, including: pixelSortParams.threshold),
            step: 0.05,
            resetValue: PixelSortShaderParams().threshold
        ) { value in
            var updated = pixelSortParams
            updated.threshold = value
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            label: "Span",
            value: Double(pixelSortParams.span),
            range: expandedRange(4...256, including: Double(pixelSortParams.span)),
            step: 1,
            resetValue: Double(PixelSortShaderParams().span)
        ) { value in
            var updated = pixelSortParams
            updated.span = Int(value.rounded())
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            label: "Randomness",
            value: pixelSortParams.randomness,
            range: expandedRange(0...1, including: pixelSortParams.randomness),
            step: 0.05,
            resetValue: PixelSortShaderParams().randomness
        ) { value in
            var updated = pixelSortParams; updated.randomness = value
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            label: "Amount",
            value: pixelSortParams.amount,
            range: expandedRange(0...1, including: pixelSortParams.amount),
            step: 0.05,
            resetValue: PixelSortShaderParams().amount
        ) { value in
            var updated = pixelSortParams
            updated.amount = value
            onChange(params.withParams(.pixelSort(updated)))
        }

        ControlRow(label: "Reverse") {
            Toggle("", isOn: Binding(
                get: { pixelSortParams.reverse },
                set: { value in
                    var updated = pixelSortParams; updated.reverse = value
                    onChange(params.withParams(.pixelSort(updated)))
                }
            ))
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func crtControls(_ crtParams: CRTShaderParams) -> some View {
        sliderRow(
            label: "Curvature",
            value: crtParams.curvature,
            range: expandedRange(1...10, including: crtParams.curvature),
            step: 0.5,
            resetValue: CRTShaderParams().curvature
        ) { value in
            var updated = crtParams; updated.curvature = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Line Size",
            value: Double(crtParams.lineSize),
            range: expandedRange(0...4, including: Double(crtParams.lineSize)),
            step: 1,
            resetValue: Double(CRTShaderParams().lineSize)
        ) { value in
            var updated = crtParams; updated.lineSize = Int(value.rounded())
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Line Strength",
            value: crtParams.lineStrength,
            range: expandedRange(0...5, including: crtParams.lineStrength),
            step: 0.1,
            resetValue: CRTShaderParams().lineStrength
        ) { value in
            var updated = crtParams; updated.lineStrength = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Brightness",
            value: crtParams.brightness,
            range: expandedRange(-1...1, including: crtParams.brightness),
            step: 0.05,
            resetValue: CRTShaderParams().brightness
        ) { value in
            var updated = crtParams; updated.brightness = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            label: "Vignette",
            value: crtParams.vignette,
            range: expandedRange(1...100, including: crtParams.vignette),
            step: 1,
            resetValue: CRTShaderParams().vignette
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
            step: 0.1,
            resetValue: HalftoneShaderParams().dotSize
        ) { value in
            var updated = halftoneParams; updated.dotSize = value
            onChange(params.withParams(.halftone(updated)))
        }
        sliderRow(
            label: "Contrast",
            value: halftoneParams.contrast,
            range: expandedRange(0.1...3, including: halftoneParams.contrast),
            step: 0.1,
            resetValue: HalftoneShaderParams().contrast
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
            step: 1,
            resetValue: Double(KuwaharaShaderParams().kernelSize)
        ) { value in
            var updated = kuwaharaParams; updated.kernelSize = Int(value.rounded())
            onChange(params.withParams(.kuwahara(updated)))
        }
        sliderRow(
            label: "Softness",
            value: kuwaharaParams.softness,
            range: expandedRange(0...1, including: kuwaharaParams.softness),
            step: 0.05,
            resetValue: KuwaharaShaderParams().softness
        ) { value in
            var updated = kuwaharaParams; updated.softness = value
            onChange(params.withParams(.kuwahara(updated)))
        }
    }

@ViewBuilder
    private func roughBorderControls(_ roughBorderParams: RoughBorderShaderParams) -> some View {
        ControlRow(label: "Type") {
            Picker("Type", selection: Binding(
                get: { roughBorderParams.borderType },
                set: { value in
                    var updated = roughBorderParams; updated.borderType = value
                    onChange(params.withParams(.roughBorder(updated)))
                }
            )) {
                ForEach(RoughBorderType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.menu)
        }
        sliderRow(
            label: "Size",
            value: roughBorderParams.size * 2000,
            range: expandedRange(2...100, including: roughBorderParams.size * 2000),
            step: 1,
            resetValue: RoughBorderShaderParams().size * 2000
        ) { value in
            var updated = roughBorderParams; updated.size = value / 2000
            onChange(params.withParams(.roughBorder(updated)))
        }
        sliderRow(
            label: "Spread",
            value: roughBorderParams.spread,
            range: expandedRange(0...1, including: roughBorderParams.spread),
            step: 0.05,
            resetValue: RoughBorderShaderParams().spread
        ) { value in
            var updated = roughBorderParams; updated.spread = value
            onChange(params.withParams(.roughBorder(updated)))
        }
        sliderRow(
            label: "Roughness",
            value: roughBorderParams.roughness,
            range: expandedRange(0...1, including: roughBorderParams.roughness),
            step: 0.05,
            resetValue: RoughBorderShaderParams().roughness
        ) { value in
            var updated = roughBorderParams; updated.roughness = value
            onChange(params.withParams(.roughBorder(updated)))
        }
        seedRow(
            seed: roughBorderParams.seed,
            varyPerImage: roughBorderParams.varyPerImage
        ) { newSeed in
            var updated = roughBorderParams; updated.seed = newSeed
            onChange(params.withParams(.roughBorder(updated)))
        }
        ControlRow(label: "Vary per Image") {
            Toggle("", isOn: Binding(
                get: { roughBorderParams.varyPerImage },
                set: { value in
                    var updated = roughBorderParams; updated.varyPerImage = value
                    onChange(params.withParams(.roughBorder(updated)))
                }
            ))
            .labelsHidden()
        }
        ControlRow(label: "Color") {
            ColorPicker("", selection: Binding(
                get: { Color(cgColor: roughBorderParams.borderColor.cgColor) },
                set: { newColor in
                    guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                    var updated = roughBorderParams; updated.borderColor = codable
                    onChange(params.withParams(.roughBorder(updated)))
                }
            ))
            .labelsHidden()
        }
    }

    private func seedRow(
        seed: Int,
        varyPerImage: Bool,
        onSeed: @escaping (Int) -> Void
    ) -> some View {
        ControlRow(label: varyPerImage ? "Seed · varies" : "Seed") {
            HStack(spacing: 8) {
                TextField("", value: Binding(get: { seed }, set: { onSeed(max(0, $0)) }), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .accessibilityLabel("Seed value")
                Button {
                    onSeed(Int.random(in: 0...9999))
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle seed")
            }
            .opacity(varyPerImage ? 0.4 : 1.0)
            .disabled(varyPerImage)
        }
    }

    @ViewBuilder
    private func filmGrainControls(_ filmGrainParams: FilmGrainShaderParams) -> some View {
        ControlRow(label: "Film Stock") {
            Picker("Film Stock", selection: Binding(
                get: { filmGrainParams.stock },
                set: { value in
                    guard case .filmGrain(var current) = params.params else { return }
                    if value == .custom {
                        current.stock = .custom
                        onChange(params.withParams(.filmGrain(current)))
                    } else {
                        onChange(params.withParams(.filmGrain(current.applyingStockProfile(value))))
                    }
                }
            )) {
                ForEach(FilmGrainStock.allCases, id: \.self) { stock in
                    Text(stock.label).tag(stock)
                }
            }
            .pickerStyle(.menu)
        }
        bwSectionHeader("GRAIN")
        sliderRow(
            label: "Grain per Pixel",
            value: filmGrainParams.grainsPerPixel,
            range: expandedRange(1...500, including: filmGrainParams.grainsPerPixel),
            step: 1,
            resetValue: filmGrainParams.stock.grainProfile.grainsPerPixel
        ) { value in
            guard case .filmGrain(var current) = params.params else { return }
            current.grainsPerPixel = value
            current.stock = .custom
            onChange(params.withParams(.filmGrain(current)))
        }
        sliderRow(
            label: "Soft / Hard",
            value: filmGrainParams.softness,
            range: expandedRange(0...1, including: filmGrainParams.softness),
            step: 0.05,
            resetValue: filmGrainParams.stock.grainProfile.softness
        ) { value in
            guard case .filmGrain(var current) = params.params else { return }
            current.softness = value
            current.stock = .custom
            onChange(params.withParams(.filmGrain(current)))
        }
        bwSectionHeader("TONAL PROTECTION")
        sliderRow(
            label: "Protect Highlights",
            value: filmGrainParams.protectHighlights,
            range: expandedRange(0...1, including: filmGrainParams.protectHighlights),
            step: 0.05,
            resetValue: FilmGrainShaderParams().protectHighlights
        ) { value in
            var updated = filmGrainParams; updated.protectHighlights = value
            onChange(params.withParams(.filmGrain(updated)))
        }
        sliderRow(
            label: "Protect Shadows",
            value: filmGrainParams.protectShadows,
            range: expandedRange(0...1, including: filmGrainParams.protectShadows),
            step: 0.05,
            resetValue: FilmGrainShaderParams().protectShadows
        ) { value in
            var updated = filmGrainParams; updated.protectShadows = value
            onChange(params.withParams(.filmGrain(updated)))
        }
        bwSectionHeader("VARIATION")
        seedRow(
            seed: filmGrainParams.seed,
            varyPerImage: filmGrainParams.varyPerImage
        ) { newSeed in
            var updated = filmGrainParams; updated.seed = newSeed
            onChange(params.withParams(.filmGrain(updated)))
        }
        ControlRow(label: "Vary per Image") {
            Toggle("", isOn: Binding(
                get: { filmGrainParams.varyPerImage },
                set: { value in
                    var updated = filmGrainParams; updated.varyPerImage = value
                    onChange(params.withParams(.filmGrain(updated)))
                }
            ))
            .labelsHidden()
        }
    }

        @ViewBuilder
    private func distantPastControls(_ distantPastParams: DistantPastShaderParams) -> some View {
        styleSliderRows(
            [("Palette Depth", Double(distantPastParams.paletteDepth), 2...6, 1, Double(DistantPastShaderParams().paletteDepth)),
             ("Fade", distantPastParams.fade, 0...1, 0.05, DistantPastShaderParams().fade),
             ("Softness", distantPastParams.softness, 0...1, 0.05, DistantPastShaderParams().softness),
             ("Grain", distantPastParams.grain, 0...1, 0.05, DistantPastShaderParams().grain)]
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
        _ rows: [(String, Double, ClosedRange<Double>, Double, Double)],
        onSet: @escaping (String, Double) -> Void
    ) -> some View {
        ForEach(rows, id: \.0) { row in
            sliderRow(
                label: row.0,
                value: row.1,
                range: expandedRange(row.2, including: row.1),
                step: row.3,
                resetValue: row.4
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
        resetValue: Double? = nil,
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
        .onTapGesture(count: 2) {
            if let resetValue {
                onSet(min(range.upperBound, max(range.lowerBound, resetValue)))
            }
        }
    }
}

