import SwiftUI
import AppKit
import FramerCore

// MARK: - LayerListSection

struct LayerListSection: View {
    @Binding var layers: [CompositionLayer]
    @State private var draggingLayerID: UUID?
    @State private var dropTargetIndex: Int?

    var body: some View {
        SidebarSection("LAYERS (\(layers.count))", metrics: SidebarMetrics(expandedBodyInset: 0)) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                    LayerPanelRow(
                        layer: binding(for: layer),
                        isDragging: draggingLayerID == layer.id,
                        isDropTarget: dropTargetIndex == index,
                        onDelete: { removeLayer(at: index) },
                        onMoveUp: index > 0 ? { moveLayer(from: index, to: index - 1) } : nil,
                        onMoveDown: index < layers.count - 1 ? { moveLayer(from: index, to: index + 1) } : nil,
                        onDragStart: { draggingLayerID = layer.id }
                    )
                    // Drop indicator is an overlay rather than a view inserted
                    // into the layout flow: inserting it used to push the row
                    // down on hover, sliding it out from under the cursor and
                    // flipping `isTargeted` off — a flicker loop that made drops
                    // hard to land. An overlay never reflows the list.
                    .overlay(alignment: .top) {
                        if dropTargetIndex == index {
                            dropIndicator
                                .offset(y: -Spacing.xs)
                        }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        dropTargetIndex = nil
                        draggingLayerID = nil
                        guard let droppedIDString = items.first,
                              let droppedID = UUID(uuidString: droppedIDString),
                              let fromIndex = layers.firstIndex(where: { $0.id == droppedID }),
                              fromIndex != index else { return false }

                        let toOffset = index > fromIndex ? index + 1 : index

                        withAnimation(.easeInOut(duration: 0.2)) {
                            layers.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
                        }
                        return true
                    } isTargeted: { targeted in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
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

    // Layer mutations no longer register undo here — every config edit
    // (including these) is captured by the ConfigUndoCoalescer hook in
    // ContentView, which coalesces slider bursts and covers controls this
    // per-call plumbing never reached.
    private func removeLayer(at index: Int) {
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            layers.remove(at: index)
        }
    }

    private func addLayer(_ layer: CompositionLayer) {
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.append(layer)
        }
    }

    private func moveLayer(from source: Int, to destination: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.swapAt(source, destination)
        }
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
