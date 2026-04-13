import SwiftUI
import FramerCore

struct LayerStrip: View {
    @Environment(AppState.self) var appState

    private var layers: Binding<[CompositionLayer]> {
        Binding(
            get: { appState.currentConfig.layers ?? CompositionLayer.defaultLayers() },
            set: { appState.currentConfig.layers = $0 }
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

                        NavigationLink(value: layer.id) {
                            LayerRow(layer: layer)
                        }
                        .buttonStyle(.plain)
                        .opacity(draggingID == layer.id ? 0.3 : 1.0)
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
                                  let droppedID = UUID(uuidString: droppedStr),
                                  let fromIndex = layers.wrappedValue.firstIndex(where: { $0.id == droppedID }),
                                  fromIndex != index else { return false }
                            let toOffset = index > fromIndex ? index + 1 : index
                            withAnimation(.easeInOut(duration: 0.2)) {
                                layers.wrappedValue.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
                            }
                            return true
                        } isTargeted: { targeted in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
                            }
                        }
                    }
                }

                addLayerButton
            }
            .padding(.horizontal, 16)
        }
        .frame(maxHeight: 220)
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
            Button { addLayer(.shader(ShaderLayerParams())) } label: {
                Label("Shader", systemImage: "sparkles.rectangle.stack")
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Layer")
            }
            .font(AppFont.controlLabel)
            .foregroundStyle(Color.text2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
        }
    }

    private func addLayer(_ layer: CompositionLayer) {
        layers.wrappedValue.append(layer)
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

                Text(layerSummary)
                    .font(AppFont.badgeSummary)
                    .foregroundStyle(Color.text3)
            }

            Spacer()

            Image(systemName: layer.isEnabled ? "eye" : "eye.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(layer.isEnabled ? Color.text2 : Color.text3)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.text3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
        .opacity(layer.isEnabled ? 1.0 : 0.65)
    }

    private var layerSummary: String {
        if !layer.isEnabled { return "Disabled" }
        switch layer {
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
