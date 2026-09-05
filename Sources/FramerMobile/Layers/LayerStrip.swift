import SwiftUI
import FramerCore

struct LayerStrip: View {
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layers: Binding<[CompositionLayer]> {
        Binding(
            get: { appState.editorLayers },
            set: { appState.editorLayers = $0 }
        )
    }

    @State private var draggingID: UUID?
    @State private var dropTargetIndex: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(layers.wrappedValue.enumerated()), id: \.element.id) { index, layer in
                    VStack(spacing: 0) {
                        // Drop indicator above this row
                        if dropTargetIndex == index {
                            dropIndicator
                        }

                        HStack(spacing: 0) {
                            NavigationLink(value: layer.id) {
                                LayerRow(layer: layer)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(layer.label)
                            .accessibilityValue(layer.accessibilitySummary)
                            .accessibilityHint("Opens controls for this layer")
                            .accessibilityAction(named: Text("Move \(layer.label) up")) {
                                moveLayer(layer.id, direction: .up)
                            }
                            .accessibilityAction(named: Text("Move \(layer.label) down")) {
                                moveLayer(layer.id, direction: .down)
                            }
                            .accessibilityAction(named: Text("Delete \(layer.label) layer")) {
                                deleteLayer(layer.id)
                            }

                            LayerVisibilityButton(
                                layerName: layer.label,
                                isEnabled: layer.isEnabled,
                                action: { toggleVisibility(for: layer.id) }
                            )
                        }
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                        .opacity(draggingID == layer.id ? 0.3 : (layer.isEnabled ? 1.0 : 0.65))
                        .draggable(layer.id.uuidString) {
                            Text(layer.label)
                                .font(AppFont.layerName)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                                .overlay(RoundedRectangle(cornerRadius: CornerRadius.md).stroke(Color.accent.opacity(0.3), lineWidth: 1))
                                .onAppear { draggingID = layer.id }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            dropTargetIndex = nil
                            draggingID = nil
                            guard let droppedStr = items.first,
                                  let droppedID = UUID(uuidString: droppedStr) else { return false }
                            return moveDroppedLayer(droppedID, to: layer.id)
                        } isTargeted: { targeted in
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                                dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
                            }
                        }
                    }
                }

                addLayerButton
            }
            .padding(.horizontal, 16)
        }
        .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : 220)
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
        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
    }

    private var addLayerButton: some View {
        Menu {
            Button { addLayer(.border(BorderLayerParams())) } label: {
                Label("Border", systemImage: "square.dashed")
            }
            Button { addLayer(.padding(PaddingLayerParams())) } label: {
                Label("Padding", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button { addLayer(.canvas(CanvasLayerParams())) } label: {
                Label("Canvas", systemImage: "rectangle.on.rectangle")
            }
            Button { addLayer(.resize(ResizeLayerParams())) } label: {
                Label("Resize", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            Button { addLayer(.aspectRatio(AspectRatioLayerParams())) } label: {
                Label("Aspect Ratio", systemImage: "aspectratio")
            }
            Button { addLayer(.orientation(OrientationLayerParams())) } label: {
                Label("Orientation", systemImage: "rotate.right")
            }
            Button { addLayer(.caption(CaptionLayerParams())) } label: {
                Label("Caption", systemImage: "textformat")
            }
            Button { addLayer(.dither(DitherLayerParams())) } label: {
                Label("Dither", systemImage: "circle.dotted")
            }
            Divider()
            Button { addLayer(.overlay(OverlayLayerParams(kind: .frame))) } label: {
                Label("Frame Overlay", systemImage: "photo.artframe")
            }
            Button { addLayer(.overlay(OverlayLayerParams(kind: .dust))) } label: {
                Label("Dust & Scratches", systemImage: "sparkles")
            }
            Button { addLayer(.overlay(OverlayLayerParams(kind: .lightLeak))) } label: {
                Label("Light Leak", systemImage: "sun.max.trianglebadge.exclamationmark")
            }
            Button { addLayer(.overlay(OverlayLayerParams(kind: .wetPlate))) } label: {
                Label("Wet Plate", systemImage: "drop.halffull")
            }
            Divider()
            Button { addLayer(.lut(LUTLayerParams())) } label: {
                Label("LUT", systemImage: "photo.artframe")
            }
            // Per-style shader entries — mirrors the GPU-effect pattern
            // below so each shader (ASCII, Kuwahara, CRT, …) reads as its
            // own first-class filter. Under the hood every entry still
            // builds a `.shader` layer; the style chooses which renderer
            // runs and which parameter panel shows in the inspector.
            ForEach(ShaderStyle.allCases, id: \.self) { style in
                Button { addLayer(style.makeDefaultLayer()) } label: {
                    Label(style.label, systemImage: style.menuIcon)
                }
            }
            Divider()
            // Per-variant GPU-effect entries. Each is a first-class layer
            // type in the picker (Option B of the bucket-UI refactor); under
            // the hood all map to `.gpuEffect` with pre-scoped defaults.
            ForEach(GPUEffectKind.userFacingCases, id: \.self) { kind in
                Button { addLayer(kind.makeDefaultLayer()) } label: {
                    Label(kind.label, systemImage: kind.menuIcon)
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Layer")
            }
            .font(AppFont.controlLabel)
            .foregroundStyle(Color.text2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
        }
    }

    private func addLayer(_ layer: CompositionLayer) {
        layers.wrappedValue.append(layer)
    }

    private func toggleVisibility(for layerID: UUID) {
        updateLayers { LayerListMutation.toggleVisibility(of: layerID, in: &$0) }
    }

    private func moveLayer(_ layerID: UUID, direction: LayerMoveDirection) {
        updateLayers { LayerListMutation.move(layerID, direction: direction, in: &$0) }
    }

    private func moveDroppedLayer(_ layerID: UUID, to targetID: UUID) -> Bool {
        var updated = layers.wrappedValue
        guard LayerListMutation.move(layerID, to: targetID, in: &updated) else { return false }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            layers.wrappedValue = updated
        }
        return true
    }

    private func deleteLayer(_ layerID: UUID) {
        updateLayers { LayerListMutation.delete(layerID, in: &$0) }
    }

    private func updateLayers(_ mutation: (inout [CompositionLayer]) -> Bool) {
        var updated = layers.wrappedValue
        guard mutation(&updated) else { return }
        layers.wrappedValue = updated
    }
}

struct LayerRow: View {
    let layer: CompositionLayer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: layer.iconName)
                .foregroundStyle(layer.isEnabled ? Color.text2 : Color.text3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(layer.label)
                    .font(AppFont.layerName)
                    .foregroundStyle(layer.isEnabled ? Color.text0 : Color.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(layer.accessibilitySummary)
                    .font(AppFont.badgeSummary)
                    .foregroundStyle(Color.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.text3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

struct LayerVisibilityButton: View {
    let layerName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                "Visibility for \(layerName)",
                systemImage: isEnabled ? "eye" : "eye.slash"
            )
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isEnabled ? Color.text2 : Color.text3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Visibility for \(layerName)")
        .accessibilityValue(isEnabled ? "Visible" : "Hidden")
        .accessibilityHint(isEnabled ? "Hides this layer" : "Shows this layer")
    }
}

enum LayerMoveDirection: Equatable {
    case up
    case down
}

enum LayerListMutation {
    @discardableResult
    static func toggleVisibility(of layerID: UUID, in layers: inout [CompositionLayer]) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return false }
        layers[index].isEnabled.toggle()
        return true
    }

    @discardableResult
    static func move(
        _ layerID: UUID,
        direction: LayerMoveDirection,
        in layers: inout [CompositionLayer]
    ) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return false }
        let destination = direction == .up ? index - 1 : index + 1
        guard layers.indices.contains(destination) else { return false }
        layers.swapAt(index, destination)
        return true
    }

    @discardableResult
    static func move(_ layerID: UUID, to targetID: UUID, in layers: inout [CompositionLayer]) -> Bool {
        guard layerID != targetID,
              let sourceIndex = layers.firstIndex(where: { $0.id == layerID }),
              let targetIndex = layers.firstIndex(where: { $0.id == targetID }) else { return false }
        let movedLayer = layers.remove(at: sourceIndex)
        layers.insert(movedLayer, at: targetIndex)
        return true
    }

    @discardableResult
    static func delete(_ layerID: UUID, in layers: inout [CompositionLayer]) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return false }
        layers.remove(at: index)
        return true
    }
}

extension CompositionLayer {
    var accessibilitySummary: String {
        if !isEnabled { return "Disabled" }
        switch self {
        case .border(let p):
            switch p.thickness {
            case .pixels(let px): return "\(px)px"
            case .percent(let pct): return "\(Int(pct))%"
            }
        case .padding(let p): return "\(p.thickness)px"
        case .canvas(let p): return "\(p.width)×\(p.height)"
        case .resize(let p): return "max \(p.maxWidth)×\(p.maxHeight)"
        case .overlay(let p):
            if p.overlayName.isEmpty { return "None" }
            return "\(p.kind.label) \(Int(p.opacity))%"
        case .orientation(let p): return p.target.rawValue.capitalized
        case .caption(let p):
            switch p.mode {
            case .template: return "Template"
            case .custom: return "Custom"
            case .none: return "Off"
            }
        case .dither(let p): return p.algorithm.label
        case .aspectRatio(let p): return "\(p.ratioWidth):\(p.ratioHeight)"
        case .lut(let p): return p.lutName.isEmpty ? "None" : p.lutName
        case .shader(let p): return p.style.label
        case .gpuEffect(let p): return p.kind.label
        }
    }
}
