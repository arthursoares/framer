import SwiftUI
import AppKit
import FramerCore

// MARK: - LayerListSection

struct LayerListSection: View {
    @Binding var layers: [CompositionLayer]
    @Environment(\.undoManager) private var undoManager
    @State private var draggingLayerID: UUID?
    @State private var dropTargetIndex: Int?

    var body: some View {
        SidebarSection(metrics: SidebarMetrics(expandedBodyInset: 0)) {
            Text("LAYERS (\(layers.count))")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                    VStack(spacing: 0) {
                        if dropTargetIndex == index {
                            dropIndicator
                        }

                        LayerPanelRow(
                            layer: binding(for: layer),
                            isDragging: draggingLayerID == layer.id,
                            isDropTarget: dropTargetIndex == index,
                            onDelete: { removeLayer(at: index) },
                            onMoveUp: index > 0 ? { moveLayer(from: index, to: index - 1) } : nil,
                            onMoveDown: index < layers.count - 1 ? { moveLayer(from: index, to: index + 1) } : nil
                        )
                        .draggable(layer.id.uuidString) {
                            let draggingStyle = SidebarStateStyle.dragging

                            return Label(layer.label, systemImage: layer.iconName)
                                .foregroundStyle(draggingStyle.foregroundColor)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(
                                    draggingStyle.backgroundColor,
                                    in: RoundedRectangle(cornerRadius: CornerRadius.md)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .stroke(draggingStyle.borderColor, lineWidth: 1)
                                )
                                .onAppear { draggingLayerID = layer.id }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            dropTargetIndex = nil
                            draggingLayerID = nil
                            guard let droppedIDString = items.first,
                                  let droppedID = UUID(uuidString: droppedIDString),
                                  let fromIndex = layers.firstIndex(where: { $0.id == droppedID }),
                                  fromIndex != index else { return false }

                            let toOffset = index > fromIndex ? index + 1 : index
                            let snapshot = layers
                            let layersBinding = $layers

                            withAnimation(.easeInOut(duration: 0.2)) {
                                layers.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
                            }

                            undoManager?.registerUndo(withTarget: UndoProxy.shared) { @MainActor _ in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    layersBinding.wrappedValue = snapshot
                                }
                            }

                            undoManager?.setActionName("Move Layer")
                            return true
                        } isTargeted: { targeted in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
                            }
                        }

                        if index == layers.count - 1 && dropTargetIndex == layers.count {
                            dropIndicator
                        }
                    }
                }

                addLayerMenu
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private var dropIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accent)
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(Color.accent)
                .frame(height: 2)
            Circle()
                .fill(Color.accent)
                .frame(width: 5, height: 5)
        }
        .padding(.vertical, 2)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private var addLayerMenu: some View {
        Menu {
            Button {
                addLayer(.aspectRatio(AspectRatioLayerParams()))
            } label: {
                Label("Aspect Ratio", systemImage: "crop")
            }
            Button {
                addLayer(.border(BorderLayerParams()))
            } label: {
                Label("Border", systemImage: "square.dashed")
            }
            Button {
                addLayer(.padding(PaddingLayerParams()))
            } label: {
                Label("Padding", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                addLayer(.canvas(CanvasLayerParams()))
            } label: {
                Label("Canvas", systemImage: "rectangle.on.rectangle")
            }
            Button {
                addLayer(.resize(ResizeLayerParams()))
            } label: {
                Label("Resize", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            Button {
                addLayer(.orientation(OrientationLayerParams()))
            } label: {
                Label("Orientation", systemImage: "rotate.right")
            }
            Button {
                addLayer(.caption(CaptionLayerParams()))
            } label: {
                Label("Caption", systemImage: "textformat")
            }
            Button {
                addLayer(.dither(DitherLayerParams()))
            } label: {
                Label("Dither", systemImage: "circle.dotted")
            }
            Divider()
            Button {
                addLayer(.overlay(OverlayLayerParams(kind: .frame)))
            } label: {
                Label("Frame Overlay", systemImage: "photo.artframe")
            }
            Button {
                addLayer(.overlay(OverlayLayerParams(kind: .dust)))
            } label: {
                Label("Dust & Scratches", systemImage: "sparkles")
            }
            Button {
                addLayer(.overlay(OverlayLayerParams(kind: .lightLeak)))
            } label: {
                Label("Light Leak", systemImage: "sun.max.trianglebadge.exclamationmark")
            }
            Button {
                addLayer(.overlay(OverlayLayerParams(kind: .wetPlate)))
            } label: {
                Label("Wet Plate", systemImage: "drop.halffull")
            }
            Divider()
            Button {
                addLayer(.lut(LUTLayerParams()))
            } label: {
                Label("LUT", systemImage: "photo.artframe")
            }
            // One menu entry per shader style. Each constructs a `.shader`
            // layer pre-scoped to that specific style with its default
            // parameters. Mirrors the `GPUEffectKind` pattern below so
            // shaders feel like first-class filters (ASCII, Kuwahara, CRT,
            // …) rather than being tucked under a single umbrella "+
            // Shader" button that asks the user to pick a style afterward.
            ForEach(ShaderStyle.allCases, id: \.self) { style in
                Button { addLayer(style.makeDefaultLayer()) } label: {
                    Label(style.label, systemImage: style.menuIcon)
                }
            }
            Divider()
            // One menu entry per user-facing GPU-effect variant. Each
            // constructs a .gpuEffect layer pre-scoped to that specific kind
            // with sensible default parameters — so "+ Dots" feels like its
            // own layer type even though the underlying data model is still
            // the shared .gpuEffect case. Avoids the confusion of a single
            // "+ GPU Effect" umbrella that then asks users to pick a variant.
            ForEach(GPUEffectKind.userFacingCases, id: \.self) { kind in
                Button { addLayer(kind.makeDefaultLayer()) } label: {
                    Label(kind.label, systemImage: kind.menuIcon)
                }
            }
        } label: {
            Label("Add Layer", systemImage: "plus.circle")
                .foregroundStyle(Color.text2)
        }
    }

    private func removeLayer(at index: Int) {
        let removed = layers[index]
        let layersBinding = $layers
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            layers.remove(at: index)
        }
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { @MainActor _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                let insertAt = min(index, layersBinding.wrappedValue.count)
                layersBinding.wrappedValue.insert(removed, at: insertAt)
            }
        }
        undoManager?.setActionName("Delete Layer")
    }

    private func addLayer(_ layer: CompositionLayer) {
        let layersBinding = $layers
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.append(layer)
        }
        let addedIndex = layers.count - 1
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { @MainActor _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                if addedIndex < layersBinding.wrappedValue.count {
                    layersBinding.wrappedValue.remove(at: addedIndex)
                }
            }
        }
        undoManager?.setActionName("Add Layer")
    }

    private func moveLayer(from source: Int, to destination: Int) {
        let layersBinding = $layers
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.swapAt(source, destination)
        }
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { @MainActor _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                layersBinding.wrappedValue.swapAt(destination, source)
            }
        }
        undoManager?.setActionName("Move Layer")
    }

    /// ID-keyed binding. Previously this was indexed by `Int`, which captured
    /// the index at creation time — SwiftUI reads a detail view's binding
    /// once after its row is deleted or reordered (before the view is torn
    /// down), and `layers[staleIdx]` went out of bounds. Looking up by
    /// `layer.id` keeps the read valid across any structural mutation.
    ///
    /// The captured `fallback` is the layer value as of binding-creation
    /// time. It's only used if the layer has been removed AND `layers` is
    /// empty (deleting the last row) — SwiftUI's teardown tick would
    /// otherwise read `layers[0]` on an empty array. Returning the
    /// snapshot lets the dying view finish its render cycle cleanly.
    private func binding(for layer: CompositionLayer) -> Binding<CompositionLayer> {
        let id = layer.id
        let fallback = layer
        return Binding(
            get: { layers.first(where: { $0.id == id }) ?? fallback },
            set: { newValue in
                if let idx = layers.firstIndex(where: { $0.id == id }) {
                    layers[idx] = newValue
                }
            }
        )
    }
}

