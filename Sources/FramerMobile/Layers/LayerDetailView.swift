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
        case .gpuEffect(let params):
            GPUEffectControls(params: params) { layer = .gpuEffect($0) }
        }
    }
}

/// Mobile blend-mode + opacity picker used by every visual adjustment
/// layer's inspector. Mirrors `BlendModeControls` on the desktop.
private struct MobileBlendModeControls: View {
    @Binding var blendMode: LayerBlendMode
    @Binding var opacity: Double

    var body: some View {
        ControlRow(label: "Blend") {
            Picker("", selection: $blendMode) {
                ForEach(LayerBlendMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        ControlRow(label: "Opacity (\(Int((opacity * 100).rounded()))%)") {
            Slider(value: $opacity, in: 0...1, step: 0.01)
        }
    }
}

private struct GPUEffectControls: View {
    var params: GPUEffectLayerParams
    var onChange: (GPUEffectLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Kind is fixed at layer creation (each variant is its own
            // layer-add menu entry). Show read-only for orientation; don't
            // offer a Picker to switch variants mid-flight.
            ControlRow(label: "Effect") {
                Label(params.kind.label, systemImage: params.kind.menuIcon)
            }
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

            // Per-variant pruning mirrors the desktop sidebar: only show
            // controls whose uniforms the variant's shader actually reads
            // (see GPUEffectKind capability flags).
            if params.kind.usesGeometry {
                ControlRow(label: "Scale") {
                    HStack {
                        Slider(value: scaleBinding, in: 0.5...2.0)
                        Text(String(format: "%.2f", scaleBinding.wrappedValue))
                            .font(AppFont.mono(12))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .onTapGesture(count: 2) { scaleBinding.wrappedValue = defaultGeometry.scale }

                ControlRow(label: "Spacing") {
                    HStack {
                        Slider(value: spacingBinding, in: 1...8)
                        Text(String(format: "%.1f", spacingBinding.wrappedValue))
                            .font(AppFont.mono(12))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .onTapGesture(count: 2) { spacingBinding.wrappedValue = defaultGeometry.spacing }
            }

            // Output Width is the effect's render resolution — consumed by
            // every renderer family, so it stays visible for all kinds.
            ControlRow(label: "Output Width") {
                HStack {
                    Slider(value: outputWidthBinding, in: 120...640, step: 1)
                    Text("\(Int(outputWidthBinding.wrappedValue))")
                        .font(AppFont.mono(12))
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .onTapGesture(count: 2) { outputWidthBinding.wrappedValue = Double(defaultGeometry.outputWidth) }

            if params.kind.usesColorModeAndFgBg {
                ControlRow(label: "Color Mode") {
                    Picker("Color Mode", selection: colorModeBinding) {
                        Text("Source").tag(GPUEffectColorMode.source)
                        Text("FG/BG").tag(GPUEffectColorMode.foregroundBackground)
                        Text("Mono").tag(GPUEffectColorMode.monochrome)
                        // Offered only where the variant's shader quantizes
                        // against the palette uniform (framerPalettePick).
                        if params.kind.usesPalette {
                            Text("Palette").tag(GPUEffectColorMode.palette)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if params.kind.usesPalette,
                   Self.color(for: params.params).mode == .palette {
                    gpuPaletteEditor
                }
            }

            if params.kind.usesBackgroundIntensity || params.kind.usesColorModeAndFgBg {
                SliderRow(label: "Background", value: backgroundIntensityBinding, range: 0...1, step: 0.05, resetValue: defaultColor.backgroundIntensity)
            }

            if params.kind.usesCommonAdjustments {
                SliderRow(label: "Brightness", value: commonBinding(\.brightness), range: -1...1, step: 0.05, resetValue: defaultCommon.brightness)
                SliderRow(label: "Contrast", value: commonBinding(\.contrast), range: 0...3, step: 0.05, resetValue: defaultCommon.contrast)
                SliderRow(label: "Saturation", value: commonBinding(\.saturation), range: 0...2, step: 0.05, resetValue: defaultCommon.saturation)
                SliderRow(label: "Hue", value: commonBinding(\.hueRotation), range: -1...1, step: 0.05, resetValue: defaultCommon.hueRotation)
                // (No Sharpness slider — the field was retired from the
                // model entirely; no bucket shader ever consumed it.)
                SliderRow(label: "Gamma", value: commonBinding(\.gamma), range: 0.2...2, step: 0.05, resetValue: defaultCommon.gamma)
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .ascii {
                ControlRow(label: "Character Set") {
                    Picker("Character Set", selection: characterSetBinding) {
                        Text("ASCII").tag(GPUEffectCharacterSet.classicASCII)
                        Text("Blocks").tag(GPUEffectCharacterSet.blocks)
                        Text("Binary").tag(GPUEffectCharacterSet.binary)
                        Text("Dense").tag(GPUEffectCharacterSet.dense)
                    }
                    .pickerStyle(.menu)
                }

                SliderRow(label: "Intensity", value: textCellBinding(\.intensity), range: 0...1, step: 0.05, resetValue: defaultTextCell.intensity)

                ControlRow(label: "Foreground") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.foreground ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.foreground = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }

                ControlRow(label: "Background") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.background ?? CodableColor(unchecked: "#101010")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.background = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .dots {
                ControlRow(label: "Dot Shape") {
                    Picker("Dot Shape", selection: dotShapeBinding) {
                        Text("Circle").tag(DotShape.circle)
                        Text("Square").tag(DotShape.square)
                        Text("Diamond").tag(DotShape.diamond)
                    }
                    .pickerStyle(.menu)
                }

                ControlRow(label: "Grid") {
                    Picker("Grid", selection: dotGridBinding) {
                        Text("Square").tag(DotGridType.square)
                        Text("Hex").tag(DotGridType.hex)
                    }
                    .pickerStyle(.menu)
                }

                SliderRow(label: "Dot Size", value: textCellBinding(\.sizeMultiplier), range: 0.1...2.0, step: 0.05, resetValue: defaultTextCell.sizeMultiplier)
                SliderRow(label: "Intensity", value: textCellBinding(\.intensity), range: 0...1, step: 0.05, resetValue: defaultTextCell.intensity)

                ControlRow(label: "Invert") {
                    Toggle("Invert", isOn: textInvertBinding)
                        .labelsHidden()
                }

                ControlRow(label: "Foreground") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.foreground ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.foreground = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }

                ControlRow(label: "Background") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.background ?? CodableColor(unchecked: "#111111")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.background = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .blockify {
                ControlRow(label: "Style") {
                    Picker("Style", selection: blockStyleBinding) {
                        Text("Solid").tag(BlockStyle.solid)
                        Text("Shaded").tag(BlockStyle.shaded)
                        Text("Outlined").tag(BlockStyle.outlined)
                    }
                    .pickerStyle(.menu)
                }

                SliderRow(label: "Border Width", value: blockBorderWidthBinding, range: 0...1, step: 0.05, resetValue: defaultTextCell.borderWidth)

                ControlRow(label: "Foreground") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.foreground ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.foreground = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }

                ControlRow(label: "Background") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.background ?? CodableColor(unchecked: "#111111")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.background = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }

                ControlRow(label: "Border Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.borderColor ?? CodableColor(unchecked: "#00FFAA")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.borderColor = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .matrixRain {
                SliderRow(label: "Speed", value: matrixBinding(\.speed), range: 0...1, step: 0.05, resetValue: defaultTextCell.speed)
                SliderRow(label: "Trail", value: matrixBinding(\.trailLength), range: 0...1, step: 0.05, resetValue: defaultTextCell.trailLength)
                SliderRow(label: "Glow", value: matrixBinding(\.glow), range: 0...1, step: 0.05, resetValue: defaultTextCell.glow)
                SliderRow(label: "BG Opacity", value: matrixBinding(\.backgroundOpacity), range: 0...1, step: 0.05, resetValue: defaultTextCell.backgroundOpacity)
                // Threshold slider dropped — see LayerListSection.swift for
                // rationale (dead control: GPU encoder writes trailLength to
                // the shader's `threshold` uniform, never params.threshold).

                ControlRow(label: "Direction") {
                    Picker("Direction", selection: matrixDirectionBinding) {
                        Text("Down").tag(TextCellFlowDirection.down)
                        Text("Up").tag(TextCellFlowDirection.up)
                        Text("Left").tag(TextCellFlowDirection.left)
                        Text("Right").tag(TextCellFlowDirection.right)
                    }
                    .pickerStyle(.menu)
                }

                ControlRow(label: "Rain Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.rainColor ?? CodableColor(unchecked: "#00FF66")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.rainColor = codable
                            onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .glitch(let common, let geometry, let color, let payload) = params.params,
               params.kind == .pixelSort {
                ControlRow(label: "Direction") {
                    Picker("Direction", selection: glitchDirectionBinding) {
                        Text("Horizontal").tag(GlitchDirection.horizontal)
                        Text("Vertical").tag(GlitchDirection.vertical)
                    }
                    .pickerStyle(.menu)
                }

                ControlRow(label: "Sort Mode") {
                    Picker("Sort Mode", selection: sortModeBinding) {
                        Text("Brightness").tag(PixelSortMode.brightness)
                        Text("Luminance").tag(PixelSortMode.luminance)
                        Text("Hue").tag(PixelSortMode.hue)
                    }
                    .pickerStyle(.menu)
                }

                // Threshold (luminance cutoff for sortable pixels) and
                // Amount (blend of sorted vs. original) mirror the desktop
                // sidebar.
                SliderRow(label: "Threshold", value: glitchBinding(\.threshold), range: 0...1, step: 0.05, resetValue: defaultGlitch.threshold)
                SliderRow(label: "Amount", value: glitchBinding(\.amount), range: 0...1, step: 0.05, resetValue: defaultGlitch.amount)
                SliderRow(label: "Streak", value: glitchBinding(\.streakLength), range: 0...1, step: 0.05, resetValue: defaultGlitch.streakLength)
                SliderRow(label: "Random", value: glitchBinding(\.randomness), range: 0...1, step: 0.05, resetValue: defaultGlitch.randomness)

                ControlRow(label: "Reverse") {
                    Toggle("Reverse", isOn: reverseBinding)
                        .labelsHidden()
                }
            }

            if case .glitch(_, _, _, _) = params.params,
               params.kind == .vhs {
                // Amount is the master VHS strength — scales tracking,
                // distortion, and chroma in Glitch.metal.
                SliderRow(label: "Amount", value: glitchBinding(\.amount), range: 0...1, step: 0.05, resetValue: defaultGlitch.amount)
                SliderRow(label: "Distortion", value: glitchBinding(\.distortion), range: 0...1, step: 0.05, resetValue: defaultGlitch.distortion)
                SliderRow(label: "Color Bleed", value: glitchBinding(\.colorBleed), range: 0...1, step: 0.05, resetValue: defaultGlitch.colorBleed)
                SliderRow(label: "Scanlines", value: glitchBinding(\.scanlines), range: 0...1, step: 0.05, resetValue: defaultGlitch.scanlines)
                SliderRow(label: "Tracking", value: glitchBinding(\.trackingError), range: 0...1, step: 0.05, resetValue: defaultGlitch.trackingError)
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .waveLines {
                // Line Strength drives the shader's threshold shaping —
                // the primary brightness knob (mirrors desktop sidebar).
                SliderRow(label: "Line Strength", value: edgeFieldBinding(\.lineStrength), range: 0...1, step: 0.05, resetValue: defaultEdgeField.lineStrength)
                SliderRow(label: "Amplitude", value: edgeFieldBinding(\.amplitude), range: 0...1, step: 0.05, resetValue: defaultEdgeField.amplitude)
                SliderRow(label: "Frequency", value: edgeFieldBinding(\.frequency), range: 0.1...4, step: 0.05, resetValue: defaultEdgeField.frequency)
                SliderRow(label: "Thickness", value: edgeFieldBinding(\.thickness), range: 0.05...1, step: 0.05, resetValue: defaultEdgeField.thickness)

                ControlRow(label: "Direction") {
                    Picker("Direction", selection: edgeDirectionBinding) {
                        Text("Horizontal").tag(EdgeFieldDirection.horizontal)
                        Text("Vertical").tag(EdgeFieldDirection.vertical)
                    }
                    .pickerStyle(.menu)
                }

                // Range matches the desktop sidebar: the shader computes
                // countFactor = max(1, lineCount/spacing); 1...40 covers
                // "no boost" through "very dense bands".
                SliderRow(label: "Line Count", value: edgeFieldBinding(\.lineCount), range: 1...40, step: 0.05, resetValue: defaultEdgeField.lineCount)

                ControlRow(label: "Line Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.edgeColor = codable
                            onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .noiseField {
                // Line Strength gates the noise contribution; Field
                // Intensity biases the baseline level (mirrors desktop).
                SliderRow(label: "Line Strength", value: edgeFieldBinding(\.lineStrength), range: 0...1, step: 0.05, resetValue: defaultEdgeField.lineStrength)
                SliderRow(label: "Field Intensity", value: edgeFieldBinding(\.fieldIntensity), range: 0...1, step: 0.05, resetValue: defaultEdgeField.fieldIntensity)
                // Range matches the GPU clamp (EdgeFieldGPURenderer caps
                // octaves at 6) — values above were silently ignored.
                SliderRow(label: "Octaves", value: noiseOctavesBinding, range: 1...6, step: 0.05, resetValue: Double(defaultEdgeField.octaves))
                SliderRow(label: "Scale", value: edgeFieldBinding(\.amplitude), range: 0.1...1, step: 0.05, resetValue: defaultEdgeField.amplitude)

                ControlRow(label: "Noise Type") {
                    Picker("Noise Type", selection: noiseTypeBinding) {
                        Text("Value").tag(NoiseFieldType.value)
                        Text("Simplex").tag(NoiseFieldType.simplex)
                        Text("Cellular").tag(NoiseFieldType.cellular)
                    }
                    .pickerStyle(.menu)
                }

                ControlRow(label: "Invert") {
                    Toggle("Invert", isOn: edgeInvertBinding)
                        .labelsHidden()
                }

                ControlRow(label: "Field Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.edgeColor = codable
                            onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .edgeDetection {
                ControlRow(label: "Algorithm") {
                    Picker("Algorithm", selection: edgeAlgorithmBinding) {
                        Text("Sobel").tag(EdgeAlgorithm.sobel)
                        Text("Laplacian").tag(EdgeAlgorithm.laplacian)
                    }
                    .pickerStyle(.menu)
                }

                SliderRow(label: "Line Strength", value: edgeFieldBinding(\.lineStrength), range: 0...1, step: 0.05, resetValue: defaultEdgeField.lineStrength)
                SliderRow(label: "Threshold", value: edgeThresholdBinding, range: 0...1, step: 0.05, resetValue: defaultEdgeField.edgeThreshold)
                SliderRow(label: "Line Width", value: edgeFieldBinding(\.thickness), range: 0.05...1, step: 0.05, resetValue: defaultEdgeField.thickness)

                ControlRow(label: "Invert") {
                    Toggle("Invert", isOn: edgeInvertBinding)
                        .labelsHidden()
                }

                ControlRow(label: "Edge Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.edgeColor = codable
                            onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .contour {
                ControlRow(label: "Fill Mode") {
                    Picker("Fill Mode", selection: contourFillModeBinding) {
                        Text("Lines").tag(ContourFillMode.linesOnly)
                        Text("Bands").tag(ContourFillMode.filledBands)
                    }
                    .pickerStyle(.menu)
                }

                SliderRow(label: "Line Strength", value: edgeFieldBinding(\.lineStrength), range: 0...1, step: 0.05, resetValue: defaultEdgeField.lineStrength)
                SliderRow(label: "Field Intensity", value: edgeFieldBinding(\.fieldIntensity), range: 0.01...1, step: 0.05, resetValue: defaultEdgeField.fieldIntensity)
                SliderRow(label: "Levels", value: contourLevelsBinding, range: 2...24, step: 0.05, resetValue: Double(defaultEdgeField.contourLevels))
                SliderRow(label: "Line Width", value: edgeFieldBinding(\.thickness), range: 0.05...1, step: 0.05, resetValue: defaultEdgeField.thickness)

                ControlRow(label: "Invert") {
                    Toggle("Invert", isOn: edgeInvertBinding)
                        .labelsHidden()
                }

                ControlRow(label: "Contour Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.edgeColor = codable
                            onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .voronoi {
                SliderRow(label: "Cell Size", value: voronoiCellSizeBinding, range: 2...64, step: 0.05, resetValue: defaultEdgeField.cellSize)
                SliderRow(label: "Wall Strength", value: edgeFieldBinding(\.lineStrength), range: 0...1, step: 0.05, resetValue: defaultEdgeField.lineStrength)
                SliderRow(label: "Cell Fill", value: edgeFieldBinding(\.fieldIntensity), range: 0...1, step: 0.05, resetValue: defaultEdgeField.fieldIntensity)
                SliderRow(label: "Edge Width", value: voronoiEdgeWidthBinding, range: 0.05...1, step: 0.05, resetValue: defaultEdgeField.edgeWidth)

                ControlRow(label: "Randomize") {
                    Toggle("Randomize", isOn: voronoiRandomizeBinding)
                        .labelsHidden()
                }

                ControlRow(label: "Edge Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.edgeColor = codable
                            onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }

            if case .printSampling(let common, let geometry, let color, let payload) = params.params {
                if params.kind == .halftone {
                    ControlRow(label: "Shape") {
                        Picker("Shape", selection: halftoneShapeBinding) {
                            Text("Circle").tag(HalftoneShape.circle)
                            Text("Square").tag(HalftoneShape.square)
                            Text("Diamond").tag(HalftoneShape.diamond)
                        }
                        .pickerStyle(.menu)
                    }

                    SliderRow(label: "Angle", value: halftoneAngleBinding, range: 0...90, step: 0.05, resetValue: defaultPrintSampling.halftoneAngle)

                    ControlRow(label: "Invert") {
                        Toggle("Invert", isOn: invertBinding)
                            .labelsHidden()
                    }
                }

                if params.kind == .crosshatch {
                    // Threshold is the luminance cutoff that decides which
                    // pixels get inked (mirrors desktop sidebar).
                    SliderRow(label: "Threshold", value: printSamplingBinding(\.threshold), range: 0...1, step: 0.05, resetValue: defaultPrintSampling.threshold)
                    SliderRow(label: "Density", value: hatchDensityBinding, range: 0...1, step: 0.05, resetValue: defaultPrintSampling.hatchDensity)
                    // Max 3 matches the GPU clamp (PrintSamplingGPURenderer
                    // caps hatchLayers at 3) — position 4 was a no-op.
                    SliderRow(label: "Layers", value: hatchLayersBinding, range: 1...3, step: 0.05, resetValue: Double(defaultPrintSampling.hatchLayers))
                    SliderRow(label: "Angle", value: hatchAngleBinding, range: 0...90, step: 0.05, resetValue: defaultPrintSampling.hatchAngle)
                    SliderRow(label: "Line Width", value: hatchLineWidthBinding, range: 0.05...1, step: 0.05, resetValue: defaultPrintSampling.hatchLineWidth)
                    SliderRow(label: "Random", value: hatchRandomnessBinding, range: 0...1, step: 0.05, resetValue: defaultPrintSampling.hatchRandomness)

                    ControlRow(label: "Invert") {
                        Toggle("Invert", isOn: invertBinding)
                            .labelsHidden()
                    }
                }

                if params.kind == .threshold {
                    // Core cutoff — shader decides ink vs paper by
                    // `quantized < u.threshold` (mirrors desktop sidebar).
                    SliderRow(label: "Threshold", value: printSamplingBinding(\.threshold), range: 0...1, step: 0.05, resetValue: defaultPrintSampling.threshold)
                    SliderRow(label: "Levels", value: thresholdLevelsBinding, range: 2...8, step: 0.05, resetValue: Double(defaultPrintSampling.thresholdLevels))

                    ControlRow(label: "Dither") {
                        Toggle("Dither", isOn: thresholdDitherBinding)
                            .labelsHidden()
                    }

                    ControlRow(label: "Invert") {
                        Toggle("Invert", isOn: invertBinding)
                            .labelsHidden()
                    }
                }

                ControlRow(label: "Foreground") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.foreground ?? CodableColor(unchecked: "#FFFFFF")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.foreground = codable
                            onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }

                ControlRow(label: "Background") {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: (payload.background ?? CodableColor(unchecked: "#000000")).cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                            var updatedPayload = payload
                            updatedPayload.background = codable
                            onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: updatedPayload)))
                        }
                    ))
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: Canonical per-kind defaults (double-tap-to-reset targets).
    // Derived from GPUEffectKind.defaultParameters() so reset values can
    // never drift from the values a fresh layer starts with.

    private var kindDefaults: GPUEffectParameters { params.kind.defaultParameters() }

    private var defaultCommon: GPUEffectCommonParameters {
        switch kindDefaults {
        case .textCell(let c, _, _, _), .printSampling(let c, _, _, _),
             .edgeField(let c, _, _, _), .glitch(let c, _, _, _):
            return c
        }
    }

    private var defaultGeometry: GPUEffectGeometryParameters {
        switch kindDefaults {
        case .textCell(_, let g, _, _), .printSampling(_, let g, _, _),
             .edgeField(_, let g, _, _), .glitch(_, let g, _, _):
            return g
        }
    }

    private var defaultColor: GPUEffectColorParameters {
        switch kindDefaults {
        case .textCell(_, _, let c, _), .printSampling(_, _, let c, _),
             .edgeField(_, _, let c, _), .glitch(_, _, let c, _):
            return c
        }
    }

    private var defaultTextCell: TextCellParameters {
        if case .textCell(_, _, _, let p) = kindDefaults { return p }
        return TextCellParameters()
    }

    private var defaultPrintSampling: PrintSamplingParameters {
        if case .printSampling(_, _, _, let p) = kindDefaults { return p }
        return PrintSamplingParameters()
    }

    private var defaultEdgeField: EdgeFieldParameters {
        if case .edgeField(_, _, _, let p) = kindDefaults { return p }
        return EdgeFieldParameters()
    }

    private var defaultGlitch: GlitchParameters {
        if case .glitch(_, _, _, let p) = kindDefaults { return p }
        return GlitchParameters()
    }

    /// Preset picker + saved palettes + per-colour editor for `.palette`
    /// colour mode. Mirrors the Dither layer's palette editor in this file.
    @ViewBuilder
    private var gpuPaletteEditor: some View {
        let colors = Self.color(for: params.params).palette ?? VintagePalette.gameBoy
        let selectedPreset = VintagePalette.Preset.matching(colors)

        ControlRow(label: "Preset") {
            Picker("", selection: Binding(
                get: { selectedPreset },
                set: { newValue in
                    guard newValue != selectedPreset else { return }
                    var c = Self.color(for: params.params)
                    switch newValue {
                    case .custom:
                        let base = colors.isEmpty ? VintagePalette.gameBoy : colors
                        let trimmed = Array(base.prefix(FramerColorUniformsLayout.maxPaletteColors - 1))
                        c.palette = trimmed + [CodableColor(unchecked: "#808080")]
                    default:
                        c.palette = newValue.colors
                    }
                    onChange(Self.updatingColor(params, color: c))
                }
            )) {
                ForEach(VintagePalette.Preset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.menu)
        }

        MobileUserPaletteRow(currentColors: colors) { applied in
            var c = Self.color(for: params.params)
            c.palette = applied
            onChange(Self.updatingColor(params, color: c))
        }

        ForEach(Array(colors.enumerated()), id: \.offset) { idx, color in
            ControlRow(label: "Colour \(idx + 1)") {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { Color(cgColor: color.cgColor) },
                        set: { newColor in
                            guard let hex = newColor.hexString,
                                  let codable = try? CodableColor(hex: hex) else { return }
                            var c = Self.color(for: params.params)
                            var next = colors
                            next[idx] = codable
                            c.palette = next
                            onChange(Self.updatingColor(params, color: c))
                        }
                    ))
                    .labelsHidden()
                    if colors.count > 2 {
                        Button {
                            var c = Self.color(for: params.params)
                            var next = colors
                            next.remove(at: idx)
                            c.palette = next
                            onChange(Self.updatingColor(params, color: c))
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }

        if colors.count < FramerColorUniformsLayout.maxPaletteColors {
            Button {
                var c = Self.color(for: params.params)
                c.palette = colors + [colors.last ?? CodableColor(unchecked: "#000000")]
                onChange(Self.updatingColor(params, color: c))
            } label: {
                Label("Add Colour", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var kindBinding: Binding<GPUEffectKind> {
        Binding(
            get: { params.kind },
            set: { newKind in
                var copy = params
                copy.kind = newKind
                copy.params = newKind.defaultParameters()
                onChange(copy)
            }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(get: { Self.geometry(for: params.params).scale }, set: { onChange(Self.updatingGeometry(params, scale: $0, spacing: nil, outputWidth: nil)) })
    }

    private var spacingBinding: Binding<Double> {
        Binding(get: { Self.geometry(for: params.params).spacing }, set: { onChange(Self.updatingGeometry(params, scale: nil, spacing: $0, outputWidth: nil)) })
    }

    private var outputWidthBinding: Binding<Double> {
        Binding(get: { Double(Self.geometry(for: params.params).outputWidth) }, set: { onChange(Self.updatingGeometry(params, scale: nil, spacing: nil, outputWidth: Int($0.rounded()))) })
    }

    private var colorModeBinding: Binding<GPUEffectColorMode> {
        Binding(
            get: { Self.color(for: params.params).mode },
            set: {
                var current = Self.color(for: params.params)
                current.mode = $0
                onChange(Self.updatingColor(params, color: current))
            }
        )
    }

    private var backgroundIntensityBinding: Binding<Double> {
        Binding(
            get: { Self.color(for: params.params).backgroundIntensity },
            set: {
                var current = Self.color(for: params.params)
                current.backgroundIntensity = $0
                onChange(Self.updatingColor(params, color: current))
            }
        )
    }

    private func commonBinding(_ keyPath: WritableKeyPath<GPUEffectCommonParameters, Double>) -> Binding<Double> {
        Binding(
            get: { Self.common(for: params.params)[keyPath: keyPath] },
            set: {
                var current = Self.common(for: params.params)
                current[keyPath: keyPath] = $0
                onChange(Self.updatingCommon(params, common: current))
            }
        )
    }

    private func matrixBinding(_ keyPath: WritableKeyPath<TextCellParameters, Double>) -> Binding<Double> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params {
                    return payload[keyPath: keyPath]
                }
                return 0
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var matrixDirectionBinding: Binding<TextCellFlowDirection> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params {
                    return payload.direction
                }
                return .down
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.direction = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var characterSetBinding: Binding<GPUEffectCharacterSet> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params {
                    return payload.characterSet
                }
                return .classicASCII
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.characterSet = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var dotShapeBinding: Binding<DotShape> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params { return payload.dotShape }
                return .circle
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.dotShape = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var dotGridBinding: Binding<DotGridType> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params { return payload.gridType }
                return .square
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.gridType = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var textInvertBinding: Binding<Bool> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params { return payload.invert }
                return false
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.invert = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var blockStyleBinding: Binding<BlockStyle> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params { return payload.blockStyle }
                return .solid
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.blockStyle = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var blockBorderWidthBinding: Binding<Double> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params { return payload.borderWidth }
                return 0
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.borderWidth = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private func textCellBinding(_ keyPath: WritableKeyPath<TextCellParameters, Double>) -> Binding<Double> {
        Binding(
            get: {
                if case .textCell(_, _, _, let payload) = params.params {
                    return payload[keyPath: keyPath]
                }
                return 0
            },
            set: {
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = $0
                onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: payload)))
            }
        )
    }

    private var halftoneShapeBinding: Binding<HalftoneShape> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params {
                    return payload.halftoneShape
                }
                return .circle
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.halftoneShape = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var halftoneAngleBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params {
                    return payload.halftoneAngle
                }
                return 0
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.halftoneAngle = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var invertBinding: Binding<Bool> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params {
                    return payload.invert
                }
                return false
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.invert = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private func printSamplingBinding(_ keyPath: WritableKeyPath<PrintSamplingParameters, Double>) -> Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return payload[keyPath: keyPath] }
                return 0.5
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var hatchDensityBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return payload.hatchDensity }
                return 0.5
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchDensity = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var hatchLayersBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return Double(payload.hatchLayers) }
                return 2
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchLayers = max(1, Int($0.rounded()))
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var hatchAngleBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return payload.hatchAngle }
                return 45
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchAngle = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var hatchLineWidthBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return payload.hatchLineWidth }
                return 0.25
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchLineWidth = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var hatchRandomnessBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return payload.hatchRandomness }
                return 0
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchRandomness = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var thresholdLevelsBinding: Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return Double(payload.thresholdLevels) }
                return 2
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.thresholdLevels = max(2, Int($0.rounded()))
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private var thresholdDitherBinding: Binding<Bool> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params { return payload.thresholdDither }
                return false
            },
            set: {
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.thresholdDither = $0
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
            }
        )
    }

    private func glitchBinding(_ keyPath: WritableKeyPath<GlitchParameters, Double>) -> Binding<Double> {
        Binding(
            get: {
                if case .glitch(_, _, _, let payload) = params.params {
                    return payload[keyPath: keyPath]
                }
                return 0
            },
            set: {
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = $0
                onChange(updated(layer: params, params: .glitch(common: common, geometry: geometry, color: color, glitch: payload)))
            }
        )
    }

    private var glitchDirectionBinding: Binding<GlitchDirection> {
        Binding(
            get: {
                if case .glitch(_, _, _, let payload) = params.params {
                    return payload.direction
                }
                return .horizontal
            },
            set: {
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload.direction = $0
                onChange(updated(layer: params, params: .glitch(common: common, geometry: geometry, color: color, glitch: payload)))
            }
        )
    }

    private var sortModeBinding: Binding<PixelSortMode> {
        Binding(
            get: {
                if case .glitch(_, _, _, let payload) = params.params {
                    return payload.sortMode
                }
                return .brightness
            },
            set: {
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload.sortMode = $0
                onChange(updated(layer: params, params: .glitch(common: common, geometry: geometry, color: color, glitch: payload)))
            }
        )
    }

    private var reverseBinding: Binding<Bool> {
        Binding(
            get: {
                if case .glitch(_, _, _, let payload) = params.params {
                    return payload.reverse
                }
                return false
            },
            set: {
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload.reverse = $0
                onChange(updated(layer: params, params: .glitch(common: common, geometry: geometry, color: color, glitch: payload)))
            }
        )
    }

    private func edgeFieldBinding(_ keyPath: WritableKeyPath<EdgeFieldParameters, Double>) -> Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload[keyPath: keyPath]
                }
                return 0
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var edgeDirectionBinding: Binding<EdgeFieldDirection> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.direction
                }
                return .horizontal
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.direction = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var noiseTypeBinding: Binding<NoiseFieldType> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.noiseType
                }
                return .value
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.noiseType = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var noiseOctavesBinding: Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return Double(payload.octaves)
                }
                return 1
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.octaves = max(1, Int($0.rounded()))
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var edgeAlgorithmBinding: Binding<EdgeAlgorithm> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.edgeAlgorithm
                }
                return .sobel
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.edgeAlgorithm = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var edgeThresholdBinding: Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.edgeThreshold
                }
                return 0.5
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.edgeThreshold = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var edgeInvertBinding: Binding<Bool> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.invert
                }
                return false
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.invert = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var contourFillModeBinding: Binding<ContourFillMode> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params { return payload.contourFillMode }
                return .linesOnly
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.contourFillMode = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var contourLevelsBinding: Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params { return Double(payload.contourLevels) }
                return 8
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.contourLevels = max(2, Int($0.rounded()))
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var voronoiCellSizeBinding: Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params { return payload.cellSize }
                return 16
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.cellSize = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var voronoiEdgeWidthBinding: Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params { return payload.edgeWidth }
                return 0.25
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.edgeWidth = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private var voronoiRandomizeBinding: Binding<Bool> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params { return payload.randomize }
                return false
            },
            set: {
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.randomize = $0
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private static func geometry(for params: GPUEffectParameters) -> GPUEffectGeometryParameters {
        switch params {
        case .textCell(_, let geometry, _, _), .printSampling(_, let geometry, _, _), .edgeField(_, let geometry, _, _), .glitch(_, let geometry, _, _):
            return geometry
        }
    }

    private static func common(for params: GPUEffectParameters) -> GPUEffectCommonParameters {
        switch params {
        case .textCell(let common, _, _, _), .printSampling(let common, _, _, _), .edgeField(let common, _, _, _), .glitch(let common, _, _, _):
            return common
        }
    }

    private static func color(for params: GPUEffectParameters) -> GPUEffectColorParameters {
        switch params {
        case .textCell(_, _, let color, _), .printSampling(_, _, let color, _), .edgeField(_, _, let color, _), .glitch(_, _, let color, _):
            return color
        }
    }

    private static func updatingGeometry(_ layer: GPUEffectLayerParams, scale: Double?, spacing: Double?, outputWidth: Int?) -> GPUEffectLayerParams {
        var copy = layer
        switch layer.params {
        case .textCell(let common, let geometry, let color, let payload):
            copy.params = .textCell(common: common, geometry: .init(scale: scale ?? geometry.scale, spacing: spacing ?? geometry.spacing, outputWidth: outputWidth ?? geometry.outputWidth), color: color, textCell: payload)
        case .printSampling(let common, let geometry, let color, let payload):
            copy.params = .printSampling(common: common, geometry: .init(scale: scale ?? geometry.scale, spacing: spacing ?? geometry.spacing, outputWidth: outputWidth ?? geometry.outputWidth), color: color, printSampling: payload)
        case .edgeField(let common, let geometry, let color, let payload):
            copy.params = .edgeField(common: common, geometry: .init(scale: scale ?? geometry.scale, spacing: spacing ?? geometry.spacing, outputWidth: outputWidth ?? geometry.outputWidth), color: color, edgeField: payload)
        case .glitch(let common, let geometry, let color, let payload):
            copy.params = .glitch(common: common, geometry: .init(scale: scale ?? geometry.scale, spacing: spacing ?? geometry.spacing, outputWidth: outputWidth ?? geometry.outputWidth), color: color, glitch: payload)
        }
        return copy
    }

    private static func updatingCommon(_ layer: GPUEffectLayerParams, common: GPUEffectCommonParameters) -> GPUEffectLayerParams {
        var copy = layer
        switch layer.params {
        case .textCell(_, let geometry, let color, let payload):
            copy.params = .textCell(common: common, geometry: geometry, color: color, textCell: payload)
        case .printSampling(_, let geometry, let color, let payload):
            copy.params = .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)
        case .edgeField(_, let geometry, let color, let payload):
            copy.params = .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)
        case .glitch(_, let geometry, let color, let payload):
            copy.params = .glitch(common: common, geometry: geometry, color: color, glitch: payload)
        }
        return copy
    }

    private static func updatingColor(_ layer: GPUEffectLayerParams, color: GPUEffectColorParameters) -> GPUEffectLayerParams {
        var copy = layer
        switch layer.params {
        case .textCell(let common, let geometry, _, let payload):
            copy.params = .textCell(common: common, geometry: geometry, color: color, textCell: payload)
        case .printSampling(let common, let geometry, _, let payload):
            copy.params = .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)
        case .edgeField(let common, let geometry, _, let payload):
            copy.params = .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)
        case .glitch(let common, let geometry, _, let payload):
            copy.params = .glitch(common: common, geometry: geometry, color: color, glitch: payload)
        }
        return copy
    }

    private func updated(layer: GPUEffectLayerParams, params newParams: GPUEffectParameters) -> GPUEffectLayerParams {
        var copy = layer
        copy.params = newParams
        return copy
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
    /// Snap increment — mirrors the desktop sidebar's 0.05 step so both
    /// platforms store the same precision. nil = continuous.
    var step: Double? = nil
    /// Double-tapping the row resets to this value (the parameter's
    /// canonical default from GPUEffectKind.defaultParameters()).
    var resetValue: Double? = nil

    /// Narrow ranges (0...1, 0.2...2, …) are fractional parameters — an
    /// integer readout would render every value as "0" or "1". Wide ranges
    /// (angles, counts, sizes) read better as whole numbers.
    private var formattedValue: String {
        if range.upperBound - range.lowerBound <= 10 {
            return String(format: "%.2f", value)
        }
        return "\(Int(value))"
    }

    var body: some View {
        ControlRow(label: label) {
            HStack {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text("\(formattedValue)\(unit)")
                    .font(AppFont.mono(12))
                    .foregroundStyle(Color.text1)
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .onTapGesture(count: 2) {
            if let resetValue {
                value = min(range.upperBound, max(range.lowerBound, resetValue))
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
            case .bwFilm(let bwFilmParams):
                bwFilmControls(bwFilmParams)
            }
        }
    }

    @ViewBuilder
    private func bwFilmControls(_ bw: BWFilmShaderParams) -> some View {
        ControlRow(label: "Film Response") {
            Picker("Film Response", selection: Binding(
                get: { bw.response },
                set: { value in
                    onChange(params.withParams(.bwFilm(bw.applyingResponse(value))))
                }
            )) {
                ForEach(BWFilmResponse.allCases, id: \.self) { response in
                    Text(response.label).tag(response)
                }
            }
            .pickerStyle(.menu)
        }
        bwFilmSlider("Red", bw.sensRed) { v, p in var u = p; u.sensRed = v; return u }
        bwFilmSlider("Yellow", bw.sensYellow) { v, p in var u = p; u.sensYellow = v; return u }
        bwFilmSlider("Green", bw.sensGreen) { v, p in var u = p; u.sensGreen = v; return u }
        bwFilmSlider("Cyan", bw.sensCyan) { v, p in var u = p; u.sensCyan = v; return u }
        bwFilmSlider("Blue", bw.sensBlue) { v, p in var u = p; u.sensBlue = v; return u }
        bwFilmSlider("Magenta", bw.sensMagenta) { v, p in var u = p; u.sensMagenta = v; return u }
        bwFilmSlider("Brightness", bw.brightness) { v, p in var u = p; u.brightness = v; return u }
        bwFilmSlider("Highlights", bw.brightnessHighlights) { v, p in var u = p; u.brightnessHighlights = v; return u }
        bwFilmSlider("Midtones", bw.brightnessMidtones) { v, p in var u = p; u.brightnessMidtones = v; return u }
        bwFilmSlider("Shadows", bw.brightnessShadows) { v, p in var u = p; u.brightnessShadows = v; return u }
        bwFilmSlider("Contrast", bw.contrast) { v, p in var u = p; u.contrast = v; return u }
        bwFilmSlider("Protect Highlights", bw.protectHighlights, range: 0...100) { v, p in var u = p; u.protectHighlights = v; return u }
        bwFilmSlider("Protect Shadows", bw.protectShadows, range: 0...100) { v, p in var u = p; u.protectShadows = v; return u }
        bwFilmSlider("Structure", bw.structure) { v, p in var u = p; u.structure = v; return u }
        bwFilmSlider("Structure Highlights", bw.structureHighlights) { v, p in var u = p; u.structureHighlights = v; return u }
        bwFilmSlider("Structure Midtones", bw.structureMidtones) { v, p in var u = p; u.structureMidtones = v; return u }
        bwFilmSlider("Structure Shadows", bw.structureShadows) { v, p in var u = p; u.structureShadows = v; return u }
        bwFilmSlider("Fine Structure", bw.fineStructure, range: 0...100) { v, p in var u = p; u.fineStructure = v; return u }
        bwFilmSlider("Gamma", bw.curveGamma, range: -1...1, step: 0.02) { v, p in var u = p; u.curveGamma = v; return u }
        bwFilmSlider("Black Point", bw.curveLowX, range: 0...0.5, step: 0.01) { v, p in var u = p; u.curveLowX = v; return u }
        bwFilmSlider("Black Lift", bw.curveLowY, range: 0...0.5, step: 0.01) { v, p in var u = p; u.curveLowY = v; return u }
        bwFilmSlider("White Point", bw.curveHighX, range: 0.5...1, step: 0.01, resetValue: 1) { v, p in var u = p; u.curveHighX = v; return u }
        bwFilmSlider("White Cap", bw.curveHighY, range: 0.5...1, step: 0.01, resetValue: 1) { v, p in var u = p; u.curveHighY = v; return u }

        if !bw.curvePoints.isEmpty {
            ControlRow(label: "Film Curve") {
                Button {
                    guard case .bwFilm(var current) = params.params else { return }
                    current.curvePoints = []
                    current.curveLowY = 0
                    current.curveHighY = 1
                    onChange(params.withParams(.bwFilm(current)))
                } label: {
                    Label("\(bw.curvePoints.count) points · Reset", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .buttonStyle(.plain)
            }
        }

        ControlRow(label: "Toning") {
            Picker("Toning", selection: Binding(
                get: { bw.toningPreset },
                set: { value in
                    onChange(params.withParams(.bwFilm(bw.applyingToningPreset(value))))
                }
            )) {
                ForEach(BWToningPreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.menu)
        }
        bwFilmSlider("Toning Strength", bw.toningStrength, range: 0...100) { v, p in var u = p; u.toningStrength = v; return u }
        bwFilmSlider("Silver Hue", bw.toneHueHigh, range: 0...360, resetValue: 40) { v, p in var u = p; u.toneHueHigh = v; return u }
        bwFilmSlider("Silver Toning", bw.toneStrengthHigh, range: 0...100) { v, p in var u = p; u.toneStrengthHigh = v; return u }
        bwFilmSlider("Paper Hue", bw.toneHueLow, range: 0...360, resetValue: 40) { v, p in var u = p; u.toneHueLow = v; return u }
        bwFilmSlider("Paper Toning", bw.toneStrengthLow, range: 0...100) { v, p in var u = p; u.toneStrengthLow = v; return u }
        bwFilmSlider("Balance", bw.toneBalance) { v, p in var u = p; u.toneBalance = v; return u }
        bwFilmSlider("Vignette", bw.vigStrength) { v, p in var u = p; u.vigStrength = v; return u }
        bwFilmSlider("Vignette Size", bw.vigSize, range: 0...100, resetValue: 50) { v, p in var u = p; u.vigSize = v; return u }
        bwFilmSlider("Circle / Rectangle", bw.vigShape, range: 1...5, step: 0.1, resetValue: 3) { v, p in var u = p; u.vigShape = v; return u }
        bwFilmSlider("Burn Top", bw.beStrengthTop, range: 0...100) { v, p in var u = p; u.beStrengthTop = v; return u }
        bwFilmSlider("Burn Bottom", bw.beStrengthBottom, range: 0...100) { v, p in var u = p; u.beStrengthBottom = v; return u }
        bwFilmSlider("Burn Left", bw.beStrengthLeft, range: 0...100) { v, p in var u = p; u.beStrengthLeft = v; return u }
        bwFilmSlider("Burn Right", bw.beStrengthRight, range: 0...100) { v, p in var u = p; u.beStrengthRight = v; return u }
        bwFilmSlider("Burn Size", bw.beSizeTop, range: 0...100, resetValue: 25) { v, p in
            var u = p; u.beSizeTop = v; u.beSizeBottom = v; u.beSizeLeft = v; u.beSizeRight = v; return u
        }
        bwFilmSlider("Burn Transition", bw.beTransitionTop, range: 0...100, resetValue: 50) { v, p in
            var u = p; u.beTransitionTop = v; u.beTransitionBottom = v; u.beTransitionLeft = v; u.beTransitionRight = v; return u
        }
    }

    private func bwFilmSlider(
        _ label: String,
        _ value: Double,
        range: ClosedRange<Double> = -100...100,
        step: Double = 1,
        resetValue: Double = 0,
        update: @escaping (Double, BWFilmShaderParams) -> BWFilmShaderParams
    ) -> some View {
        sliderRow(
            label: label,
            value: value,
            range: range,
            step: step,
            resetValue: resetValue
        ) { newValue in
            guard case .bwFilm(let current) = params.params else { return }
            onChange(params.withParams(.bwFilm(update(newValue, current))))
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

// MARK: - Saved palettes row

/// "Saved" palettes row: apply a stored user palette, save the current
/// colours under a name, or delete stored palettes. Backed by
/// UserPaletteStore — the same file the desktop UserPaletteMenu reads, so
/// palettes are shared across editors (and across devices if the container
/// syncs). Used by the Dither palette editor and the GPU-effect palette
/// colour mode above.
private struct MobileUserPaletteRow: View {
    var currentColors: [CodableColor]
    var onApply: ([CodableColor]) -> Void

    @State private var palettes: [UserPalette] = []
    @State private var showingSavePrompt = false
    @State private var saveName = ""

    private let store = UserPaletteStore()

    var body: some View {
        ControlRow(label: "Saved") {
            Menu {
                if palettes.isEmpty {
                    Text("No Saved Palettes")
                } else {
                    ForEach(palettes) { palette in
                        Button(palette.name) { onApply(palette.colors) }
                    }
                }
                Divider()
                Button("Save Current Palette…") {
                    saveName = ""
                    showingSavePrompt = true
                }
                if !palettes.isEmpty {
                    Menu("Delete Palette") {
                        ForEach(palettes) { palette in
                            Button(palette.name, role: .destructive) {
                                try? store.delete(id: palette.id)
                                palettes = store.list()
                            }
                        }
                    }
                }
            } label: {
                Label("Saved Palettes", systemImage: "swatchpalette")
            }
        }
        .onAppear { palettes = store.list() }
        .alert("Save Palette", isPresented: $showingSavePrompt) {
            TextField("Name", text: $saveName)
            Button("Save") {
                let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try? store.save(UserPalette(name: trimmed, colors: currentColors))
                palettes = store.list()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current \(currentColors.count) colours for reuse in any palette editor.")
        }
    }
}

// MARK: - Color hex helper

extension Color {
    var hexString: String? {
        // Resolve through UIKit — `Color.cgColor` is nil for dynamic /
        // catalog colors, which made the picker bindings' guard fail and
        // silently drop the selection. UIColor(_:) always resolves.
        guard let cgColor = UIColor(self).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ),
        let components = cgColor.components,
        components.count >= 3 else { return nil }
        let r = Int((max(0, min(1, components[0])) * 255).rounded())
        let g = Int((max(0, min(1, components[1])) * 255).rounded())
        let b = Int((max(0, min(1, components[2])) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
