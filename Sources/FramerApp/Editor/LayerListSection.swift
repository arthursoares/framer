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
        Section {
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                VStack(spacing: 0) {
                    // Drop indicator line above this row
                    if dropTargetIndex == index {
                        dropIndicator
                    }

                    LayerRow(
                        layer: binding(for: index),
                        onDelete: { removeLayer(at: index) },
                        onMoveUp: index > 0 ? { moveLayer(from: index, to: index - 1) } : nil,
                        onMoveDown: index < layers.count - 1 ? { moveLayer(from: index, to: index + 1) } : nil
                    )
                    .opacity(draggingLayerID == layer.id ? 0.3 : 1.0)
                    .draggable(layer.id.uuidString) {
                        Label(layer.label, systemImage: layer.iconName)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.surface2, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accent.opacity(0.3), lineWidth: 1))
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

                    // Drop indicator after last row
                    if index == layers.count - 1 && dropTargetIndex == layers.count {
                        dropIndicator
                    }
                }
            }

            addLayerMenu
        } header: {
            Text("LAYERS (\(layers.count))")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)
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
            Button {
                addLayer(.shader(ShaderLayerParams()))
            } label: {
                Label("Shader", systemImage: "sparkles.rectangle.stack")
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

    private func binding(for index: Int) -> Binding<CompositionLayer> {
        Binding(
            get: { layers[index] },
            set: { layers[index] = $0 }
        )
    }
}

/// Proxy target for UndoManager since it requires NSObject.
@MainActor
private final class UndoProxy: NSObject, Sendable {
    static let shared = UndoProxy()
}

// MARK: - LayerRow

struct LayerRow: View {
    @Binding var layer: CompositionLayer
    let onDelete: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var isHoveringVisibilityToggle = false
    @State private var isHoveringDelete = false