/// Proxy target for UndoManager since it requires NSObject.
@MainActor
private final class UndoProxy: NSObject, Sendable {
    static let shared = UndoProxy()
}

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
                        step: 0.05
                    )
                } secondary: {
                    DenseSliderControlRow(
                        title: "Spacing",
                        value: spacingBinding,
                        range: 1...8,
                        step: 0.1
                    )
                }
            }

            if params.kind.usesColorModeAndFgBg {
                // Palette was dead on every variant that uses this picker
                // (dots / blockify / matrixRain / threshold / crosshatch /
                // edgeDetection): the bucket uniform struct has no palette
                // array, so the shader had nothing to quantise against.
                // Dropped from the menu until the bucket renderer grows a
                // palette uniform the way DitherGPURenderer has.
                Picker("", selection: colorModeBinding) {
                    Text("Source").tag(GPUEffectColorMode.source)
                    Text("FG/BG").tag(GPUEffectColorMode.foregroundBackground)
                    Text("Mono").tag(GPUEffectColorMode.monochrome)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Color Mode")
            }

            if params.kind.usesBackgroundIntensity || params.kind.usesColorModeAndFgBg {
                DenseSliderControlRow(
                    title: "Background",
                    value: backgroundIntensityBinding,
                    range: 0...1,
                    step: 0.05
                )
            }

            // Common adjustments (brightness / contrast / etc.) are NOT consumed
            // by any bucket shader today — per GPUEffectKind.usesCommonAdjustments.
            // Hidden globally. If shaders are later extended to apply them,
            // flip the flag and they'll light up on the correct variants.
            if params.kind.usesCommonAdjustments {
                adjustmentSlider(label: "Brightness", binding: commonBinding(\.brightness), range: -1...1)
                adjustmentSlider(label: "Contrast", binding: commonBinding(\.contrast), range: 0...3)
                adjustmentSlider(label: "Saturation", binding: commonBinding(\.saturation), range: 0...2)
                adjustmentSlider(label: "Hue", binding: commonBinding(\.hueRotation), range: -1...1)
                adjustmentSlider(label: "Sharpness", binding: commonBinding(\.sharpness), range: 0...2)
                adjustmentSlider(label: "Gamma", binding: commonBinding(\.gamma), range: 0.2...2)
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

                adjustmentSlider(label: "Intensity", binding: textCellBinding(\.intensity), range: 0...1)

                ColorPickerWithHex("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                ColorPickerWithHex("Background", selection: Binding(
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

                adjustmentSlider(label: "Dot Size", binding: textCellBinding(\.sizeMultiplier), range: 0.1...2.0)
                adjustmentSlider(label: "Intensity", binding: textCellBinding(\.intensity), range: 0...1)
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: textInvertBinding)
                }

                ColorPickerWithHex("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                ColorPickerWithHex("Background", selection: Binding(
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
                adjustmentSlider(label: "Border Width", binding: blockBorderWidthBinding, range: 0...1)

                ColorPickerWithHex("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                ColorPickerWithHex("Background", selection: Binding(
                    get: { nsColor(from: payload.background ?? CodableColor(unchecked: "#111111")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.background = codable
                        onChange(updated(layer: params, params: .textCell(common: common, geometry: geometry, color: color, textCell: updatedPayload)))
                    }
                ))

                ColorPickerWithHex("Border Color", selection: Binding(
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
                adjustmentSlider(label: "Speed", binding: matrixBinding(\.speed), range: 0...1)
                adjustmentSlider(label: "Trail", binding: matrixBinding(\.trailLength), range: 0...1)
                adjustmentSlider(label: "Glow", binding: matrixBinding(\.glow), range: 0...1)
                adjustmentSlider(label: "BG Opacity", binding: matrixBinding(\.backgroundOpacity), range: 0...1)
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

                ColorPickerWithHex("Rain Color", selection: Binding(
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

                adjustmentSlider(label: "Streak", binding: glitchBinding(\.streakLength), range: 0...1)
                adjustmentSlider(label: "Random", binding: glitchBinding(\.randomness), range: 0...1)
                SidebarControlRow("Reverse") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: reverseBinding)
                }
            }

            if case .glitch(_, _, _, _) = params.params,
               params.kind == .vhs {
                adjustmentSlider(label: "Distortion", binding: glitchBinding(\.distortion), range: 0...1)
                adjustmentSlider(label: "Color Bleed", binding: glitchBinding(\.colorBleed), range: 0...1)
                adjustmentSlider(label: "Scanlines", binding: glitchBinding(\.scanlines), range: 0...1)
                adjustmentSlider(label: "Tracking", binding: glitchBinding(\.trackingError), range: 0...1)
            }

            if case .edgeField = params.params,
               params.kind == .waveLines {
                // Line Strength drives the shader's threshold shaping — primary
                // brightness knob, was missing from UI before.
                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Amplitude", binding: edgeFieldBinding(\.amplitude), range: 0...1)
                adjustmentSlider(label: "Frequency", binding: edgeFieldBinding(\.frequency), range: 0.1...4)
                adjustmentSlider(label: "Thickness", binding: edgeFieldBinding(\.thickness), range: 0.05...1)

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
                adjustmentSlider(label: "Line Count", binding: edgeFieldBinding(\.lineCount), range: 1...40)
                // Animate stays hidden — no time uniform yet.
            }

            if case .edgeField = params.params,
               params.kind == .noiseField {
                // Line Strength gates the noise contribution (shader:
                // `noise * u.lineStrength + fieldWeight * 0.3`). Field Intensity
                // biases the baseline level. Both were missing from UI.
                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Field Intensity", binding: edgeFieldBinding(\.fieldIntensity), range: 0...1)
                adjustmentSlider(label: "Octaves", binding: noiseOctavesBinding, range: 1...6)
                adjustmentSlider(label: "Scale", binding: edgeFieldBinding(\.amplitude), range: 0.1...1)
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
                // Speed + Animate stay hidden (no time uniform yet).
                // Distort Only stays hidden (shader generates standalone,
                // doesn't distort source UVs).
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

                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Threshold", binding: edgeThresholdBinding, range: 0...1)
                adjustmentSlider(label: "Line Width", binding: edgeFieldBinding(\.thickness), range: 0.05...1)
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: edgeInvertBinding)
                }

                ColorPickerWithHex("Edge Color", selection: Binding(
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

                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Field Intensity", binding: edgeFieldBinding(\.fieldIntensity), range: 0.01...1)
                adjustmentSlider(label: "Levels", binding: contourLevelsBinding, range: 2...24)
                adjustmentSlider(label: "Line Width", binding: edgeFieldBinding(\.thickness), range: 0.05...1)
                SidebarControlRow("Invert") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: edgeInvertBinding)
                }

                ColorPickerWithHex("Contour Color", selection: Binding(
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
                adjustmentSlider(label: "Cell Size", binding: voronoiCellSizeBinding, range: 2...64)
                adjustmentSlider(label: "Wall Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Cell Fill", binding: edgeFieldBinding(\.fieldIntensity), range: 0...1)
                adjustmentSlider(label: "Edge Width", binding: voronoiEdgeWidthBinding, range: 0.05...1)
                SidebarControlRow("Randomize") {
                    EmptyView()
                } trailingValue: {
                    StyledToggle(isOn: voronoiRandomizeBinding)
                }

                ColorPickerWithHex("Edge Color", selection: Binding(
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

                    adjustmentSlider(label: "Angle", binding: halftoneAngleBinding, range: 0...90)

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
                    adjustmentSlider(label: "Threshold", binding: printSamplingBinding(\.threshold), range: 0...1)
                    adjustmentSlider(label: "Density", binding: hatchDensityBinding, range: 0...1)
                    adjustmentSlider(label: "Layers", binding: hatchLayersBinding, range: 1...4)
                    adjustmentSlider(label: "Angle", binding: hatchAngleBinding, range: 0...90)
                    adjustmentSlider(label: "Line Width", binding: hatchLineWidthBinding, range: 0.05...1)
                    adjustmentSlider(label: "Random", binding: hatchRandomnessBinding, range: 0...1)
                    SidebarControlRow("Invert") {
                        EmptyView()
                    } trailingValue: {
                    StyledToggle(isOn: invertBinding)
                    }
                }

                if params.kind == .threshold {
                    // Core cutoff — shader decides ink vs paper by `quantized < u.threshold`.
                    // Not exposed before so users were stuck at the default.
                    adjustmentSlider(label: "Threshold", binding: printSamplingBinding(\.threshold), range: 0...1)
                    adjustmentSlider(label: "Levels", binding: thresholdLevelsBinding, range: 2...8)
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

                ColorPickerWithHex("Foreground", selection: Binding(
                    get: { nsColor(from: payload.foreground ?? CodableColor(unchecked: "#FFFFFF")) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        var updatedPayload = payload
                        updatedPayload.foreground = codable
                        onChange(updated(layer: params, params: .printSampling(common: common, geometry: geometry, color: color, printSampling: updatedPayload)))
                    }
                ))

                ColorPickerWithHex("Background", selection: Binding(
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
                copy.params = Self.defaultParams(for: newKind)
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

    private static func defaultParams(for kind: GPUEffectKind) -> GPUEffectParameters {
        switch kind {
        case .ascii:
            return .textCell(common: .init(), geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240), color: .init(mode: .foregroundBackground, backgroundIntensity: 0.2), textCell: .init(characterSet: .classicASCII, variant: .ascii))
        case .matrixRain:
            return .textCell(common: .init(), geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240), color: .init(mode: .foregroundBackground, backgroundIntensity: 0.2), textCell: .init(characterSet: .classicASCII, variant: .matrixRain))
        case .blockify:
            return .textCell(common: .init(), geometry: .init(scale: 1.0, spacing: 3.0, outputWidth: 240), color: .init(mode: .source, backgroundIntensity: 0.0), textCell: .init(characterSet: .classicASCII, variant: .blockify))
        case .dots:
            return .textCell(common: .init(), geometry: .init(scale: 0.9, spacing: 4.0, outputWidth: 240), color: .init(mode: .monochrome, backgroundIntensity: 0.1), textCell: .init(characterSet: .classicASCII, variant: .dots))
        case .dithering:
            return .printSampling(common: .init(), geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240), color: .init(mode: .monochrome, backgroundIntensity: 0.1), printSampling: .init(variant: .dithering, sampleDensity: 0.5, threshold: 0.5))
        case .halftone:
            return .printSampling(common: .init(), geometry: .init(scale: 0.9, spacing: 3.0, outputWidth: 240), color: .init(mode: .source, backgroundIntensity: 0.0), printSampling: .init(variant: .halftone, sampleDensity: 0.7, threshold: 0.4))
        case .threshold:
            return .printSampling(common: .init(), geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240), color: .init(mode: .monochrome, backgroundIntensity: 0.2), printSampling: .init(variant: .threshold, sampleDensity: 0.5, threshold: 0.6))
        case .crosshatch:
            return .printSampling(common: .init(), geometry: .init(scale: 0.8, spacing: 4.0, outputWidth: 240), color: .init(mode: .foregroundBackground, backgroundIntensity: 0.15), printSampling: .init(variant: .crosshatch, sampleDensity: 0.65, threshold: 0.45))
        case .contour:
            return .edgeField(common: .init(), geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240), color: .init(mode: .monochrome, backgroundIntensity: 0.05), edgeField: .init(variant: .contour, lineStrength: 0.6, fieldIntensity: 0.7))
        case .edgeDetection:
            return .edgeField(common: .init(), geometry: .init(scale: 0.9, spacing: 2.0, outputWidth: 240), color: .init(mode: .foregroundBackground, backgroundIntensity: 0.1), edgeField: .init(variant: .edgeDetection, lineStrength: 0.8, fieldIntensity: 0.5))
        case .waveLines:
            return .edgeField(common: .init(), geometry: .init(scale: 1.2, spacing: 4.0, outputWidth: 240), color: .init(mode: .palette, backgroundIntensity: 0.2), edgeField: .init(variant: .waveLines, lineStrength: 0.5, fieldIntensity: 0.9))
        case .voronoi:
            return .edgeField(common: .init(), geometry: .init(scale: 1.1, spacing: 3.0, outputWidth: 240), color: .init(mode: .source, backgroundIntensity: 0.0), edgeField: .init(variant: .voronoi, lineStrength: 0.55, fieldIntensity: 0.85))
        case .noiseField:
            return .edgeField(common: .init(), geometry: .init(scale: 0.8, spacing: 5.0, outputWidth: 240), color: .init(mode: .monochrome, backgroundIntensity: 0.15), edgeField: .init(variant: .noiseField, lineStrength: 0.45, fieldIntensity: 0.95))
        case .pixelSort:
            return .glitch(common: .init(), geometry: .init(scale: 1.0, spacing: 1.0, outputWidth: 240), color: .init(mode: .source, backgroundIntensity: 0.0), glitch: .init(variant: .pixelSort, amount: 0.65, threshold: 0.42))
        case .vhs:
            return .glitch(common: .init(), geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240), color: .init(mode: .foregroundBackground, backgroundIntensity: 0.08), glitch: .init(variant: .vhs, amount: 0.75, threshold: 0.5))
        }
    }

    private func adjustmentSlider(label: String, binding: Binding<Double>, range: ClosedRange<Double>) -> some View {
        DenseSliderControlRow(
            title: LocalizedStringKey(label),
            value: binding,
            range: range,
            step: 0.05
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

    private var edgeAnimateBinding: Binding<Bool> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.animate
                }
                return false
            },
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.animate = newValue
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

    private var noiseSpeedBinding: Binding<Double> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.speed
                }
                return 0
            },
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.speed = newValue
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

    private var noiseDistortOnlyBinding: Binding<Bool> {
        Binding(
            get: {
                if case .edgeField(_, _, _, let payload) = params.params {
                    return payload.distortOnly
                }
                return false
            },
            set: { newValue in
                guard case .edgeField(let common, let geometry, let color, var payload) = params.params else { return }
                payload.distortOnly = newValue
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

// MARK: - BorderLayerControls

private extension View {
    func simpleLayerEditorInputStyle(width: CGFloat? = SidebarMetrics().controlValueFieldWidth) -> some View {
        self
            .textFieldStyle(.plain)
            .font(AppFont.numericInput)
            .foregroundStyle(Color.text1)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: width)
            .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Color.borderDefault, lineWidth: 1)
            )
    }

    func simpleLayerEditorInputStyle(width: CGFloat? = SidebarMetrics().controlValueFieldWidth, accessibilityLabel: String) -> some View {
        simpleLayerEditorInputStyle(width: width)
            .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct SimpleLayerEditorDivider: View {
    @Environment(\.sidebarMetrics) private var metrics

    var body: some View {
        Rectangle()
            .fill(Color.borderDefault)
            .frame(height: metrics.controlStackDividerThickness)
            .padding(.horizontal, metrics.controlStackDividerInset)
            .accessibilityHidden(true)
    }
}


struct BorderLayerControls: View {
    var params: BorderLayerParams
    var onChange: (BorderLayerParams) -> Void

    @State private var thicknessMode: ThicknessMode = .pixels

    private enum ThicknessMode: String, CaseIterable {
        case pixels = "px"
        case percent = "%"
    }

    init(params: BorderLayerParams, onChange: @escaping (BorderLayerParams) -> Void) {
        self.params = params
        self.onChange = onChange
        _thicknessMode = State(initialValue: Self.thicknessMode(for: params.thickness))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarMetrics().expandedBodyInset) {
            SidebarCompoundControlBlock {
                SidebarControlRow("Mode") {
                    Picker("Thickness Mode", selection: $thicknessMode) {
                        ForEach(ThicknessMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: SidebarMetrics().controlSegmentedModeWidth)
                    .labelsHidden()
                }
            } secondary: {
                SidebarControlRow("Thickness") {
                    Slider(value: thicknessValue, in: thicknessRange)
                        .tint(Color.accentDim)
                } trailingValue: {
                    SidebarTrailingUnitCluster(unit: LocalizedStringKey(thicknessMode.rawValue)) {
                        TextField("", value: thicknessValue, format: .number)
                            .simpleLayerEditorInputStyle(accessibilityLabel: "Thickness")
                            .monospacedDigit()
                    }
                }
            }

            ColorPickerWithHex("", selection: colorBinding)
                .denseControlRow("Color")
        }
        .onChange(of: params.thickness) { _, newThickness in
            thicknessMode = Self.thicknessMode(for: newThickness)
        }
    }

    private static func thicknessMode(for thickness: BorderSize) -> ThicknessMode {
        switch thickness {
        case .pixels:
            .pixels
        case .percent:
            .percent
        }
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
                switch thicknessMode {
                case .pixels: p.thickness = .pixels(Int(val))
                case .percent: p.thickness = .percent(val)
                }
                onChange(p)
            }
        )
    }

    private var thicknessRange: ClosedRange<Double> {
        thicknessMode == .pixels ? 0...300 : 0...20
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: params.color.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.color = c
                onChange(p)
            }
        )
    }
}

