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
                    .foregroundStyle(Color.text0)

                Spacer()

                Text(layerSummary)
                    .font(AppFont.badgeSummary)
                    .foregroundStyle(Color.text2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.surface4, in: Capsule())

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(isHovering ? Color.error : Color.text3)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        }
    }

    private var layerSummary: String {
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
        }
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
                Text("Lightness")
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
            Text("Lightness")
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
                Text("Lightness")
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
                }
            },
            set: { tag in
                var p = params
                switch tag {
                case 0: p.colorMode = .bw
                case 1: p.colorMode = .twoTone(foreground: (try? CodableColor(hex: "#0251FF")) ?? .black, background: .black)
                case 2: p.colorMode = .color(levels: 4)
                case 3: p.colorMode = .dominantTwoTone(flipped: false)
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

    private func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Import Failed"
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

// MARK: - Color Helper

extension Color {
    var hexString: String? {
        guard let cgColor = NSColor(self).cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let comps = cgColor.components, comps.count >= 3 else {
            return nil
        }
        let r = Int(comps[0] * 255)
        let g = Int(comps[1] * 255)
        let b = Int(comps[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