    var body: some View {
        VStack(spacing: 0) {
            // Tappable header row
            HStack(spacing: 6) {
                // Disclosure chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.text3)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 16)

                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.text3)
                    .frame(width: 20)
                    .opacity(0.6)

                Image(systemName: layer.iconName)
                    .foregroundStyle(Color.text2)
                    .frame(width: 20)

                Text(layer.label)
                    .font(AppFont.layerName)
                    .foregroundStyle(layer.isEnabled ? Color.text0 : Color.text2)

                Spacer()

                Text(layerSummary)
                    .font(AppFont.badgeSummary)
                    .foregroundStyle(Color.text2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.surface4, in: Capsule())

                Button {
                    layer.isEnabled.toggle()
                } label: {
                    Image(systemName: layer.isEnabled ? "eye" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(isHoveringVisibilityToggle ? Color.text1 : (layer.isEnabled ? Color.text2 : Color.text3))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringVisibilityToggle = $0 }
                .accessibilityLabel(layer.isEnabled ? "Disable layer" : "Enable layer")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(isHoveringDelete ? Color.error : Color.text3)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringDelete = $0 }
                .opacity(isHovering ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .accessibilityLabel("Delete layer")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .onHover { isHovering = $0 }

            // Lazy controls — only built when expanded
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    layerControls
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .padding(.leading, 20)
                .padding(.trailing, 4)
                .foregroundStyle(Color.text1)
                .tint(Color.accent)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(isExpanded ? Color.surface2 : (isHovering ? Color.surface2.opacity(0.5) : .clear))
        )
        .opacity(layer.isEnabled ? 1.0 : 0.65)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(isExpanded ? Color.borderDefault : (isHovering ? Color.borderDefault : .clear), lineWidth: 1)
        )
        .contextMenu {
            if let onMoveUp {
                Button { onMoveUp() } label: {
                    Label("Move Up", systemImage: "chevron.up")
                }
            }
            if let onMoveDown {
                Button { onMoveDown() } label: {
                    Label("Move Down", systemImage: "chevron.down")
                }
            }
            Divider()
            Button {
                layer.isEnabled.toggle()
            } label: {
                Label(layer.isEnabled ? "Disable Layer" : "Enable Layer",
                      systemImage: layer.isEnabled ? "eye.slash" : "eye")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Layer", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var layerControls: some View {
        switch layer {
        case .border(let params):
            BorderLayerControls(params: params) { layer = .border($0) }
        case .padding(let params):
            PaddingLayerControls(params: params) { layer = .padding($0) }
        case .canvas(let params):
            CanvasLayerControls(params: params) { layer = .canvas($0) }
        case .resize(let params):
            ResizeLayerControls(params: params) { layer = .resize($0) }
        case .overlay(let params):
            OverlayLayerControls(params: params) { layer = .overlay($0) }
        case .orientation(let params):
            OrientationLayerControls(params: params) { layer = .orientation($0) }
        case .caption(let params):
            CaptionLayerControls(params: params) { layer = .caption($0) }
        case .dither(let params):
            DitherLayerControls(params: params) { layer = .dither($0) }
        case .aspectRatio(let params):
            AspectRatioLayerControls(params: params) { layer = .aspectRatio($0) }
        case .lut(let params):
            LUTLayerControls(params: params) { layer = .lut($0) }
        case .shader(let params):
            ShaderLayerControls(params: params) { layer = .shader($0) }
        case .gpuEffect(let params):
            GPUEffectLayerControls(params: params) { layer = .gpuEffect($0) }
        }
    }

    private var layerSummary: String {
        if !layer.isEnabled {
            return "Disabled"
        }
        switch layer {
        case .border(let p):
            switch p.thickness {
            case .pixels(let px): return "\(px)px"
            case .percent(let pct): return "\(Int(pct))%"
            }
        case .padding(let p):
            return "\(p.thickness)px"
        case .canvas(let p):
            return "\(p.width)x\(p.height)"
        case .resize(let p):
            return "max \(p.maxWidth)x\(p.maxHeight)"
        case .overlay(let p):
            if p.overlayName.isEmpty { return "None" }
            return "\(p.kind.label) \(Int(p.opacity))%"
        case .orientation(let p):
            return p.target.rawValue.capitalized
        case .caption(let p):
            switch p.mode {
            case .template: return "Template"
            case .custom: return "Custom"
            case .none: return "Off"
            }
        case .dither(let p):
            return p.algorithm.label
        case .aspectRatio(let p):
            return "\(p.ratioWidth):\(p.ratioHeight)"
        case .lut(let p):
            return p.lutName.isEmpty ? "None" : p.lutName
        case .shader(let p):
            return p.style.label
        case .gpuEffect(let p):
            return p.kind.label
        }
    }
}

struct GPUEffectLayerControls: View {
    var params: GPUEffectLayerParams
    var onChange: (GPUEffectLayerParams) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Per-variant layers (Option B of the bucket-UI refactor): each
            // GPU-effect variant is a first-class entry in the layer-add
            // menu, so the kind is fixed at creation. Show it here as a
            // read-only label so users know which layer they're editing
            // without offering mid-flight variant switching (which would
            // require re-picking every parameter for the new kind).
            HStack {
                Label(params.kind.label, systemImage: params.kind.menuIcon)
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text1)
                Spacer()
            }

            // Global control blocks are gated by GPUEffectKind capability flags.
            // Each variant's shader only reads a subset of the shared
            // common/geometry/color uniforms — showing sliders the shader
            // ignores felt "unwired" to the user, per the parameter matrix at
            // docs/gpu-effects-parameter-matrix.md. We only render each group
            // when the current kind actually consumes it.

            if params.kind.usesGeometry {
                HStack {
                    Text("Scale")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    Slider(value: scaleBinding, in: 0.5...2.0)
                    Text(String(format: "%.2f", scaleBinding.wrappedValue))
                        .monospacedDigit()
                        .frame(width: 44)
                }

                HStack {
                    Text("Spacing")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    Slider(value: spacingBinding, in: 1...8)
                    Text(String(format: "%.1f", spacingBinding.wrappedValue))
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            if params.kind.usesColorModeAndFgBg {
                Picker("Color Mode", selection: colorModeBinding) {
                    Text("Source").tag(GPUEffectColorMode.source)
                    Text("FG/BG").tag(GPUEffectColorMode.foregroundBackground)
                    Text("Mono").tag(GPUEffectColorMode.monochrome)
                    Text("Palette").tag(GPUEffectColorMode.palette)
                }
                .pickerStyle(.menu)
            }

            if params.kind.usesBackgroundIntensity || params.kind.usesColorModeAndFgBg {
                HStack {
                    Text("Background")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    Slider(value: backgroundIntensityBinding, in: 0...1)
                    Text(String(format: "%.2f", backgroundIntensityBinding.wrappedValue))
                        .monospacedDigit()
                        .frame(width: 44)
                }
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
                Picker("Character Set", selection: characterSetBinding) {
                    Text("ASCII").tag(GPUEffectCharacterSet.classicASCII)
                    Text("Blocks").tag(GPUEffectCharacterSet.blocks)
                    Text("Binary").tag(GPUEffectCharacterSet.binary)
                    Text("Dense").tag(GPUEffectCharacterSet.dense)
                }
                .pickerStyle(.menu)

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
                Picker("Dot Shape", selection: dotShapeBinding) {
                    Text("Circle").tag(DotShape.circle)
                    Text("Square").tag(DotShape.square)
                    Text("Diamond").tag(DotShape.diamond)
                }
                .pickerStyle(.menu)

                Picker("Grid", selection: dotGridBinding) {
                    Text("Square").tag(DotGridType.square)
                    Text("Hex").tag(DotGridType.hex)
                }
                .pickerStyle(.menu)

                adjustmentSlider(label: "Intensity", binding: textCellBinding(\.intensity), range: 0...1)
                Toggle("Invert", isOn: textInvertBinding)

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
                Picker("Style", selection: blockStyleBinding) {
                    Text("Solid").tag(BlockStyle.solid)
                    Text("Outlined").tag(BlockStyle.outlined)
                }
                .pickerStyle(.menu)

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
                adjustmentSlider(label: "Threshold", binding: matrixBinding(\.threshold), range: 0...1)

                Picker("Direction", selection: matrixDirectionBinding) {
                    Text("Down").tag(TextCellFlowDirection.down)
                    Text("Up").tag(TextCellFlowDirection.up)
                    Text("Left").tag(TextCellFlowDirection.left)
                    Text("Right").tag(TextCellFlowDirection.right)
                }
                .pickerStyle(.menu)

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

            if case .glitch(let common, let geometry, let color, let payload) = params.params,
               params.kind == .pixelSort {
                Picker("Direction", selection: glitchDirectionBinding) {
                    Text("Horizontal").tag(GlitchDirection.horizontal)
                    Text("Vertical").tag(GlitchDirection.vertical)
                }
                .pickerStyle(.menu)

                Picker("Sort Mode", selection: sortModeBinding) {
                    Text("Brightness").tag(PixelSortMode.brightness)
                    Text("Luminance").tag(PixelSortMode.luminance)
                    Text("Hue").tag(PixelSortMode.hue)
                }
                .pickerStyle(.menu)

                adjustmentSlider(label: "Streak", binding: glitchBinding(\.streakLength), range: 0...1)
                adjustmentSlider(label: "Random", binding: glitchBinding(\.randomness), range: 0...1)
                Toggle("Reverse", isOn: reverseBinding)
            }

            if case .glitch(_, _, _, _) = params.params,
               params.kind == .vhs {
                adjustmentSlider(label: "Distortion", binding: glitchBinding(\.distortion), range: 0...1)
                adjustmentSlider(label: "Color Bleed", binding: glitchBinding(\.colorBleed), range: 0...1)
                adjustmentSlider(label: "Scanlines", binding: glitchBinding(\.scanlines), range: 0...1)
                adjustmentSlider(label: "Tracking", binding: glitchBinding(\.trackingError), range: 0...1)
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .waveLines {
                // Line Strength drives the shader's threshold shaping — primary
                // brightness knob, was missing from UI before.
                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Amplitude", binding: edgeFieldBinding(\.amplitude), range: 0...1)
                adjustmentSlider(label: "Frequency", binding: edgeFieldBinding(\.frequency), range: 0.1...4)
                adjustmentSlider(label: "Thickness", binding: edgeFieldBinding(\.thickness), range: 0.05...1)

                Picker("Direction", selection: edgeDirectionBinding) {
                    Text("Horizontal").tag(EdgeFieldDirection.horizontal)
                    Text("Vertical").tag(EdgeFieldDirection.vertical)
                }
                .pickerStyle(.menu)
                // Line Count multiplies the wave-band frequency: the shader
                // computes countFactor = max(1, lineCount/spacing) and
                // multiplies `frequency` by it. Range 1..40 covers from "no
                // boost" to "very dense bands" at typical spacing values.
                adjustmentSlider(label: "Line Count", binding: edgeFieldBinding(\.lineCount), range: 1...40)
                // Animate stays hidden — no time uniform yet.
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .noiseField {
                // Line Strength gates the noise contribution (shader:
                // `noise * u.lineStrength + fieldWeight * 0.3`). Field Intensity
                // biases the baseline level. Both were missing from UI.
                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Field Intensity", binding: edgeFieldBinding(\.fieldIntensity), range: 0...1)
                adjustmentSlider(label: "Octaves", binding: noiseOctavesBinding, range: 1...6)
                adjustmentSlider(label: "Scale", binding: edgeFieldBinding(\.amplitude), range: 0.1...1)
                Picker("Noise Type", selection: noiseTypeBinding) {
                    Text("Value (IGN)").tag(NoiseFieldType.value)
                    Text("Simplex").tag(NoiseFieldType.simplex)
                    Text("Cellular").tag(NoiseFieldType.cellular)
                }
                .pickerStyle(.menu)
                Toggle("Invert", isOn: edgeInvertBinding)
                // Speed + Animate stay hidden (no time uniform yet).
                // Distort Only stays hidden (shader generates standalone,
                // doesn't distort source UVs).
            }

            if case .edgeField(let common, let geometry, let color, let payload) = params.params,
               params.kind == .edgeDetection {
                Picker("Algorithm", selection: edgeAlgorithmBinding) {
                    Text("Sobel").tag(EdgeAlgorithm.sobel)
                    Text("Laplacian").tag(EdgeAlgorithm.laplacian)
                }
                .pickerStyle(.menu)

                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Threshold", binding: edgeThresholdBinding, range: 0...1)
                adjustmentSlider(label: "Line Width", binding: edgeFieldBinding(\.thickness), range: 0.05...1)
                Toggle("Invert", isOn: edgeInvertBinding)

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
                Picker("Fill Mode", selection: contourFillModeBinding) {
                    Text("Lines").tag(ContourFillMode.linesOnly)
                    Text("Bands").tag(ContourFillMode.filledBands)
                }
                .pickerStyle(.menu)

                adjustmentSlider(label: "Line Strength", binding: edgeFieldBinding(\.lineStrength), range: 0...1)
                adjustmentSlider(label: "Field Intensity", binding: edgeFieldBinding(\.fieldIntensity), range: 0.01...1)
                adjustmentSlider(label: "Levels", binding: contourLevelsBinding, range: 2...24)
                adjustmentSlider(label: "Line Width", binding: edgeFieldBinding(\.thickness), range: 0.05...1)
                Toggle("Invert", isOn: edgeInvertBinding)

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
                Toggle("Randomize", isOn: voronoiRandomizeBinding)

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
                    Picker("Shape", selection: halftoneShapeBinding) {
                        Text("Circle").tag(HalftoneShape.circle)
                        Text("Square").tag(HalftoneShape.square)
                        Text("Diamond").tag(HalftoneShape.diamond)
                    }
                    .pickerStyle(.menu)

                    adjustmentSlider(label: "Angle", binding: halftoneAngleBinding, range: 0...90)

                    Toggle("Invert", isOn: invertBinding)
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
                    Toggle("Invert", isOn: invertBinding)
                }

                if params.kind == .threshold {
                    // Core cutoff — shader decides ink vs paper by `quantized < u.threshold`.
                    // Not exposed before so users were stuck at the default.
                    adjustmentSlider(label: "Threshold", binding: printSamplingBinding(\.threshold), range: 0...1)
                    adjustmentSlider(label: "Levels", binding: thresholdLevelsBinding, range: 2...8)
                    Toggle("Dither", isOn: thresholdDitherBinding)
                    Toggle("Invert", isOn: invertBinding)
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
        HStack {
            Text(label)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            Slider(value: binding, in: range)
            Text(String(format: "%.2f", binding.wrappedValue))
                .monospacedDigit()
                .frame(width: 44)
        }
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

struct BorderLayerControls: View {
    var params: BorderLayerParams
    var onChange: (BorderLayerParams) -> Void

    @State private var thicknessMode: ThicknessMode = .pixels

    private enum ThicknessMode: String, CaseIterable {
        case pixels = "px"
        case percent = "%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Thickness")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                Picker("", selection: $thicknessMode) {
                    ForEach(ThicknessMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .labelsHidden()
            }

            HStack {
                Slider(value: thicknessValue, in: thicknessRange)
                TextField("", value: thicknessValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(thicknessMode.rawValue)
                    .foregroundStyle(Color.text2)
                    .frame(width: 20)
            }
        }

        ColorPickerWithHex("Color", selection: colorBinding)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Thickness")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            HStack {
                Slider(value: thicknessBinding, in: 0...400)
                TextField("", value: thicknessBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("px")
                    .foregroundStyle(Color.text2)
                    .frame(width: 20)
            }
        }

        LayerFillPicker(fill: params.fill) { newFill in
            var p = params
            p.fill = newFill
            onChange(p)
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
        presetPicker

        Picker("Size Mode", selection: $sizeMode) {
            ForEach(SizeMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        if sizeMode == .pixels {
            pixelFields
        } else {
            physicalFields
        }

        pixelSummary

        LayerFillPicker(fill: params.fill) { newFill in
            var p = params
            p.fill = newFill
            onChange(p)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Width")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                HStack(spacing: 4) {
                    TextField("", value: widthBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                    Text("px").foregroundStyle(Color.text2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Height")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                HStack(spacing: 4) {
                    TextField("", value: heightBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                    Text("px").foregroundStyle(Color.text2)
                }
            }
        }
    }

    private var physicalFields: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Unit", selection: $physicalUnit) {
                    ForEach(PhysicalUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .onChange(of: physicalUnit) { oldUnit, newUnit in
                    convertUnit(from: oldUnit, to: newUnit)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("DPI")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    TextField("", value: $dpi, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .onChange(of: dpi) { _, _ in syncPhysicalToPixels() }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    HStack(spacing: 4) {
                        TextField("", value: $widthPhysical, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .onChange(of: widthPhysical) { _, _ in syncPhysicalToPixels() }
                        Text(physicalUnit.rawValue).foregroundStyle(Color.text2)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    HStack(spacing: 4) {
                        TextField("", value: $heightPhysical, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .onChange(of: heightPhysical) { _, _ in syncPhysicalToPixels() }
                        Text(physicalUnit.rawValue).foregroundStyle(Color.text2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pixelSummary: some View {
        if sizeMode == .physical {
            HStack {
                Spacer()
                Text("\(params.width) x \(params.height) px")
                    .font(AppFont.mono(10))
                    .foregroundStyle(Color.text3)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Max Width")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                TextField("", value: maxWidthBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Max Height")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                TextField("", value: maxHeightBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Ratio")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            Picker("", selection: ratioBinding) {
                ForEach(presets, id: \.label) { preset in
                    Text(preset.label).tag("\(preset.w):\(preset.h)")
                }
                Text("Custom").tag("custom")
            }
            .labelsHidden()
        }

        if isCustom {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    TextField("W", value: Binding(
                        get: { params.ratioWidth },
                        set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: max(1, $0), ratioHeight: params.ratioHeight, offsetX: params.offsetX, offsetY: params.offsetY)) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
                Text(":")
                    .foregroundStyle(Color.text3)
                    .padding(.top, 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    TextField("H", value: Binding(
                        get: { params.ratioHeight },
                        set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: max(1, $0), offsetX: params.offsetX, offsetY: params.offsetY)) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Offset X")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            HStack {
                Slider(value: offsetXBinding, in: -1...1)
                Text(String(format: "%.1f", params.offsetX))
                    .font(AppFont.mono(10))
                    .monospacedDigit()
                    .frame(width: 30)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Offset Y")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            HStack {
                Slider(value: offsetYBinding, in: -1...1)
                Text(String(format: "%.1f", params.offsetY))
                    .font(AppFont.mono(10))
                    .monospacedDigit()
                    .frame(width: 30)
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
        Picker("Target", selection: targetBinding) {
            ForEach(OrientationTarget.allCases, id: \.self) { target in
                Text(target.rawValue.capitalized).tag(target)
            }
        }
        .pickerStyle(.segmented)
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

    @State private var availableOverlays: [TextureFrameProvider.OverlayInfo] = []
    @State private var selectedKind: OverlayKind = .frame

    var body: some View {
        kindPicker
        overlayPicker
        overlayThumbnailStrip
        blendModePicker
        opacityControl
        openFolderButton
    }

    // MARK: - Subviews

    private var kindPicker: some View {
        Picker("Category", selection: $selectedKind) {
            Text("Frames").tag(OverlayKind.frame)
            Text("Dust").tag(OverlayKind.dust)
            Text("Light Leaks").tag(OverlayKind.lightLeak)
            Text("Wet Plate").tag(OverlayKind.wetPlate)
        }
        .pickerStyle(.segmented)
        .onAppear {
            selectedKind = params.kind
            loadOverlays()
        }
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

    private var overlayPicker: some View {
        Picker("Overlay", selection: overlayNameBinding) {
            Text("None").tag("")
            ForEach(filteredOverlays) { overlay in
                Text(overlay.displayName).tag(overlay.id)
            }
        }
    }

    @ViewBuilder
    private var overlayThumbnailStrip: some View {
        if !filteredOverlays.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filteredOverlays) { overlay in
                        overlayThumb(overlay)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var blendModePicker: some View {
        Picker("Blend Mode", selection: blendModeBinding) {
            ForEach(OverlayBlendMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
    }

    private var opacityControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Opacity")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            HStack {
                Slider(value: opacityBinding, in: 0...100)
                TextField("", value: opacityBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("%")
                    .foregroundStyle(Color.text2)
                    .frame(width: 20)
            }
        }
    }

    private var openFolderButton: some View {
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
        Picker("Fill", selection: fillModeBinding) {
            Text("Solid Color").tag(0)
            Text("Dominant Color").tag(1)
            Text("Linear Gradient").tag(2)
            Text("Radial Gradient").tag(3)
        }

        if case .color(let c) = fill {
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Saturation")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                HStack {
                    Slider(value: saturationBinding(params), in: -50...50)
                    TextField("", value: saturationBinding(params), formatter: Self.signedFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                HStack {
                    Slider(value: lightnessBinding(params), in: -50...50)
                    TextField("", value: lightnessBinding(params), formatter: Self.signedFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
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
        // Caption mode
        Picker("Mode", selection: captionModeIndex) {
            Text("Template").tag(0)
            Text("Custom").tag(1)
            Text("None").tag(2)
        }
        .pickerStyle(.segmented)

        switch params.mode {
        case .template:
            TextField("Template", text: captionTemplateText)
                .font(.system(.body, design: .monospaced))
            TemplateTokenBar(text: captionTemplateText)
        case .custom:
            TextField("Caption text", text: captionCustomText)
        case .none:
            EmptyView()
        }

        if captionEnabled {
            // Position
            Picker("Position", selection: positionBinding) {
                Text("Bottom").tag(CaptionPosition.bottom)
                Text("Top").tag(CaptionPosition.top)
            }
            .pickerStyle(.segmented)

            // Alignment
            Picker("Alignment", selection: alignmentBinding) {
                Text("Left").tag(CaptionAlignment.left)
                Text("Center").tag(CaptionAlignment.center)
                Text("Right").tag(CaptionAlignment.right)
            }
            .pickerStyle(.segmented)

            // Offset X
            VStack(alignment: .leading, spacing: 4) {
                Text("Offset X")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                HStack {
                    Slider(value: offsetXBinding, in: -200...200)
                    TextField("", value: offsetXBinding, formatter: Self.signedIntFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text("px")
                        .foregroundStyle(Color.text2)
                        .frame(width: 20)
                }
            }

            // Offset Y
            VStack(alignment: .leading, spacing: 4) {
                Text("Offset Y")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                HStack {
                    Slider(value: offsetYBinding, in: -200...200)
                    TextField("", value: offsetYBinding, formatter: Self.signedIntFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text("px")
                        .foregroundStyle(Color.text2)
                        .frame(width: 20)
                }
            }

            // Font
            Picker("Font", selection: fontNameBinding) {
                ForEach(monospacedFontList, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            // Style toggles
            HStack(spacing: 8) {
                Text("Style")
                Spacer()
                Toggle(isOn: fontStyleBinding(.bold)) {
                    Text("B").bold()
                }
                .toggleStyle(.button)

                Toggle(isOn: fontStyleBinding(.italic)) {
                    Text("I").italic()
                }
                .toggleStyle(.button)
            }

            // Font size
            Picker("Size", selection: $fontSizeMode) {
                ForEach(FontSizeMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onAppear {
                switch params.fontSize {
                case .auto: fontSizeMode = .auto
                case .fixed: fontSizeMode = .custom
                }
            }
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

            if case .fixed(let pts) = params.fontSize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font Size")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    HStack {
                        Slider(value: fontSizeBinding(pts), in: 8...120)
                        TextField("", value: fontSizeBinding(pts), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text("pt")
                            .foregroundStyle(Color.text2)
                            .frame(width: 20)
                    }
                }
            }

            // Font color mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Font Color")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Picker("", selection: fontColorModeIndex) {
                    Text("Custom").tag(0)
                    Text("Dominant").tag(1)
                    Text("Invert").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if case .fixed = params.fontColorMode {
                ColorPickerWithHex("Color", selection: fontColorBinding)
            }

            if case .dominant(let sat, let light) = params.fontColorMode {
                captionColorAdjustmentSliders(saturation: sat, lightness: light) { s, l in
                    var p = params; p.fontColorMode = .dominant(saturationShift: s, lightnessShift: l); onChange(p)
                }
            }
            if case .dominantInverted(let sat, let light) = params.fontColorMode {
                captionColorAdjustmentSliders(saturation: sat, lightness: light) { s, l in
                    var p = params; p.fontColorMode = .dominantInverted(saturationShift: s, lightnessShift: l); onChange(p)
                }
            }
        }
    }

    @ViewBuilder
    private func captionColorAdjustmentSliders(saturation: Double, lightness: Double, onChange: @escaping (Double, Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saturation")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            HStack {
                Slider(value: Binding(get: { saturation }, set: { onChange($0, lightness) }), in: -50...50)
                TextField("", value: Binding(get: { saturation }, set: { onChange($0, lightness) }), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Brightness")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            HStack {
                Slider(value: Binding(get: { lightness }, set: { onChange(saturation, $0) }), in: -50...50)
                TextField("", value: Binding(get: { lightness }, set: { onChange(saturation, $0) }), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
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
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TemplateToken.Category.allCases, id: \.rawValue) { category in
                tokenRow(category)
            }
        }
    }

    private func tokenRow(_ category: TemplateToken.Category) -> some View {
        HStack(spacing: 4) {
            Text(category.rawValue)
                .font(AppFont.body(10))
                .foregroundStyle(Color.text3)
                .frame(width: 48, alignment: .trailing)

            FlowLayout(spacing: 4) {
                ForEach(TemplateToken.all.filter { $0.category == category }) { token in
                    Button {
                        text.append(token.token)
                    } label: {
                        Text(token.label)
                            .font(AppFont.controlLabel)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.surface4, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Insert \(token.token)")
                }
            }
        }
    }
}

/// Simple horizontal flow layout for wrapping token chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), origins)
    }
}

// MARK: - DitherLayerControls

struct DitherLayerControls: View {
    var params: DitherLayerParams
    var onChange: (DitherLayerParams) -> Void

    var body: some View {
        Picker("Algorithm", selection: algorithmBinding) {
            ForEach(DitherAlgorithm.allCases, id: \.self) { algo in
                Text(algo.label).tag(algo)
            }
        }

        Picker("Color Mode", selection: colorModeTag) {
            Text("B&W").tag(0)
            Text("Two-Tone").tag(1)
            Text("Dominant").tag(3)
            Text("Color").tag(2)
        }
        .pickerStyle(.segmented)

        if params.algorithm == .bayer {
            Stepper(
                "Bayer Level: \(params.bayerLevel)",
                value: bayerLevelBinding,
                in: 1...4
            )
            .caption("(\(1 << (params.bayerLevel + 1))×\(1 << (params.bayerLevel + 1)))")
        }

        Stepper(
            "Pixel Scale: \(params.pixelScale)×",
            value: pixelScaleBinding,
            in: 1...8
        )

        if case .twoTone(let fg, let bg) = params.colorMode {
            ColorPickerWithHex("Foreground", selection: foregroundBinding(fg: fg, bg: bg))
            ColorPickerWithHex("Background", selection: backgroundBinding(fg: fg, bg: bg))
        }

        if case .dominantTwoTone(let flipped, let sat, let light) = params.colorMode {
            Toggle("Flip Colors", isOn: Binding(
                get: { flipped },
                set: { var p = params; p.colorMode = .dominantTwoTone(flipped: $0, saturationShift: sat, lightnessShift: light); onChange(p) }
            ))
            .caption("Swap foreground and background")

            VStack(alignment: .leading, spacing: 4) {
                Text("Saturation")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Slider(value: Binding(
                    get: { sat },
                    set: { var p = params; p.colorMode = .dominantTwoTone(flipped: flipped, saturationShift: $0, lightnessShift: light); onChange(p) }
                ), in: -50...50)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Slider(value: Binding(
                    get: { light },
                    set: { var p = params; p.colorMode = .dominantTwoTone(flipped: flipped, saturationShift: sat, lightnessShift: $0); onChange(p) }
                ), in: -50...50)
            }
        }

        if case .color(let levels) = params.colorMode {
            Stepper(
                "Levels: \(levels) per channel",
                value: levelsBinding(levels),
                in: 2...8
            )
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Threshold: \(String(format: "%.2f", params.threshold))")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            Slider(value: thresholdBinding, in: 0.1...0.9, step: 0.05)
        }
        .caption("Lower = darker, Higher = brighter")

        VStack(alignment: .leading, spacing: 4) {
            Text("Sharpen: \(String(format: "%.0f%%", params.sharpen * 100))")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            Slider(value: sharpenBinding, in: 0...1, step: 0.1)
        }
        .caption("Pre-sharpen to preserve edge detail")

        VStack(alignment: .leading, spacing: 4) {
            Text("Contrast: \(String(format: "%.0f%%", params.contrast * 100))")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            Slider(value: contrastBinding, in: 0...1, step: 0.1)
        }
        .caption("Boost contrast before dithering")
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
}

private extension View {
    func caption(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            self
            Text(text)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
        }
    }
}

// MARK: - LUTLayerControls

struct LUTLayerControls: View {
    @Environment(AppState.self) private var appState
    var params: LUTLayerParams
    var onChange: (LUTLayerParams) -> Void

    @State private var availableLUTs: [LUTInfo] = []
    @State private var thumbnailCache: [String: CGImage] = [:]
    @State private var renamingLUT: LUTInfo?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 12) {
            lutPicker
            lutThumbnailStrip
            intensityControl
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
        Picker("LUT", selection: lutNameBinding) {
            Text("None").tag("")
            ForEach(availableLUTs) { lut in
                Text(lut.displayName).tag(lut.id)
            }
        }
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
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableLUTs) { lut in
                        lutThumb(lut)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var intensityControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Intensity")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                Text("\(Int(params.intensity * 100))%")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
            }
            Slider(value: intensityBinding, in: 0...1, step: 0.05)
        }
    }

    private var importButtons: some View {
        HStack {
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
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: Binding(
                get: { params.style },
                set: { onChange(params.withStyle($0)) }
            )) {
                ForEach(ShaderStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }

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

        VStack(alignment: .leading, spacing: 4) {
            Text("Colors")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
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
            .labelsHidden()
            .pickerStyle(.segmented)
        }

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
            Toggle("Flip Palette", isOn: Binding(
                get: { flipped },
                set: { value in
                    updateASCII(asciiParams, colorMode: .dominantTwoTone(
                        flipped: value,
                        saturationShift: saturationShift,
                        lightnessShift: lightnessShift
                    ))
                }
            ))

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

        Toggle("Invert", isOn: Binding(
            get: { asciiParams.invert },
            set: { value in
                updateASCII(asciiParams, invert: value)
            }
        ))
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

        VStack(alignment: .leading, spacing: 8) {
            Text("Characters")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)

            Picker("", selection: Binding<ASCIIPreset>(
                get: { selectedPreset },
                set: { newValue in
                    switch newValue {
                    case .default:
                        updateASCII(asciiParams, characters: .some(nil))
                    case .custom:
                        // Preserve whatever string the user currently has —
                        // seed with the classic palette if they're picking
                        // Custom for the first time.
                        let seed = asciiParams.characters ?? ASCIIPreset.classic.characters ?? ""
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

                HStack(spacing: 6) {
                    Text("\(characterCount) / 10")
                        .font(.caption)
                        .foregroundStyle(Color.text2)
                    Spacer()
                }

                // Mini ramp preview: 10 cells, each the character that would
                // rasterise at that luminance slot over a gray background
                // matching the relative luma. Makes the N-across-10 mapping
                // explicit without the user having to apply + re-render.
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
        characters: String?? = nil
    ) {
        onChange(params.withParams(.ascii(ASCIIShaderParams(
            cellSize: cellSize ?? asciiParams.cellSize,
            edgeBias: edgeBias ?? asciiParams.edgeBias,
            colorMode: colorMode ?? asciiParams.colorMode,
            invert: invert ?? asciiParams.invert,
            exposure: exposure ?? asciiParams.exposure,
            attenuation: attenuation ?? asciiParams.attenuation,
            blackLevel: blackLevel ?? asciiParams.blackLevel,
            characters: characters ?? asciiParams.characters
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
        Picker("Direction", selection: Binding(
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
        Toggle("Monochrome", isOn: Binding(
            get: { halftoneParams.monochrome },
            set: { value in
                var updated = halftoneParams; updated.monochrome = value
                onChange(params.withParams(.halftone(updated)))
            }
        ))
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                Text(step >= 1 ? "\(Int(value.rounded()))" : String(format: "%.2f", value))
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
            }
            Slider(value: Binding(get: { value }, set: onSet), in: range, step: step)
        }
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