// MARK: - PaddingLayerControls

struct PaddingLayerControls: View {
    var params: PaddingLayerParams
    var onChange: (PaddingLayerParams) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarControlRow("Thickness") {
                Slider(value: thicknessBinding, in: 0...400)
                    .tint(Color.accentDim)
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: thicknessBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Thickness")
                        .monospacedDigit()
                }
            }

            SimpleLayerEditorDivider()

            LayerFillPicker(fill: params.fill) { newFill in
                var p = params
                p.fill = newFill
                onChange(p)
            }
        }
    }

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: { Double(params.thickness) },
            set: {
                var p = params
                p.thickness = Int($0)
                onChange(p)
            }
        )
    }
}

// MARK: - CanvasLayerControls

struct CanvasLayerControls: View {
    var params: CanvasLayerParams
    var onChange: (CanvasLayerParams) -> Void

    @State private var presetIndex: Int = 99
    @State private var sizeMode: SizeMode = .pixels
    @State private var physicalUnit: PhysicalUnit = .cm
    @State private var widthPhysical: Double = 10.0
    @State private var heightPhysical: Double = 15.0
    @State private var dpi: Int = 300

    private enum SizeMode: String, CaseIterable {
        case pixels = "Pixels"
        case physical = "Physical"
    }

    enum PhysicalUnit: String, CaseIterable {
        case cm = "cm"
        case mm = "mm"

        var toMM: Double {
            switch self {
            case .cm: return 10.0
            case .mm: return 1.0
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarCompoundControlBlock {
                SidebarControlRow("Preset") {
                    presetPicker
                        .labelsHidden()
                }
            } secondary: {
                SidebarControlRow("Size Mode") {
                    Picker("Size Mode", selection: $sizeMode) {
                        ForEach(SizeMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            SimpleLayerEditorDivider()

            if sizeMode == .pixels {
                pixelFields
            } else {
                physicalFields

                SimpleLayerEditorDivider()

                pixelSummary
            }

            SimpleLayerEditorDivider()

            LayerFillPicker(fill: params.fill) { newFill in
                var p = params
                p.fill = newFill
                onChange(p)
            }
        }
        .onAppear(perform: syncEditorStateFromParams)
        .onChange(of: params) { _, _ in
            syncEditorStateFromParams()
        }
    }

    // MARK: - Subviews

    private var presetPicker: some View {
        Picker("Preset", selection: $presetIndex) {
            Text("Instagram 4:5").tag(0)
            Text("10x15 cm (300dpi)").tag(1)
            Text("13x18 cm (300dpi)").tag(2)
            Text("A4 (300dpi)").tag(3)
            Text("Custom").tag(99)
        }
        .onChange(of: presetIndex) { _, preset in
            applyPreset(preset)
        }
    }

    private var pixelFields: some View {
        SidebarCompoundControlBlock {
            SidebarControlRow("Width") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: widthBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Width")
                        .monospacedDigit()
                }
            }
        } secondary: {
            SidebarControlRow("Height") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: heightBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Height")
                        .monospacedDigit()
                }
            }
        }
    }

