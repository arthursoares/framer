import SwiftUI
import AppKit
import FramerCore

struct GPUEffectLayerControls: View {
    var params: GPUEffectLayerParams
    var onChange: (GPUEffectLayerParams) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Per-variant layers (Option B of the bucket-UI refactor): each
            // GPU-effect variant is a first-class entry in the layer-add
            // menu, so the kind is fixed at creation. Show it here as a
            // read-only label so users know which layer they're editing
            // without offering mid-flight variant switching (which would
            // require re-picking every parameter for the new kind).
            Label(params.kind.label, systemImage: params.kind.menuIcon)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text1)
                .denseControlRow("Effect")

            SimpleLayerEditorDivider()

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

            // Global control blocks are gated by GPUEffectKind capability flags.
            // Each variant's shader only reads a subset of the shared
            // common/geometry/color uniforms — showing sliders the shader
            // ignores felt "unwired" to the user, per the parameter matrix at
            // docs/gpu-effects-parameter-matrix.md. We only render each group
            // when the current kind actually consumes it.

            if params.kind.usesGeometry {
                SidebarCompoundControlBlock {
                    DenseSliderControlRow(
                        title: "Scale",
                        value: scaleBinding,
                        range: 0.5...2.0,
                        step: 0.05,
                        resetValue: defaultGeometry.scale
                    )
                } secondary: {
                    DenseSliderControlRow(
                        title: "Spacing",
                        value: spacingBinding,
                        range: 1...8,
                        step: 0.1,
                        resetValue: defaultGeometry.spacing
                    )
                }
            }

            // Output Width is the effect's render resolution — consumed by
            // every renderer family, so it stays visible for all kinds
            // (mirrors the mobile inspector; previously the binding existed
            // here but no control was wired to it).
            DenseSliderControlRow(
                title: "Output Width",
                value: outputWidthBinding,
                range: 120...640,
                step: 1,
                resetValue: Double(defaultGeometry.outputWidth)
            )

            if params.kind.usesColorModeAndFgBg {
                Picker("", selection: colorModeBinding) {
                    Text("Source").tag(GPUEffectColorMode.source)
                    Text("FG/BG").tag(GPUEffectColorMode.foregroundBackground)
                    Text("Mono").tag(GPUEffectColorMode.monochrome)
                    // Palette mode is offered only where the variant's
                    // shader actually quantizes against the palette uniform
                    // (framerPalettePick in ShaderCommon.h) — matrixRain
                    // paints via rainColor and stays without it.
                    if params.kind.usesPalette {
                        Text("Palette").tag(GPUEffectColorMode.palette)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Color Mode")

                if params.kind.usesPalette,
                   Self.color(for: params.params).mode == .palette {
                    gpuPaletteEditor()
                }
            }

            if params.kind.usesBackgroundIntensity || params.kind.usesColorModeAndFgBg {
                DenseSliderControlRow(
                    title: "Background",
                    value: backgroundIntensityBinding,
                    range: 0...1,
                    step: 0.05,
                    resetValue: defaultColor.backgroundIntensity
                )
            }

            // Common adjustments consumed by every bucket shader via
            // `applyCommonAdjustments` in ShaderCommon.h. Five of six fields
            // apply (brightness / contrast / saturation / hueRotation / gamma);
            // `sharpness` stays in the uniform struct for back-compat but is
            // NOT rendered as a slider — the shared helper flags it as
            // "0 = identity; not consumed by helpers" (ShaderCommon.h:162)
            // because sharpening requires neighbour samples the bucket
            // fragments don't take today. Use the `.shader` layer (Crimewave,
            // Shiba, CRT, etc.) for sharpening until a sharpen kernel lands in
            // the bucket family.
            if params.kind.usesCommonAdjustments {
                adjustmentSlider(label: "Brightness", binding: commonBinding(\.brightness), range: -1...1, resetValue: defaultCommon.brightness)
                adjustmentSlider(label: "Contrast", binding: commonBinding(\.contrast), range: 0...3, resetValue: defaultCommon.contrast)
                adjustmentSlider(label: "Saturation", binding: commonBinding(\.saturation), range: 0...2, resetValue: defaultCommon.saturation)
                adjustmentSlider(label: "Hue", binding: commonBinding(\.hueRotation), range: -1...1, resetValue: defaultCommon.hueRotation)
                adjustmentSlider(label: "Gamma", binding: commonBinding(\.gamma), range: 0.2...2, resetValue: defaultCommon.gamma)
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .ascii {
                Picker("", selection: characterSetBinding) {
                    Text("ASCII").tag(GPUEffectCharacterSet.classicASCII)
                    Text("Blocks").tag(GPUEffectCharacterSet.blocks)
                    Text("Binary").tag(GPUEffectCharacterSet.binary)
                    Text("Dense").tag(GPUEffectCharacterSet.dense)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Character Set")

                adjustmentSlider(label: "Intensity", binding: textCellBinding(\.intensity), range: 0...1, resetValue: defaultTextCell.intensity)

                labeledColorPicker("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                labeledColorPicker("Background", selection: Binding(
                    get: { nsColor(from: payload.background ?? CodableColor(unchecked: "#101010")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.background = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .dots {
                Picker("", selection: dotShapeBinding) {
                    Text("Circle").tag(DotShape.circle)
                    Text("Square").tag(DotShape.square)
                    Text("Diamond").tag(DotShape.diamond)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Dot Shape")

                Picker("", selection: dotGridBinding) {
                    Text("Square").tag(DotGridType.square)
                    Text("Hex").tag(DotGridType.hex)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Grid")

                adjustmentSlider(label: "Dot Size", binding: textCellBinding(\.sizeMultiplier), range: 0.1...2.0, resetValue: defaultTextCell.sizeMultiplier)
                adjustmentSlider(label: "Intensity", binding: textCellBinding(\.intensity), range: 0...1, resetValue: defaultTextCell.intensity)
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: textInvertBinding)
                }

                labeledColorPicker("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                labeledColorPicker("Background", selection: Binding(
                    get: { nsColor(from: payload.background ?? CodableColor(unchecked: "#111111")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.background = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .blockify {
                Picker("", selection: blockStyleBinding) {
                    Text("Solid").tag(BlockStyle.solid)
                    Text("Shaded").tag(BlockStyle.shaded)
                    Text("Outlined").tag(BlockStyle.outlined)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Style")

                // Shaded mode reuses `borderWidth` as the radial-falloff
                // strength (0 = flat like solid, 1 = full bubble). Outlined
                // mode still uses it as the inset thickness.
                adjustmentSlider(label: "Border Width", binding: blockBorderWidthBinding, range: 0...1, resetValue: defaultTextCell.borderWidth)
                // Intensity blends the blockified output with the original
                // (TextCell.metal: `mix(srcOrig, drawn, intensity)`); had no slider.
                adjustmentSlider(label: "Intensity", binding: textCellBinding(\.intensity), range: 0...1, resetValue: defaultTextCell.intensity)

                labeledColorPicker("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                labeledColorPicker("Background", selection: Binding(
                    get: { nsColor(from: payload.background ?? CodableColor(unchecked: "#111111")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.background = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                labeledColorPicker("Border Color", selection: Binding(
                    get: { nsColor(from: payload.borderColor ?? CodableColor(unchecked: "#00FFAA")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.borderColor = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))
            }

            if case .textCell(let common, let geometry, let color, let payload) = params.params,
               params.kind == .matrixRain {
                adjustmentSlider(label: "Speed", binding: matrixBinding(\.speed), range: 0...1, resetValue: defaultTextCell.speed)
                adjustmentSlider(label: "Trail", binding: matrixBinding(\.trailLength), range: 0...1, resetValue: defaultTextCell.trailLength)
                adjustmentSlider(label: "Glow", binding: matrixBinding(\.glow), range: 0...1, resetValue: defaultTextCell.glow)
                adjustmentSlider(label: "BG Opacity", binding: matrixBinding(\.backgroundOpacity), range: 0...1, resetValue: defaultTextCell.backgroundOpacity)
                // Intensity blends the rain over the source (TextCell.metal:
                // `mix(srcOrig, glyphColor, intensity)`); had no slider.
                adjustmentSlider(label: "Intensity", binding: matrixBinding(\.intensity), range: 0...1, resetValue: defaultTextCell.intensity)
                // `threshold` slider removed — it was a dead control. The GPU
                // encoder (TextCellRenderer.renderMatrixRain) overwrites the
                // shader's `threshold` uniform with `params.trailLength`, so
                // nothing in the pipeline ever read `params.threshold` for
                // matrixRain. Adding it back requires either a new shader
                // uniform (e.g. headBrightness cutoff) or dropping the uniform
                // repurposing scheme. Kept out of the UI until one of those
                // lands so users stop chasing a slider that does nothing.

                Picker("", selection: matrixDirectionBinding) {
                    Text("Down").tag(TextCellFlowDirection.down)
                    Text("Up").tag(TextCellFlowDirection.up)
                    Text("Left").tag(TextCellFlowDirection.left)
                    Text("Right").tag(TextCellFlowDirection.right)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Direction")

                labeledColorPicker("Rain Color", selection: Binding(
                    get: { nsColor(from: payload.rainColor ?? CodableColor(unchecked: "#00FF66")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.rainColor = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))
            }

            if case .glitch = params.params,
               params.kind == .pixelSort {
                Picker("", selection: glitchDirectionBinding) {
                    Text("Horizontal").tag(GlitchDirection.horizontal)
                    Text("Vertical").tag(GlitchDirection.vertical)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Direction")

                Picker("", selection: sortModeBinding) {
                    Text("Brightness").tag(PixelSortMode.brightness)
                    Text("Luminance").tag(PixelSortMode.luminance)
                    Text("Hue").tag(PixelSortMode.hue)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Sort Mode")

                // Threshold (luminance cutoff deciding which pixels get sorted)
                // and Amount (blend of sorted vs. original) are both consumed by
                // PixelSort.metal — threshold → uniforms.threshold, amount →
                // uniforms.intensity (see GlitchGPURenderer) — but had no UI
                // control, so the layer was stuck at their defaults (0.42 / 0.65).
                adjustmentSlider(label: "Threshold", binding: glitchBinding(\.threshold), range: 0...1, resetValue: defaultGlitch.threshold)
                adjustmentSlider(label: "Amount", binding: glitchBinding(\.amount), range: 0...1, resetValue: defaultGlitch.amount)
                adjustmentSlider(label: "Streak", binding: glitchBinding(\.streakLength), range: 0...1, resetValue: defaultGlitch.streakLength)
                adjustmentSlider(label: "Random", binding: glitchBinding(\.randomness), range: 0...1, resetValue: defaultGlitch.randomness)
                SidebarControlRow("Reverse") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: reverseBinding)
                }
            }

            if case .glitch(_, _, _, _) = params.params,
               params.kind == .vhs {
                // Amount is the master VHS strength — it scales tracking,
                // distortion and chroma in Glitch.metal (amount = 0 ⇒ no effect).
                // Had no slider, so the layer was stuck at its 0.75 default.
                adjustmentSlider(label: "Amount", binding: glitchBinding(\.amount), range: 0...1, resetValue: defaultGlitch.amount)
                adjustmentSlider(label: "Distortion", binding: glitchBinding(\.distortion), range: 0...1, resetValue: defaultGlitch.distortion)
                adjustmentSlider(label: "Color Bleed", binding: glitchBinding(\.colorBleed), range: 0...1, resetValue: defaultGlitch.colorBleed)
                adjustmentSlider(label: "Scanlines", binding: glitchBinding(\.scanlines), range: 0...1, resetValue: defaultGlitch.scanlines)
                adjustmentSlider(label: "Tracking", binding: glitchBinding(\.trackingError), range: 0...1, resetValue: defaultGlitch.trackingError)
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .waveLines {
                // Line Strength drives the shader's threshold shaping — primary
                // brightness knob, was missing from UI before.
                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1, resetValue: defaultEdgeField.lineStrength)
                adjustmentSlider(label: "Amplitude", binding: edgeFieldBinding(\.amplitude), range: 0...1, resetValue: defaultEdgeField.amplitude)
                adjustmentSlider(label: "Frequency", binding: edgeFieldBinding(\.frequency), range: 0.1...4, resetValue: defaultEdgeField.frequency)
                adjustmentSlider(label: "Thickness", binding: edgeFieldBinding(\.thickness), range: 0.05...1, resetValue: defaultEdgeField.thickness)

                Picker("", selection: edgeDirectionBinding) {
                    Text("Horizontal").tag(EdgeFieldDirection.horizontal)
                    Text("Vertical").tag(EdgeFieldDirection.vertical)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Direction")
                // Line Count multiplies the wave-band frequency: the shader
                // computes countFactor = max(1, lineCount/spacing) and
                // multiplies `frequency` by it. Range 1..40 covers from "no
                // boost" to "very dense bands" at typical spacing values.
                adjustmentSlider(label: "Line Count", binding: edgeFieldBinding(\.lineCount), range: 1...40, resetValue: defaultEdgeField.lineCount)

                // Line tint: shader multiplies the ink by edgeColor
                // (EdgeField.metal: `ink *= u.edgeColor.rgb`); had no picker.
                labeledColorPicker("Line Color", selection: Binding(
                    get: { nsColor(from: payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.edgeColor = codable
                        onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                    }
                ))
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .noiseField {
                // Line Strength gates the noise contribution (shader:
                // `noise * u.lineStrength + fieldWeight * 0.3`). Field Intensity
                // biases the baseline level. Both were missing from UI.
                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1, resetValue: defaultEdgeField.lineStrength)
                adjustmentSlider(label: "Field Intensity", binding: edgeFieldBinding(\.fieldIntensity), range: 0...1, resetValue: defaultEdgeField.fieldIntensity)
                adjustmentSlider(label: "Octaves", binding: noiseOctavesBinding, range: 1...6, resetValue: Double(defaultEdgeField.octaves))
                adjustmentSlider(label: "Scale", binding: edgeFieldBinding(\.amplitude), range: 0.1...1, resetValue: defaultEdgeField.amplitude)
                Picker("", selection: noiseTypeBinding) {
                    Text("Value (IGN)").tag(NoiseFieldType.value)
                    Text("Simplex").tag(NoiseFieldType.simplex)
                    Text("Cellular").tag(NoiseFieldType.cellular)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Noise Type")
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: edgeInvertBinding)
                }

                // Field tint: shader multiplies the ink by edgeColor
                // (EdgeField.metal: `ink *= u.edgeColor.rgb`); had no picker.
                labeledColorPicker("Field Color", selection: Binding(
                    get: { nsColor(from: payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.edgeColor = codable
                        onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                    }
                ))
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .edgeDetection {
                Picker("", selection: edgeAlgorithmBinding) {
                    Text("Sobel").tag(EdgeAlgorithm.sobel)
                    Text("Laplacian").tag(EdgeAlgorithm.laplacian)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Algorithm")

                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1, resetValue: defaultEdgeField.lineStrength)
                adjustmentSlider(label: "Threshold", binding: edgeThresholdBinding, range: 0...1, resetValue: defaultEdgeField.edgeThreshold)
                adjustmentSlider(label: "Line Width", binding: edgeFieldBinding(\.thickness), range: 0.05...1, resetValue: defaultEdgeField.thickness)
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: edgeInvertBinding)
                }

                labeledColorPicker("Edge Color", selection: Binding(
                    get: { nsColor(from: payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.edgeColor = codable
                        onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                    }
                ))
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .contour {
                Picker("", selection: contourFillModeBinding) {
                    Text("Lines").tag(ContourFillMode.linesOnly)
                    Text("Bands").tag(ContourFillMode.filledBands)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Fill Mode")

                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1, resetValue: defaultEdgeField.lineStrength)
                adjustmentSlider(label: "Field Intensity", binding: edgeFieldBinding(\.fieldIntensity), range: 0.01...1, resetValue: defaultEdgeField.fieldIntensity)
                adjustmentSlider(label: "Levels", binding: contourLevelsBinding, range: 2...24, resetValue: Double(defaultEdgeField.contourLevels))
                adjustmentSlider(label: "Line Width", binding: edgeFieldBinding(\.thickness), range: 0.05...1, resetValue: defaultEdgeField.thickness)
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: edgeInvertBinding)
                }

                labeledColorPicker("Contour Color", selection: Binding(
                    get: { nsColor(from: payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.edgeColor = codable
                        onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                    }
                ))
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .voronoi {
                adjustmentSlider(label: "Cell Size", binding: voronoiCellSizeBinding, range: 2...64, resetValue: defaultEdgeField.cellSize)
                adjustmentSlider(label: "Wall Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1, resetValue: defaultEdgeField.lineStrength)
                adjustmentSlider(label: "Cell Fill", binding: edgeFieldBinding(\.fieldIntensity), range: 0...1, resetValue: defaultEdgeField.fieldIntensity)
                adjustmentSlider(label: "Edge Width", binding: voronoiEdgeWidthBinding, range: 0.05...1, resetValue: defaultEdgeField.edgeWidth)
                SidebarControlRow("Randomize") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: voronoiRandomizeBinding)
                }

                labeledColorPicker("Edge Color", selection: Binding(
                    get: { nsColor(from: payload.edgeColor ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.edgeColor = codable
                        onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: updatedPayload)))
                    }
                ))
            }

            if case .printSampling(let common, let geometry, let color, let payload) = params.params {
                if params.kind == .halftone {
                    Picker("", selection: halftoneShapeBinding) {
                        Text("Circle").tag(HalftoneShape.circle)
                        Text("Square").tag(HalftoneShape.square)
                        Text("Diamond").tag(HalftoneShape.diamond)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Shape")

                    adjustmentSlider(label: "Angle", binding: halftoneAngleBinding, range: 0...90, resetValue: defaultPrintSampling.halftoneAngle)

                    SidebarControlRow("Invert") {
                        EmptyView()
                    } trailingValue: {
                    StyledToggle(isOn: invertBinding)
                    }
                }

                if params.kind == .crosshatch {
                    // Threshold is the luminance cutoff that decides which pixels
                    // get inked (shader: `bool dark = lum < u.threshold`). Users
                    // previously couldn't tune this — default was the only value.
                    adjustmentSlider(label: "Threshold", binding: printSamplingBinding(\.threshold), range: 0...1, resetValue: defaultPrintSampling.threshold)
                    adjustmentSlider(label: "Density", binding: hatchDensityBinding, range: 0...1, resetValue: defaultPrintSampling.hatchDensity)
                    // Max 3 matches the GPU clamp (PrintSamplingGPURenderer
                    // caps hatchLayers at 3) — position 4 was a no-op.
                    adjustmentSlider(label: "Layers", binding: hatchLayersBinding, range: 1...3, resetValue: Double(defaultPrintSampling.hatchLayers))
                    adjustmentSlider(label: "Angle", binding: hatchAngleBinding, range: 0...90, resetValue: defaultPrintSampling.hatchAngle)
                    adjustmentSlider(label: "Line Width", binding: hatchLineWidthBinding, range: 0.05...1, resetValue: defaultPrintSampling.hatchLineWidth)
                    adjustmentSlider(label: "Random", binding: hatchRandomnessBinding, range: 0...1, resetValue: defaultPrintSampling.hatchRandomness)
                    SidebarControlRow("Invert") {
                        EmptyView()
                    } trailingValue: {
                    StyledToggle(isOn: invertBinding)
                    }
                }

                if params.kind == .threshold {
                    // Core cutoff — shader decides ink vs paper by `quantized < u.threshold`.
                    // Not exposed before so users were stuck at the default.
                    adjustmentSlider(label: "Threshold", binding: printSamplingBinding(\.threshold), range: 0...1, resetValue: defaultPrintSampling.threshold)
                    adjustmentSlider(label: "Levels", binding: thresholdLevelsBinding, range: 2...8, resetValue: Double(defaultPrintSampling.thresholdLevels))
                    SidebarControlRow("Dither") {
                        EmptyView()
                    } trailingValue: {
                    StyledToggle(isOn: thresholdDitherBinding)
                    }
                    SidebarControlRow("Invert") {
                        EmptyView()
                    } trailingValue: {
                    StyledToggle(isOn: invertBinding)
                    }
                }

                labeledColorPicker("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: updatedPayload)))
                    }
                ))

                labeledColorPicker("Background", selection: Binding(
                    get: { nsColor(from: payload.background ?? CodableColor(unchecked: "#000000")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.background = codable
                        onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: updatedPayload)))
                    }
                ))
            }
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
        Binding(
            get: { Self.geometry(for: params.params).scale },
            set: { newValue in onChange(Self.updatingGeometry(params, scale: newValue, spacing: nil, outputWidth: nil)) }
        )
    }

    private var spacingBinding: Binding<Double> {
        Binding(
            get: { Self.geometry(for: params.params).spacing },
            set: { newValue in onChange(Self.updatingGeometry(params, scale: nil, spacing: newValue, outputWidth: nil)) }
        )
    }

    private var outputWidthBinding: Binding<Double> {
        Binding(
            get: { Double(Self.geometry(for: params.params).outputWidth) },
            set: { newValue in onChange(Self.updatingGeometry(params, scale: nil, spacing: nil, outputWidth: Int(newValue.rounded()))) }
        )
    }

    private static func geometry(for params: GPUEffectParameters) -> GPUEffectGeometryParameters {
        switch params {
        case .textCell(_, let geometry, _, _),
             .printSampling(_, let geometry, _, _),
             .edgeField(_, let geometry, _, _),
             .glitch(_, let geometry, _, _):
            return geometry
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

    private func adjustmentSlider(label: String, binding: Binding<Double>, range: ClosedRange<Double>, resetValue: Double? = nil) -> some View {
        DenseSliderControlRow(
            title: LocalizedStringKey(label),
            value: binding,
            range: range,
            step: 0.05,
            resetValue: resetValue
        )
    }

    // MARK: Canonical per-kind defaults (double-click-to-reset targets).
    // Derived from GPUEffectKind.defaultParameters() so reset values can
    // never drift from the values a fresh layer starts with.

    private var kindDefaults: GPUEffectParameters { params.kind.defaultParameters() }

    private var defaultCommon: GPUEffectCommonParameters { Self.common(for: kindDefaults) }
    private var defaultGeometry: GPUEffectGeometryParameters { Self.geometry(for: kindDefaults) }
    private var defaultColor: GPUEffectColorParameters { Self.color(for: kindDefaults) }

    private var defaultTextCell: TextCellParameters {
        if case .textCell(_, _, _, let payload) = kindDefaults { return payload }
        return TextCellParameters()
    }

    private var defaultPrintSampling: PrintSamplingParameters {
        if case .printSampling(_, _, _, let payload) = kindDefaults { return payload }
        return PrintSamplingParameters()
    }

    private var defaultEdgeField: EdgeFieldParameters {
        if case .edgeField(_, _, _, let payload) = kindDefaults { return payload }
        return EdgeFieldParameters()
    }

    private var defaultGlitch: GlitchParameters {
        if case .glitch(_, _, _, let payload) = kindDefaults { return payload }
        return GlitchParameters()
    }

    /// Preset dropdown + saved-palettes menu + per-colour editor for the
    /// `.palette` colour mode. Mirrors DitherLayerControls.paletteEditor:
    /// preset selection is derived from the current colours, so editing a
    /// swatch that diverges from every preset flips the picker to Custom.
    @ViewBuilder
    private func gpuPaletteEditor() -> some View {
        let colors = Self.color(for: params.params).palette ?? VintagePalette.gameBoy
        let selectedPreset = VintagePalette.Preset.matching(colors)

        SidebarFullWidthRow("Palette") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Preset", selection: Binding<VintagePalette.Preset>(
                    get: { selectedPreset },
                    set: { newValue in
                        guard newValue != selectedPreset else { return }
                        var c = Self.color(for: params.params)
                        switch newValue {
                        case .custom:
                            // Seed Custom with the current colours plus a
                            // neutral swatch so the result can't match a
                            // preset and snap the picker back (same dance
                            // as the Dither editor).
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

                UserPaletteMenu(currentColors: colors) { applied in
                    var c = Self.color(for: params.params)
                    c.palette = applied
                    onChange(Self.updatingColor(params, color: c))
                }

                SidebarPaletteEditor(
                    colors: gpuPaletteColorsBinding(currentColors: colors),
                    maxColors: FramerColorUniformsLayout.maxPaletteColors,
                    minColors: 2,
                    defaultNewColor: colors.last ?? CodableColor(unchecked: "#000000")
                )
            }
        }
    }

    private func gpuPaletteColorsBinding(currentColors colors: [CodableColor]) -> Binding<[CodableColor]> {
        Binding(
            get: { colors },
            set: { newColors in
                var c = Self.color(for: params.params)
                c.palette = newColors
                onChange(Self.updatingColor(params, color: c))
            }
        )
    }

    private var colorModeBinding: Binding<GPUEffectColorMode> {
        Binding(
            get: { Self.color(for: params.params).mode },
            set: { newValue in
                var current = Self.color(for: params.params)
                current.mode = newValue
                onChange(Self.updatingColor(params, color: current))
            }
        )
    }

    private var backgroundIntensityBinding: Binding<Double> {
        Binding(
            get: { Self.color(for: params.params).backgroundIntensity },
            set: { newValue in
                var current = Self.color(for: params.params)
                current.backgroundIntensity = newValue
                onChange(Self.updatingColor(params, color: current))
            }
        )
    }

    private func commonBinding(_ keyPath: WritableKeyPath<GPUEffectCommonParameters, Double>) -> Binding<Double> {
        Binding(
            get: { Self.common(for: params.params)[keyPath: keyPath] },
            set: { newValue in
                var current = Self.common(for: params.params)
                current[keyPath: keyPath] = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.direction = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.characterSet = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.dotShape = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.gridType = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.invert = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.blockStyle = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload.borderWidth = newValue
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
            set: { newValue in
                guard case .textCell(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.halftoneShape = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.halftoneAngle = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.invert = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchDensity = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchLayers = max(1, Int(newValue.rounded()))
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchAngle = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchLineWidth = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.hatchRandomness = newValue
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.thresholdLevels = max(2, Int(newValue.rounded()))
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
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload.thresholdDither = newValue
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
            set: { newValue in
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = newValue
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
            set: { newValue in
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload.direction = newValue
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
            set: { newValue in
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload.sortMode = newValue
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
            set: { newValue in
                guard case .glitch(let common, let geometry, let color, var payload) = params.params else { return }
                payload.reverse = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = newValue
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
    }

    private func printSamplingBinding(_ keyPath: WritableKeyPath<PrintSamplingParameters, Double>) -> Binding<Double> {
        Binding(
            get: {
                if case .printSampling(_, _, _, let payload) = params.params {
                    return payload[keyPath: keyPath]
                }
                return 0
            },
            set: { newValue in
                guard case .printSampling(let common, let geometry, let color, var payload) = params.params else { return }
                payload[keyPath: keyPath] = newValue
                onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)))
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.direction = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.noiseType = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.octaves = max(1, Int(newValue.rounded()))
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.edgeAlgorithm = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.edgeThreshold = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.invert = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.contourFillMode = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.contourLevels = max(2, Int(newValue.rounded()))
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.cellSize = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.edgeWidth = newValue
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
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.randomize = newValue
                onChange(updated(layer: params, params: .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)))
            }
        )
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

    private func nsColor(from color: CodableColor) -> Color {
        Color(nsColor: NSColor(cgColor: color.cgColor) ?? .white)
    }
}

