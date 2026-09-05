import SwiftUI
import FramerCore

struct GPUEffectControls: View {
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