    private var physicalFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarCompoundControlBlock {
                SidebarControlRow("Unit") {
                    Picker("Unit", selection: $physicalUnit) {
                        ForEach(PhysicalUnit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: SidebarMetrics().controlUnitPickerWidth)
                    .labelsHidden()
                    .onChange(of: physicalUnit) { oldUnit, newUnit in
                        convertUnit(from: oldUnit, to: newUnit)
                    }
                }
            } secondary: {
                SidebarControlRow("DPI") {
                    EmptyView()
                } trailingValue: {
                    SidebarTrailingUnitCluster(unit: "dpi") {
                        TextField("", value: $dpi, format: .number)
                            .simpleLayerEditorInputStyle(accessibilityLabel: "DPI")
                            .monospacedDigit()
                            .onChange(of: dpi) { _, _ in syncPhysicalToPixels() }
                    }
                }
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                SidebarControlRow("Width") {
                    EmptyView()
                } trailingValue: {
                    SidebarTrailingUnitCluster(unit: LocalizedStringKey(physicalUnit.rawValue)) {
                        TextField("", value: $widthPhysical, format: .number.precision(.fractionLength(1)))
                            .simpleLayerEditorInputStyle(accessibilityLabel: "Width")
                            .monospacedDigit()
                            .onChange(of: widthPhysical) { _, _ in syncPhysicalToPixels() }
                    }
                }
            } secondary: {
                SidebarControlRow("Height") {
                    EmptyView()
                } trailingValue: {
                    SidebarTrailingUnitCluster(unit: LocalizedStringKey(physicalUnit.rawValue)) {
                        TextField("", value: $heightPhysical, format: .number.precision(.fractionLength(1)))
                            .simpleLayerEditorInputStyle(accessibilityLabel: "Height")
                            .monospacedDigit()
                            .onChange(of: heightPhysical) { _, _ in syncPhysicalToPixels() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pixelSummary: some View {
        if sizeMode == .physical {
            SidebarControlRow("Output Pixels") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingReadoutCluster(unit: "px") {
                    Text("\(params.width)×\(params.height)")
                        .font(AppFont.mono(10))
                        .foregroundStyle(Color.text3)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Pixel Bindings

    private var widthBinding: Binding<Int> {
        Binding(
            get: { params.width },
            set: {
                var p = params
                p.width = $0
                onChange(p)
                presetIndex = 99
            }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { params.height },
            set: {
                var p = params
                p.height = $0
                onChange(p)
                presetIndex = 99
            }
        )
    }

    // MARK: - Physical <-> Pixel Conversion

    private func syncPhysicalToPixels() {
        let wMM = widthPhysical * physicalUnit.toMM
        let hMM = heightPhysical * physicalUnit.toMM
        let safeDPI = max(dpi, 1)
        var p = params
        p.width = Int((wMM / 25.4) * Double(safeDPI))
        p.height = Int((hMM / 25.4) * Double(safeDPI))
        onChange(p)
        presetIndex = 99
    }

    private func convertUnit(from oldUnit: PhysicalUnit, to newUnit: PhysicalUnit) {
        // Convert current values to mm, then to new unit
        let wMM = widthPhysical * oldUnit.toMM
        let hMM = heightPhysical * oldUnit.toMM
        widthPhysical = wMM / newUnit.toMM
        heightPhysical = hMM / newUnit.toMM
    }

    private func syncEditorStateFromParams() {
        presetIndex = matchingPresetIndex(for: params)
        syncPhysicalStateFromParams()
    }

    private func syncPhysicalStateFromParams() {
        let safeDPI = max(dpi, 1)
        let widthMM = Double(params.width) / Double(safeDPI) * 25.4
        let heightMM = Double(params.height) / Double(safeDPI) * 25.4
        widthPhysical = widthMM / physicalUnit.toMM
        heightPhysical = heightMM / physicalUnit.toMM
    }

    private func matchingPresetIndex(for params: CanvasLayerParams) -> Int {
        switch (params.width, params.height) {
        case (1080, 1350): return 0
        case (1771, 1181): return 1
        case (2125, 1535): return 2
        case (3507, 2480): return 3
        default: return 99
        }
    }

    // MARK: - Presets

    private func applyPreset(_ preset: Int) {
        var p = params
        switch preset {
        case 0:
            p.width = 1080; p.height = 1350
            applyPixelPreset(p)
        case 1:
            applyPhysicalPreset(widthCM: 15, heightCM: 10, dpi: 300, params: &p)
        case 2:
            applyPhysicalPreset(widthCM: 18, heightCM: 13, dpi: 300, params: &p)
        case 3:
            applyPhysicalPreset(widthCM: 29.7, heightCM: 21.0, dpi: 300, params: &p)
        default:
            return
        }
        onChange(p)
    }

    private func applyPixelPreset(_ p: CanvasLayerParams) {
        // When applying a pixel-only preset (Instagram), sync physical fields
        let safeDPI = max(dpi, 1)
        let wMM = Double(p.width) / Double(safeDPI) * 25.4
        let hMM = Double(p.height) / Double(safeDPI) * 25.4
        widthPhysical = wMM / physicalUnit.toMM
        heightPhysical = hMM / physicalUnit.toMM
    }

    private func applyPhysicalPreset(widthCM: Double, heightCM: Double, dpi newDPI: Int, params p: inout CanvasLayerParams) {
        dpi = newDPI
        switch physicalUnit {
        case .cm:
            widthPhysical = widthCM
            heightPhysical = heightCM
        case .mm:
            widthPhysical = widthCM * 10
            heightPhysical = heightCM * 10
        }
        let wMM = widthCM * 10
        let hMM = heightCM * 10
        p.width = Int((wMM / 25.4) * Double(newDPI))
        p.height = Int((hMM / 25.4) * Double(newDPI))
    }
}

// MARK: - ResizeLayerControls

struct ResizeLayerControls: View {
    var params: ResizeLayerParams
    var onChange: (ResizeLayerParams) -> Void

    var body: some View {
        SidebarCompoundControlBlock {
            SidebarControlRow("Max Width") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: maxWidthBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Max Width")
                        .monospacedDigit()
                }
            }
        } secondary: {
            SidebarControlRow("Max Height") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: maxHeightBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Max Height")
                        .monospacedDigit()
                }
            }
        }
    }

    private var maxWidthBinding: Binding<Int> {
        Binding(
            get: { params.maxWidth },
            set: {
                var p = params
                p.maxWidth = $0
                onChange(p)
            }
        )
    }

    private var maxHeightBinding: Binding<Int> {
        Binding(
            get: { params.maxHeight },
            set: {
                var p = params
                p.maxHeight = $0
                onChange(p)
            }
        )
    }
}

// MARK: - AspectRatioLayerControls

struct AspectRatioLayerControls: View {
    var params: AspectRatioLayerParams
    var onChange: (AspectRatioLayerParams) -> Void

    private let presets: [(label: String, w: Int, h: Int)] = [
        ("1:1", 1, 1),
        ("4:5", 4, 5),
        ("5:4", 5, 4),
        ("3:2", 3, 2),
        ("2:3", 2, 3),
        ("16:9", 16, 9),
        ("9:16", 9, 16),
    ]

    private var isCustom: Bool {
        !presets.contains { $0.w == params.ratioWidth && $0.h == params.ratioHeight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarControlRow("Ratio") {
                Picker("Ratio", selection: ratioBinding) {
                    ForEach(presets, id: \.label) { preset in
                        Text(preset.label).tag("\(preset.w):\(preset.h)")
                    }
                    Text("Custom").tag("custom")
                }
                .labelsHidden()
            }

            if isCustom {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    SidebarControlRow("Width") {
                        TextField("W", value: Binding(
                            get: { params.ratioWidth },
                            set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: max(1, $0), ratioHeight: params.ratioHeight, offsetX: params.offsetX, offsetY: params.offsetY)) }
                        ), format: .number)
                        .simpleLayerEditorInputStyle(width: nil, accessibilityLabel: "Width")
                        .monospacedDigit()
                    }
                } secondary: {
                    SidebarControlRow("Height") {
                        TextField("H", value: Binding(
                            get: { params.ratioHeight },
                            set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: max(1, $0), offsetX: params.offsetX, offsetY: params.offsetY)) }
                        ), format: .number)
                        .simpleLayerEditorInputStyle(width: nil, accessibilityLabel: "Height")
                        .monospacedDigit()
                    }
                }
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                SidebarControlRow("Offset X") {
                    Slider(value: offsetXBinding, in: -1...1)
                        .tint(Color.accentDim)
                } trailingValue: {
                    SidebarTrailingReadoutCluster {
                        Text(String(format: "%.1f", params.offsetX))
                            .font(AppFont.mono(10))
                            .foregroundStyle(Color.text3)
                            .monospacedDigit()
                    }
                }
            } secondary: {
                SidebarControlRow("Offset Y") {
                    Slider(value: offsetYBinding, in: -1...1)
                        .tint(Color.accentDim)
                } trailingValue: {
                    SidebarTrailingReadoutCluster {
                        Text(String(format: "%.1f", params.offsetY))
                            .font(AppFont.mono(10))
                            .foregroundStyle(Color.text3)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var ratioBinding: Binding<String> {
        Binding(
            get: {
                if isCustom { return "custom" }
                return "\(params.ratioWidth):\(params.ratioHeight)"
            },
            set: { newValue in
                if newValue == "custom" { return }
                if let preset = presets.first(where: { "\($0.w):\($0.h)" == newValue }) {
                    onChange(AspectRatioLayerParams(id: params.id, ratioWidth: preset.w, ratioHeight: preset.h, offsetX: params.offsetX, offsetY: params.offsetY))
                }
            }
        )
    }

    private var offsetXBinding: Binding<Double> {
        Binding(
            get: { params.offsetX },
            set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: params.ratioHeight, offsetX: $0, offsetY: params.offsetY)) }
        )
    }

    private var offsetYBinding: Binding<Double> {
        Binding(
            get: { params.offsetY },
            set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: params.ratioHeight, offsetX: params.offsetX, offsetY: $0)) }
        )
    }
}

// MARK: - OrientationLayerControls

struct OrientationLayerControls: View {
    var params: OrientationLayerParams
    var onChange: (OrientationLayerParams) -> Void

    var body: some View {
        SidebarControlRow("Target") {
            Picker("Target", selection: targetBinding) {
                ForEach(OrientationTarget.allCases, id: \.self) { target in
                    Text(target.rawValue.capitalized).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var targetBinding: Binding<OrientationTarget> {
        Binding(
            get: { params.target },
            set: {
                var p = params
                p.target = $0
                onChange(p)
            }
        )
    }
}

// MARK: - OverlayLayerControls

struct OverlayLayerControls: View {
    var params: OverlayLayerParams
    var onChange: (OverlayLayerParams) -> Void

    @Environment(\.sidebarMetrics) private var metrics

    @State private var availableOverlays: [TextureFrameProvider.OverlayInfo] = []
    @State private var selectedKind: OverlayKind = .frame

    init(params: OverlayLayerParams, onChange: @escaping (OverlayLayerParams) -> Void) {
        self.params = params
        self.onChange = onChange
        _selectedKind = State(initialValue: params.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kindPicker

            SimpleLayerEditorDivider()

            overlayPicker

            if !filteredOverlays.isEmpty {
                SimpleLayerEditorDivider()

                overlayThumbnailStrip
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                blendModePicker
            } secondary: {
                opacityControl
            }

            SimpleLayerEditorDivider()

            openFolderButton
        }
        .onAppear(perform: loadOverlays)
        .onChange(of: params.kind) { _, newKind in
            selectedKind = newKind
        }
    }

    // MARK: - Subviews

    private var kindPicker: some View {
        SidebarFullWidthRow("Category") {
            Picker("", selection: $selectedKind) {
                Text("Frames").tag(OverlayKind.frame)
                Text("Dust").tag(OverlayKind.dust)
                Text("Light Leaks").tag(OverlayKind.lightLeak)
                Text("Wet Plate").tag(OverlayKind.wetPlate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedKind) { _, newKind in
                var p = params
                p.kind = newKind
                p.blendMode = OverlayBlendMode.defaultFor(newKind)
                if !filteredOverlays.contains(where: { $0.id == p.overlayName }) {
                    p.overlayName = ""
                }
                onChange(p)
            }
        }
    }

    private var overlayPicker: some View {
        Picker("", selection: overlayNameBinding) {
            Text("None").tag("")
            ForEach(filteredOverlays) { overlay in
                Text(overlay.displayName).tag(overlay.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("Overlay")
    }

    private var overlayThumbnailStrip: some View {
        SidebarFullWidthRow("Preview") {
            SidebarPreviewStrip(items: filteredOverlays) { overlay in
                overlayThumb(overlay)
            }
        }
    }

    private var blendModePicker: some View {
        SidebarControlRow("Blend Mode") {
            Picker("", selection: blendModeBinding) {
                ForEach(OverlayBlendMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var opacityControl: some View {
        SidebarControlRow("Opacity") {
            StyledSliderWithUnit(
                value: opacityBinding,
                range: 0...100,
                accessibilityLabel: "Opacity",
                step: 1,
                unit: "%"
            )
        }
    }

    private var openFolderButton: some View {
        SidebarFullWidthRow("Library") {
            Button {
                if let dir = TextureFrameProvider.ensureUserOverlayDirectory() {
                    NSWorkspace.shared.open(dir)
                }
            } label: {
                Label("Open Overlays Folder", systemImage: "folder")
                    .font(AppFont.controlLabel)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.text2)
        }
    }

    // MARK: - Thumbnail

    private func overlayThumb(_ overlay: TextureFrameProvider.OverlayInfo) -> some View {
        Button {
            var p = params
            p.overlayName = overlay.id
            p.kind = overlay.kind
            onChange(p)
        } label: {
            AsyncOverlayThumbnail(overlay: overlay, isSelected: params.overlayName == overlay.id)
        }
        .buttonStyle(.plain)
        .help(overlay.displayName)
    }

    // MARK: - Bindings

    private var overlayNameBinding: Binding<String> {
        Binding(
            get: { params.overlayName },
            set: { name in
                var p = params
                p.overlayName = name
                if let info = availableOverlays.first(where: { $0.id == name }) {
                    p.kind = info.kind
                }
                onChange(p)
            }
        )
    }

    private var blendModeBinding: Binding<OverlayBlendMode> {
        Binding(
            get: { params.blendMode },
            set: {
                var p = params
                p.blendMode = $0
                onChange(p)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { params.opacity },
            set: {
                var p = params
                p.opacity = $0
                onChange(p)
            }
        )
    }

    // MARK: - Data

    private var filteredOverlays: [TextureFrameProvider.OverlayInfo] {
        availableOverlays.filter { $0.kind == selectedKind }
    }

    private func loadOverlays() {
        // Load on background to avoid blocking the UI
        Task.detached {
            let overlays = TextureFrameProvider.availableOverlays()
            await MainActor.run {
                availableOverlays = overlays
            }
        }
    }
}

// MARK: - AsyncOverlayThumbnail

/// Loads overlay thumbnail asynchronously with caching — avoids blocking the main thread.
private struct AsyncOverlayThumbnail: View {
    let overlay: TextureFrameProvider.OverlayInfo
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor))

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 58, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 60, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .task(id: overlay.id) {
            guard thumbnail == nil else { return }
            let info = overlay
            let image = await Task.detached {
                TextureFrameProvider.cachedThumbnail(for: info)
            }.value
            if let cgImage = image {
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                thumbnail = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                )
            }
        }
    }
}

// MARK: - LayerFillPicker

struct LayerFillPicker: View {
    var fill: LayerFill
    var onChange: (LayerFill) -> Void

    private static let signedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarControlRow("Fill") {
                Picker("Fill", selection: fillModeBinding) {
                    Text("Solid Color").tag(0)
                    Text("Dominant Color").tag(1)
                    Text("Linear Gradient").tag(2)
                    Text("Radial Gradient").tag(3)
                }
                .labelsHidden()
            }

            if case .color(let c) = fill {
                SimpleLayerEditorDivider()

                ColorPickerWithHex("Fill Color", selection: Binding(
                    get: { Color(nsColor: NSColor(cgColor: c.cgColor) ?? .white) },
                    set: { newColor in
                        guard let hex = newColor.hexString else { return }
                        guard let codable = try? CodableColor(hex: hex) else { return }
                        onChange(.color(codable))
                    }
                ))
            }

            if let params = fill.gradientParams {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    SidebarControlRow("Saturation") {
                        Slider(value: saturationBinding(params), in: -50...50)
                            .tint(Color.accentDim)
                    } trailingValue: {
                        TextField("", value: saturationBinding(params), formatter: Self.signedFormatter)
                            .simpleLayerEditorInputStyle(width: SidebarMetrics().controlValueFieldWidth, accessibilityLabel: "Saturation")
                            .monospacedDigit()
                    }
                } secondary: {
                    SidebarControlRow("Brightness") {
                        Slider(value: lightnessBinding(params), in: -50...50)
                            .tint(Color.accentDim)
                    } trailingValue: {
                        TextField("", value: lightnessBinding(params), formatter: Self.signedFormatter)
                            .simpleLayerEditorInputStyle(width: SidebarMetrics().controlValueFieldWidth, accessibilityLabel: "Brightness")
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var fillModeBinding: Binding<Int> {
        Binding(
            get: {
                switch fill {
                case .color: return 0
                case .dominantColor: return 1
                case .gradientLinear: return 2
                case .gradientRadial: return 3
                }
            },
            set: { idx in
                // Preserve existing gradient params when switching between gradient types
                let existingParams = fill.gradientParams ?? GradientParams()
                switch idx {
                case 0: onChange(.color(.white))
                case 1: onChange(.dominantColor(existingParams))
                case 2: onChange(.gradientLinear(existingParams))
                case 3: onChange(.gradientRadial(existingParams))
                default: break
                }
            }
        )
    }

    private func saturationBinding(_ params: GradientParams) -> Binding<Double> {
        Binding(
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
        )
    }

    private func lightnessBinding(_ params: GradientParams) -> Binding<Double> {
        Binding(
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
        )
    }
}

// MARK: - CaptionLayerControls

struct CaptionLayerControls: View {
    var params: CaptionLayerParams
    var onChange: (CaptionLayerParams) -> Void

    @State private var fontSizeMode: FontSizeMode = .auto

    private enum FontSizeMode: String, CaseIterable {
        case auto = "Auto"
        case custom = "Custom"
    }

    init(params: CaptionLayerParams, onChange: @escaping (CaptionLayerParams) -> Void) {
        self.params = params
        self.onChange = onChange
        _fontSizeMode = State(initialValue: Self.fontSizeMode(for: params.fontSize))
    }

    private static let signedIntFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.allowsFloats = false
        return f
    }()

    private static let cachedMonospacedFonts: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
            .sorted()
    }()

    private var monospacedFontList: [String] {
        let current = params.fontName
        if Self.cachedMonospacedFonts.contains(current) {
            return Self.cachedMonospacedFonts
        }
        return ([current] + Self.cachedMonospacedFonts).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: captionModeIndex) {
                Text("Template").tag(0)
                Text("Custom").tag(1)
                Text("None").tag(2)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .denseControlRow("Mode")

            switch params.mode {
            case .template:
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    TextField("Template", text: captionTemplateText)
                        .font(.system(.body, design: .monospaced))
                        .denseControlRow("Template")
                } secondary: {
                    TemplateTokenBar(text: captionTemplateText)
                        .denseSupportingRow("Tokens")
                }
            case .custom:
                SimpleLayerEditorDivider()

                TextField("Caption text", text: captionCustomText)
                    .denseControlRow("Caption")
            case .none:
                EmptyView()
            }

            if captionEnabled {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    Picker("", selection: positionBinding) {
                        Text("Bottom").tag(CaptionPosition.bottom)
                        Text("Top").tag(CaptionPosition.top)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Position")
                } secondary: {
                    Picker("", selection: alignmentBinding) {
                        Text("Left").tag(CaptionAlignment.left)
                        Text("Center").tag(CaptionAlignment.center)
                        Text("Right").tag(CaptionAlignment.right)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Alignment")
                }

                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    DenseSliderControlRow(
                        title: "Offset X",
                        value: offsetXBinding,
                        range: -200...200,
                        step: 1,
                        unit: "px"
                    )
                } secondary: {
                    DenseSliderControlRow(
                        title: "Offset Y",
                        value: offsetYBinding,
                        range: -200...200,
                        step: 1,
                        unit: "px"
                    )
                }

                SimpleLayerEditorDivider()

                Picker("", selection: fontNameBinding) {
                    ForEach(monospacedFontList, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Font")

                SimpleLayerEditorDivider()

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
                .denseControlRow("Style")

                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    Picker("", selection: $fontSizeMode) {
                        ForEach(FontSizeMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .denseControlRow("Size")
                    .onChange(of: fontSizeMode) { _, newValue in
                        var p = params
                        switch newValue {
                        case .auto:
                            p.fontSize = .auto
                        case .custom:
                            if case .auto = params.fontSize {
                                p.fontSize = .fixed(24)
                            }
                        }
                        onChange(p)
                    }
                } secondary: {
                    if case .fixed(let pts) = params.fontSize {
                        DenseSliderControlRow(
                            title: "Font Size",
                            value: fontSizeBinding(pts),
                            range: 8...120,
                            step: 1,
                            unit: "pt"
                        )
                    }
                }

                SimpleLayerEditorDivider()

                Picker("", selection: fontColorModeIndex) {
                    Text("Custom").tag(0)
                    Text("Dominant").tag(1)
                    Text("Invert").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .denseControlRow("Font Color")

                if case .fixed = params.fontColorMode {
                    SimpleLayerEditorDivider()

                    ColorPickerWithHex("Color", selection: fontColorBinding)
                }

                if case .dominant(let sat, let light) = params.fontColorMode {
                    SimpleLayerEditorDivider()

                    captionColorAdjustmentSliders(saturation: sat, lightness: light) { s, l in
                        var p = params
                        p.fontColorMode = .dominant(saturationShift: s, lightnessShift: l)
                        onChange(p)
                    }
                }

                if case .dominantInverted(let sat, let light) = params.fontColorMode {
                    SimpleLayerEditorDivider()

                    captionColorAdjustmentSliders(saturation: sat, lightness: light) { s, l in
                        var p = params
                        p.fontColorMode = .dominantInverted(saturationShift: s, lightnessShift: l)
                        onChange(p)
                    }
                }
            }
        }
        .onChange(of: params.fontSize) { _, newFontSize in
            fontSizeMode = Self.fontSizeMode(for: newFontSize)
        }
    }

    private static func fontSizeMode(for fontSize: FontSize) -> FontSizeMode {
        switch fontSize {
        case .auto:
            .auto
        case .fixed:
            .custom
        }
    }

    @ViewBuilder
    private func captionColorAdjustmentSliders(saturation: Double, lightness: Double, onChange: @escaping (Double, Double) -> Void) -> some View {
        SidebarCompoundControlBlock {
            DenseSliderControlRow(
                title: "Saturation",
                value: Binding(get: { saturation }, set: { onChange($0, lightness) }),
                range: -50...50,
                step: 1
            )
        } secondary: {
            DenseSliderControlRow(
                title: "Brightness",
                value: Binding(get: { lightness }, set: { onChange(saturation, $0) }),
                range: -50...50,
                step: 1
            )
        }
    }

    // MARK: - Helpers

    private var captionEnabled: Bool {
        if case .none = params.mode { return false }
        return true
    }

    // MARK: - Bindings

    private var captionModeIndex: Binding<Int> {
        Binding(
            get: {
                switch params.mode {
                case .template: 0
                case .custom: 1
                case .none: 2
                }
            },
            set: { idx in
                var p = params
                switch idx {
                case 0:
                    if case .template = params.mode { return }
                    p.mode = .template(" - {{mon}} '{{year2}} -")
                case 1:
                    if case .custom = params.mode { return }
                    p.mode = .custom("")
                default:
                    p.mode = .none
                }
                onChange(p)
            }
        )
    }

    private var captionTemplateText: Binding<String> {
        Binding(
            get: {
                if case .template(let t) = params.mode { return t }
                return ""
            },
            set: {
                var p = params
                p.mode = .template($0)
                onChange(p)
            }
        )
    }

    private var captionCustomText: Binding<String> {
        Binding(
            get: {
                if case .custom(let s) = params.mode { return s }
                return ""
            },
            set: {
                var p = params
                p.mode = .custom($0)
                onChange(p)
            }
        )
    }

    private var positionBinding: Binding<CaptionPosition> {
        Binding(
            get: { params.position },
            set: {
                var p = params
                p.position = $0
                onChange(p)
            }
        )
    }

    private var alignmentBinding: Binding<CaptionAlignment> {
        Binding(
            get: { params.alignment },
            set: {
                var p = params
                p.alignment = $0
                onChange(p)
            }
        )
    }

    private var offsetXBinding: Binding<Double> {
        Binding(
            get: { Double(params.offsetX) },
            set: {
                var p = params
                p.offsetX = Int($0)
                onChange(p)
            }
        )
    }

    private var offsetYBinding: Binding<Double> {
        Binding(
            get: { Double(params.offsetY) },
            set: {
                var p = params
                p.offsetY = Int($0)
                onChange(p)
            }
        )
    }

    private var fontNameBinding: Binding<String> {
        Binding(
            get: { params.fontName },
            set: {
                var p = params
                p.fontName = $0
                onChange(p)
            }
        )
    }

    private func fontStyleBinding(_ trait: FontStyle) -> Binding<Bool> {
        Binding(
            get: { params.fontStyle.contains(trait) },
            set: { enabled in
                var p = params
                if enabled {
                    p.fontStyle.insert(trait)
                } else {
                    p.fontStyle.remove(trait)
                }
                onChange(p)
            }
        )
    }

    private func fontSizeBinding(_ currentPts: Int) -> Binding<Double> {
        Binding(
            get: { Double(currentPts) },
            set: {
                var p = params
                p.fontSize = .fixed(Int($0))
                onChange(p)
            }
        )
    }

    private var fontColorModeIndex: Binding<Int> {
        Binding(
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
                default: p.fontColorMode = .fixed(params.fontColor)
                }
                onChange(p)
            }
        )
    }

    private var fontColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: params.fontColor.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.fontColorMode = .fixed(c)
                onChange(p)
            }
        )
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
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            ForEach(TemplateToken.Category.allCases, id: \.rawValue) { category in
                tokenRow(category)
            }
        }
    }

    private func tokenRow(_ category: TemplateToken.Category) -> some View {
        HStack(alignment: .top, spacing: metrics.expandedBodyInset) {
            Text(category.rawValue)
                .font(AppFont.body(10))
                .foregroundStyle(Color.text3)
                .frame(width: 48, alignment: .trailing)

            SidebarChipFlow(
                items: TemplateToken.all.filter { $0.category == category },
                spacing: metrics.expandedBodyInset - 2
            ) { token in
                Button {
                    text.append(token.token)
                } label: {
                    Text(token.label)
                        .font(AppFont.controlLabel)
                        .padding(.horizontal, metrics.expandedBodyInset)
                        .padding(.vertical, 2)
                        .background(Color.surface4, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Insert \(token.token)")
            }
        }
    }
}

struct DenseSliderControlRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: LocalizedStringKey? = nil
    let step: Double
    var unit: LocalizedStringKey? = nil

    var body: some View {
        SidebarControlRow(title) {
            if let unit {
                StyledSliderWithUnit(
                    value: $value,
                    range: range,
                    accessibilityLabel: accessibilityLabel ?? title,
                    step: step,
                    unit: unit
                )
            } else {
                StyledSlider(
                    value: $value,
                    range: range,
                    accessibilityLabel: accessibilityLabel ?? title,
                    step: step
                )
            }
        }
    }
}

private struct DenseSupplementaryControlRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    @Environment(\.sidebarMetrics) private var metrics

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.controlColumnSpacing) {
            Text(title)
                .font(AppFont.body(10))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlLabelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, metrics.outerInset)
        .padding(.top, 3)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func denseControlRow(_ title: LocalizedStringKey) -> some View {
        SidebarControlRow(title) {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func denseSupportingRow(_ title: LocalizedStringKey) -> some View {
        DenseSupplementaryControlRow(title) {
            self
        }
    }
}

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
                ColorPickerWithHex("Foreground", selection: foregroundBinding(fg: fg, bg: bg))

                SimpleLayerEditorDivider()
                ColorPickerWithHex("Background", selection: backgroundBinding(fg: fg, bg: bg))
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
                        var p = params
                        switch newValue {
                        case .custom:
                            // Seed Custom with the current colours if already
                            // custom, else the classic Game Boy set as a starter.
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

                ForEach(Array(colors.enumerated()), id: \.offset) { idx, color in
                    HStack(spacing: metrics.controlColumnSpacing) {
                        ColorPickerWithHex("Colour \(idx + 1)", selection: Binding(
                            get: { Color(nsColor: NSColor(cgColor: color.cgColor) ?? .white) },
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
                        Button {
                            guard colors.count > 2 else { return }
                            var p = params
                            var next = colors
                            next.remove(at: idx)
                            p.colorMode = .palette(next)
                            onChange(p)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(colors.count <= 2)
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
        }
    }
}

// MARK: - LUTLayerControls

struct LUTLayerControls: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sidebarMetrics) private var metrics
    var params: LUTLayerParams
    var onChange: (LUTLayerParams) -> Void

    @State private var availableLUTs: [LUTInfo] = []
    @State private var thumbnailCache: [String: CGImage] = [:]
    @State private var renamingLUT: LUTInfo?
    @State private var renameText = ""

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
            lutPicker

            SimpleLayerEditorDivider()
            lutThumbnailStrip

            SimpleLayerEditorDivider()
            intensityControl

            SimpleLayerEditorDivider()
            importButtons
        }
        .task {
            loadLUTs()
            await reloadThumbnailsForSelectedPhoto()
        }
        .onChange(of: appState.selectedPhoto?.id) { _, _ in
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }
        }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }
        }
        .alert("Rename LUT", isPresented: Binding(
            get: { renamingLUT != nil },
            set: { if !$0 { renamingLUT = nil } }
        )) {
            TextField("LUT name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingLUT = nil
            }
            Button("Rename") {
                renameSelectedLUT()
            }
        } message: {
            Text("Enter a new name for this LUT.")
        }
    }

    private var lutPicker: some View {
        Picker("", selection: lutNameBinding) {
            Text("None").tag("")
            ForEach(availableLUTs) { lut in
                Text(lut.displayName).tag(lut.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("LUT")
    }

    @MainActor
    private func reloadThumbnailsForSelectedPhoto() async {
        thumbnailCache = [:]
        await generateThumbnails()
    }

    private func generateThumbnails() async {
        guard let sourceImage = await selectedPhotoThumbnail() else {
            return
        }

        let luts = availableLUTs
        for lut in luts {
            if thumbnailCache[lut.id] == nil {
                let thumb = await Task.detached(priority: .userInitiated) {
                    LUTProvider.thumbnail(for: lut, sourceImage: sourceImage, size: 48)
                }.value
                if let thumb {
                    await MainActor.run {
                        thumbnailCache[lut.id] = thumb
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lutThumbnailStrip: some View {
        if availableLUTs.isEmpty {
            SidebarFullWidthRow("Preview") {
                VStack(spacing: metrics.expandedBodyInset) {
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
                .padding(.vertical, metrics.expandedBodyInset * 2)
            }
        } else {
            SidebarFullWidthRow("Preview") {
                SidebarPreviewStrip(
                    items: availableLUTs,
                    tileWidth: 48,
                    tileHeight: nil,
                    spacing: metrics.expandedBodyInset
                ) { lut in
                    lutThumb(lut)
                }
            }
        }
    }

    private var intensityControl: some View {
        DenseSliderControlRow(
            title: "Intensity",
            value: Binding(
                get: { params.intensity * 100 },
                set: { intensityBinding.wrappedValue = $0 / 100 }
            ),
            range: 0...100,
            step: 5,
            unit: "%"
        )
    }

    private var importButtons: some View {
        SidebarFullWidthRow("Library") {
            HStack(spacing: metrics.controlColumnSpacing) {
                Button {
                    importLUT()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(AppFont.controlLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.text2)

                Button {
                    openLUTsFolder()
                } label: {
                    Label("Show Folder", systemImage: "folder")
                        .font(AppFont.controlLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.text2)
            }
        }
    }

    private func lutThumb(_ lut: LUTInfo) -> some View {
        Button {
            selectLUT(lut)
        } label: {
            VStack(spacing: 2) {
                Group {
                    if let thumb = thumbnailCache[lut.id] {
                        Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 48, height: 48)))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if appState.selectedPhoto == nil {
                        ZStack {
                            Color.surface2
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(Color.text3)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.surface2
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                        .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(params.lutFileName == lut.id ? Color.accent : Color.clear, lineWidth: 2)
                )
                Text(lut.displayName)
                    .font(.caption2)
                    .foregroundStyle(Color.text2)
                    .lineLimit(1)
                    .frame(width: 48)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if lut.category == "user" {
                Button {
                    renameText = lut.displayName
                    renamingLUT = lut
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteLUT(lut)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func selectLUT(_ lut: LUTInfo) {
        var p = params
        p.lutName = lut.displayName
        p.lutFileName = lut.id
        onChange(p)
    }

    private func loadLUTs() {
        availableLUTs = LUTProvider.availableLUTs()
    }

    private func selectedPhotoThumbnail() async -> CGImage? {
        guard let photo = appState.selectedPhoto else {
            return nil
        }

        return await ImageThumbnailLoader.loadCGThumbnail(
            from: photo.url,
            maxPixelSize: 96,
            rotation: photo.rotation
        )
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a .cube LUT file to import"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let info = try LUTProvider.importLUT(from: url)
                LUTProvider.invalidateCache()
                loadLUTs()
                Task {
                    await reloadThumbnailsForSelectedPhoto()
                }
                selectLUT(info)
            } catch {
                showImportError(error)
            }
        }
    }

    private func renameSelectedLUT() {
        guard let lut = renamingLUT else { return }

        do {
            try LUTProvider.renameUserLUT(named: lut.id, displayName: renameText)
            loadLUTs()
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }
            if params.lutFileName == lut.id,
               let refreshed = availableLUTs.first(where: { $0.id == lut.id }) {
                selectLUT(refreshed)
            }
        } catch {
            showLUTManagementError(error)
        }

        renamingLUT = nil
    }

    private func deleteLUT(_ lut: LUTInfo) {
        let alert = NSAlert()
        alert.messageText = "Remove LUT?"
        alert.informativeText = "This will remove \"\(lut.displayName)\" from your imported LUTs."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try LUTProvider.deleteUserLUT(named: lut.id)
            loadLUTs()
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }

            if params.lutFileName == lut.id {
                var p = params
                p.lutName = ""
                p.lutFileName = ""
                onChange(p)
            }
        } catch {
            showLUTManagementError(error)
        }
    }

    private func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Import Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showLUTManagementError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "LUT Update Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openLUTsFolder() {
        if let dir = LUTProvider.userLUTDirectory() {
            NSWorkspace.shared.open(dir)
        }
    }

    private var lutNameBinding: Binding<String> {
        Binding(
            get: { params.lutFileName },
            set: { newValue in
                var p = params
                p.lutFileName = newValue
                if let lut = availableLUTs.first(where: { $0.id == newValue }) {
                    p.lutName = lut.displayName
                }
                onChange(p)
            }
        )
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { params.intensity },
            set: { newValue in
                var p = params
                p.intensity = newValue
                onChange(p)
            }
        )
    }
}

// MARK: - ShaderLayerControls

struct ShaderLayerControls: View {
    var params: ShaderLayerParams
    var onChange: (ShaderLayerParams) -> Void

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

            sliderRow(
                title: "Intensity",
                value: params.intensity,
                range: 0...1,
                step: 0.05
            ) { value in
                var updated = params
                updated.intensity = value
                onChange(updated)
            }

            SimpleLayerEditorDivider()

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
            title: "Cell Size",
            value: Double(asciiParams.cellSize),
            range: expandedRange(4...24, including: Double(asciiParams.cellSize)),
            step: 1
        ) { value in
            updateASCII(asciiParams, cellSize: Int(value.rounded()))
        }

        sliderRow(
            title: "Edge Bias",
            value: asciiParams.edgeBias,
            range: expandedRange(0...1, including: asciiParams.edgeBias),
            step: 0.05
        ) { value in
            updateASCII(asciiParams, edgeBias: value)
        }

        sliderRow(
            title: "Exposure",
            value: asciiParams.exposure,
            range: expandedRange(0...5, including: asciiParams.exposure),
            step: 0.1
        ) { value in
            updateASCII(asciiParams, exposure: value)
        }

        sliderRow(
            title: "Attenuation",
            value: asciiParams.attenuation,
            range: expandedRange(0...5, including: asciiParams.attenuation),
            step: 0.1
        ) { value in
            updateASCII(asciiParams, attenuation: value)
        }

        sliderRow(
            title: "Black Level",
            value: asciiParams.blackLevel,
            range: 0...1,
            step: 0.05
        ) { value in
            updateASCII(asciiParams, blackLevel: value)
        }

        asciiCharactersControl(asciiParams)
        asciiFontControl(asciiParams)

        // Resolution toggle. Independent of character set / font — see
        // ASCIIShaderParams.highDetail for the axis split.
        SidebarControlRow("High Detail") {
            EmptyView()
        } trailingValue: {
            StyledToggle(isOn: Binding(
                get: { asciiParams.highDetail },
                set: { updateASCII(asciiParams, highDetail: $0) }
            ))
        }

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
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("Colors")

        switch asciiParams.colorMode {
        case .manual(let foreground, let background):
            ColorPickerWithHex("Foreground", selection: Binding(
                get: { Color(cgColor: foreground.cgColor) },
                set: { value in
                    guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                    updateASCII(asciiParams, colorMode: .manual(foreground: color, background: background))
                }
            ), onHexCommit: { color in
                updateASCII(asciiParams, colorMode: .manual(foreground: color, background: background))
            })

            ColorPickerWithHex("Background", selection: Binding(
                get: { Color(cgColor: background.cgColor) },
                set: { value in
                    guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                    updateASCII(asciiParams, colorMode: .manual(foreground: foreground, background: color))
                }
            ), onHexCommit: { color in
                updateASCII(asciiParams, colorMode: .manual(foreground: foreground, background: color))
            })
        case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift):
            SidebarControlRow("Flip Palette") {
                EmptyView()
            } trailingValue: {
                StyledToggle(isOn: Binding(
                    get: { flipped },
                    set: { value in
                        updateASCII(asciiParams, colorMode: .dominantTwoTone(
                            flipped: value,
                            saturationShift: saturationShift,
                            lightnessShift: lightnessShift
                        ))
                    }
                ))
            }

            sliderRow(
                title: "Saturation",
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
                title: "Brightness",
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
            ColorPickerWithHex("Background", selection: Binding(
                get: { Color(cgColor: background.cgColor) },
                set: { value in
                    guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                    updateASCII(asciiParams, colorMode: .source(background: color))
                }
            ), onHexCommit: { color in
                updateASCII(asciiParams, colorMode: .source(background: color))
            })
        case .gradient(let color1, let color2, let background):
            ColorPickerWithHex("Dark Color", selection: Binding(
                get: { Color(cgColor: color1.cgColor) },
                set: { value in
                    guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                    updateASCII(asciiParams, colorMode: .gradient(color1: color, color2: color2, background: background))
                }
            ), onHexCommit: { color in
                updateASCII(asciiParams, colorMode: .gradient(color1: color, color2: color2, background: background))
            })

            ColorPickerWithHex("Bright Color", selection: Binding(
                get: { Color(cgColor: color2.cgColor) },
                set: { value in
                    guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                    updateASCII(asciiParams, colorMode: .gradient(color1: color1, color2: color, background: background))
                }
            ), onHexCommit: { color in
                updateASCII(asciiParams, colorMode: .gradient(color1: color1, color2: color, background: background))
            })

            ColorPickerWithHex("Background", selection: Binding(
                get: { Color(cgColor: background.cgColor) },
                set: { value in
                    guard let hex = value.hexString, let color = try? CodableColor(hex: hex) else { return }
                    updateASCII(asciiParams, colorMode: .gradient(color1: color1, color2: color2, background: color))
                }
            ), onHexCommit: { color in
                updateASCII(asciiParams, colorMode: .gradient(color1: color1, color2: color2, background: color))
            })
        }

        SidebarControlRow("Invert") {
            EmptyView()
        } trailingValue: {
            StyledToggle(isOn: Binding(
                get: {
                    asciiParams.invert
                },
                set: { value in
                    updateASCII(asciiParams, invert: value)
                }
            ))
        }
    }

    /// Character-palette picker. Presets are derived from the stored string
    /// each render, so switching between layers / undoing selection stays in
    /// sync without a separate persisted preset field. Custom reveals a text
    /// field + live length indicator + mini ramp preview showing how the
    /// user's N characters spread across the atlas's 10 luminance slots.
    @ViewBuilder
    private func asciiCharactersControl(_ asciiParams: ASCIIShaderParams) -> some View {
        let selectedPreset = ASCIIPreset.matching(asciiParams.characters)
        let characterCount = (asciiParams.characters ?? "").count

        Picker("", selection: Binding<ASCIIPreset>(
            get: { selectedPreset },
            set: { newValue in
                switch newValue {
                case .default:
                    updateASCII(asciiParams, characters: .some(nil))
                case .custom:
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
        .denseControlRow("Characters")

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
            .denseControlRow("Custom")

            Text("\(characterCount) / 10")
                .font(.caption)
                .foregroundStyle(Color.text2)
                .denseSupportingRow("Length")

            asciiRampPreview(for: asciiParams.characters ?? "")
                .denseSupportingRow("Preview")
        }
    }

    /// Font override for runtime-rasterised ASCII atlases. "System Default"
    /// (nil `fontName`) preserves the baked PNG path when `characters` is
    /// also nil, or picks Menlo for custom palettes. Any other selection
    /// routes through `ASCIIAtlasGenerator` with the chosen PostScript name,
    /// rasterising the current palette in that face. The font list comes
    /// from `NSFontManager.availableFontFamilies` unfiltered — proportional
    /// faces render fine at the 8×8 cell size, they just don't look like a
    /// terminal ramp, which is the user's judgement to make.
    @ViewBuilder
    private func asciiFontControl(_ asciiParams: ASCIIShaderParams) -> some View {
        let families = Self.systemFontFamilies
        Picker("", selection: Binding<String>(
            get: { asciiParams.fontName ?? "" },
            set: { newValue in
                updateASCII(asciiParams, fontName: .some(newValue.isEmpty ? nil : newValue))
            }
        )) {
            Text("System Default").tag("")
            Divider()
            ForEach(families, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("Font")
    }

    private static let systemFontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

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
                .frame(width: 20, height: 20)
                .overlay(Rectangle().stroke(Color.text2.opacity(0.3), lineWidth: 0.5))
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
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("Direction")

        // Span criterion. Luminance is the classic Framer behaviour; the four
        // Kim Asendorf cases come from the original 2010 ASDF Pixel Sort
        // Processing sketch — each picks a different kind of "keep sorting"
        // predicate so the sorted streaks emerge from different regions of
        // the image. Previously shipping in the data model + shader but
        // hidden from the UI.
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
        .labelsHidden()
        .denseControlRow("Span Mode")

        // Sort criterion — orthogonal to span mode. Decides what value
        // pixels are RANKED by inside a span: Luminance (classic Rec.601),
        // Brightness (max(r,g,b), preserves saturated colours), or Hue
        // (HSV angle, rainbow-streak effect).
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
        .labelsHidden()
        .denseControlRow("Sort By")

        sliderRow(
            title: "Threshold",
            value: pixelSortParams.threshold,
            range: expandedRange(0...1, including: pixelSortParams.threshold),
            step: 0.05
        ) { value in
            var updated = pixelSortParams
            updated.threshold = value
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            title: "Span",
            value: Double(pixelSortParams.span),
            range: expandedRange(4...256, including: Double(pixelSortParams.span)),
            step: 1
        ) { value in
            var updated = pixelSortParams
            updated.span = Int(value.rounded())
            onChange(params.withParams(.pixelSort(updated)))
        }
        // Per-line threshold jitter: each row/column/diagonal gets a
        // deterministic hash of its line coordinate modulating the
        // threshold by up to ±25% (at randomness=1). Breaks up the
        // mechanical "every row the same length" look without making the
        // effect non-deterministic between renders.
        sliderRow(
            title: "Randomness",
            value: pixelSortParams.randomness,
            range: 0...1,
            step: 0.05
        ) { value in
            var updated = pixelSortParams; updated.randomness = value
            onChange(params.withParams(.pixelSort(updated)))
        }
        sliderRow(
            title: "Amount",
            value: pixelSortParams.amount,
            range: expandedRange(0...1, including: pixelSortParams.amount),
            step: 0.05
        ) { value in
            var updated = pixelSortParams
            updated.amount = value
            onChange(params.withParams(.pixelSort(updated)))
        }
        // Flip sort direction — sorts descending by luminance (bright at
        // start of span) instead of ascending.
        SidebarControlRow("Reverse") {
            EmptyView()
        } trailingValue: {
            StyledToggle(isOn: Binding(
                get: { pixelSortParams.reverse },
                set: { value in
                    var updated = pixelSortParams; updated.reverse = value
                    onChange(params.withParams(.pixelSort(updated)))
                }
            ))
        }
    }

    @ViewBuilder
    private func crtControls(_ crtParams: CRTShaderParams) -> some View {
        sliderRow(
            title: "Curvature",
            value: crtParams.curvature,
            range: expandedRange(1...10, including: crtParams.curvature),
            step: 0.5
        ) { value in
            var updated = crtParams; updated.curvature = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            title: "Line Size",
            value: Double(crtParams.lineSize),
            range: 0...4,
            step: 1
        ) { value in
            var updated = crtParams; updated.lineSize = Int(value.rounded())
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            title: "Line Strength",
            value: crtParams.lineStrength,
            range: expandedRange(0...5, including: crtParams.lineStrength),
            step: 0.1
        ) { value in
            var updated = crtParams; updated.lineStrength = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            title: "Brightness",
            value: crtParams.brightness,
            range: expandedRange(-1...1, including: crtParams.brightness),
            step: 0.05
        ) { value in
            var updated = crtParams; updated.brightness = value
            onChange(params.withParams(.crt(updated)))
        }
        sliderRow(
            title: "Vignette",
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
            title: "Dot Size",
            value: halftoneParams.dotSize,
            range: expandedRange(0.1...3, including: halftoneParams.dotSize),
            step: 0.1
        ) { value in
            var updated = halftoneParams; updated.dotSize = value
            onChange(params.withParams(.halftone(updated)))
        }
        sliderRow(
            title: "Contrast",
            value: halftoneParams.contrast,
            range: expandedRange(0.1...3, including: halftoneParams.contrast),
            step: 0.1
        ) { value in
            var updated = halftoneParams; updated.contrast = value
            onChange(params.withParams(.halftone(updated)))
        }
        SidebarControlRow("Monochrome") {
            EmptyView()
        } trailingValue: {
            StyledToggle(isOn: Binding(
                get: { halftoneParams.monochrome },
                set: { value in
                    var updated = halftoneParams; updated.monochrome = value
                    onChange(params.withParams(.halftone(updated)))
                }
            ))
        }
    }

    @ViewBuilder
    private func kuwaharaControls(_ kuwaharaParams: KuwaharaShaderParams) -> some View {
        sliderRow(
            title: "Kernel Size",
            value: Double(kuwaharaParams.kernelSize),
            range: expandedRange(1...15, including: Double(kuwaharaParams.kernelSize)),
            step: 1
        ) { value in
            var updated = kuwaharaParams; updated.kernelSize = Int(value.rounded())
            onChange(params.withParams(.kuwahara(updated)))
        }
        sliderRow(
            title: "Softness",
            value: kuwaharaParams.softness,
            range: expandedRange(0...1, including: kuwaharaParams.softness),
            step: 0.05
        ) { value in
            var updated = kuwaharaParams; updated.softness = value
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
        onSet: @escaping @MainActor @Sendable (String, Double) -> Void
    ) -> some View {
        ForEach(rows, id: \.0) { row in
            sliderRow(
                title: row.0,
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
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        onSet: @escaping @MainActor @Sendable (Double) -> Void
    ) -> some View {
        DenseSliderControlRow(
            title: LocalizedStringKey(title),
            value: Binding(get: { value }, set: onSet),
            range: range,
            step: step
        )
    }
}

// MARK: - Color Helper

extension Color {
    var hexString: String? {
        // Resolve to a concrete RGB NSColor — handles catalog, pattern, and named colors
        let nsColor: NSColor
        if let resolved = NSColor(self).usingColorSpace(.sRGB) {
            nsColor = resolved
        } else if let resolved = NSColor(self).usingColorSpace(.deviceRGB) {
            nsColor = resolved
        } else {
            return nil
        }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X",
                      max(0, min(255, r)),
                      max(0, min(255, g)),
                      max(0, min(255, b)))
    }
}
