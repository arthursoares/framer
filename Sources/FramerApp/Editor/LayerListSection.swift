import SwiftUI
import AppKit
import FramerCore

// MARK: - LayerListSection

struct LayerListSection: View {
    @Binding var layers: [CompositionLayer]
    @Environment(\.undoManager) private var undoManager
    @State private var draggingLayerID: UUID?

    var body: some View {
        Section {
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                LayerRow(
                    layer: binding(for: index),
                    onDelete: { removeLayer(at: index) },
                    onMoveUp: index > 0 ? { moveLayer(from: index, to: index - 1) } : nil,
                    onMoveDown: index < layers.count - 1 ? { moveLayer(from: index, to: index + 1) } : nil
                )
                .draggable(layer.id.uuidString) {
                    Label(layer.label, systemImage: layer.iconName)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let droppedIDString = items.first,
                          let droppedID = UUID(uuidString: droppedIDString),
                          let fromIndex = layers.firstIndex(where: { $0.id == droppedID }),
                          fromIndex != index else { return false }
                    let toOffset = index > fromIndex ? index + 1 : index
                    let snapshot = layers
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layers.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
                    }
                    undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            layers = snapshot
                        }
                    }
                    undoManager?.setActionName("Move Layer")
                    return true
                }
            }

            addLayerMenu
        } header: {
            Text("Layers (\(layers.count))")
        }
    }

    private var addLayerMenu: some View {
        Menu {
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
        } label: {
            Label("Add Layer", systemImage: "plus.circle")
        }
    }

    private func removeLayer(at index: Int) {
        let removed = layers[index]
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.remove(at: index)
        }
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                let insertAt = min(index, layers.count)
                layers.insert(removed, at: insertAt)
            }
        }
        undoManager?.setActionName("Delete Layer")
    }

    private func addLayer(_ layer: CompositionLayer) {
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.append(layer)
        }
        let addedIndex = layers.count - 1
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                if addedIndex < layers.count {
                    layers.remove(at: addedIndex)
                }
            }
        }
        undoManager?.setActionName("Add Layer")
    }

    private func moveLayer(from source: Int, to destination: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.swapAt(source, destination)
        }
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                layers.swapAt(destination, source)
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
private final class UndoProxy: NSObject {
    static let shared = UndoProxy()
}

// MARK: - LayerRow

struct LayerRow: View {
    @Binding var layer: CompositionLayer
    let onDelete: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        DisclosureGroup {
            layerControls
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                // Reorder buttons
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { onMoveUp?() }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onMoveUp == nil)
                    .opacity(onMoveUp == nil ? 0.25 : 0.6)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { onMoveDown?() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onMoveDown == nil)
                    .opacity(onMoveDown == nil ? 0.25 : 0.6)
                }

                Image(systemName: layer.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(layer.label)

                Spacer()

                Text(layerSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .padding(.vertical, 2)
            .onHover { isHovering = $0 }
        }
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
        LabeledContent("Thickness") {
            VStack(spacing: 4) {
                Picker("", selection: $thicknessMode) {
                    ForEach(ThicknessMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .labelsHidden()

                HStack {
                    Slider(value: thicknessValue, in: thicknessRange)
                    TextField("", value: thicknessValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text(thicknessMode.rawValue)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
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
        LabeledContent("Thickness") {
            HStack {
                Slider(value: thicknessBinding, in: 0...400)
                TextField("", value: thicknessBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("px")
                    .foregroundStyle(.secondary)
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
        HStack {
            LabeledContent("Width") {
                TextField("", value: widthBinding, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
            Text("px").foregroundStyle(.secondary).frame(width: 20)
            LabeledContent("Height") {
                TextField("", value: heightBinding, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
            Text("px").foregroundStyle(.secondary).frame(width: 20)
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

                LabeledContent("DPI") {
                    TextField("", value: $dpi, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .onChange(of: dpi) { _, _ in syncPhysicalToPixels() }
                }
            }

            HStack {
                LabeledContent("Width") {
                    TextField("", value: $widthPhysical, format: .number.precision(.fractionLength(1)))
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .onChange(of: widthPhysical) { _, _ in syncPhysicalToPixels() }
                }
                Text(physicalUnit.rawValue).foregroundStyle(.secondary).frame(width: 24)
                LabeledContent("Height") {
                    TextField("", value: $heightPhysical, format: .number.precision(.fractionLength(1)))
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .onChange(of: heightPhysical) { _, _ in syncPhysicalToPixels() }
                }
                Text(physicalUnit.rawValue).foregroundStyle(.secondary).frame(width: 24)
            }
        }
    }

    @ViewBuilder
    private var pixelSummary: some View {
        if sizeMode == .physical {
            HStack {
                Spacer()
                Text("\(params.width) x \(params.height) px")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
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
        HStack {
            LabeledContent("Max Width") {
                TextField("", value: maxWidthBinding, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Max Height") {
                TextField("", value: maxHeightBinding, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
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
        LabeledContent("Opacity") {
            HStack {
                Slider(value: opacityBinding, in: 0...100)
                TextField("", value: opacityBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("%")
                    .foregroundStyle(.secondary)
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
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
                thumbnail = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
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
            LabeledContent("Saturation") {
                HStack {
                    Slider(value: saturationBinding(params), in: -50...50)
                    TextField("", value: saturationBinding(params), formatter: Self.signedFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
            LabeledContent("Lightness") {
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
                case 0: onChange(.color(try! CodableColor(hex: "#FFFFFF")))
                case 1: onChange(.dominantColor)
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
            LabeledContent("Offset X") {
                HStack {
                    Slider(value: offsetXBinding, in: -200...200)
                    TextField("", value: offsetXBinding, formatter: Self.signedIntFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text("px")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
            }

            // Offset Y
            LabeledContent("Offset Y") {
                HStack {
                    Slider(value: offsetYBinding, in: -200...200)
                    TextField("", value: offsetYBinding, formatter: Self.signedIntFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text("px")
                        .foregroundStyle(.secondary)
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
                LabeledContent("Font Size") {
                    HStack {
                        Slider(value: fontSizeBinding(pts), in: 8...120)
                        TextField("", value: fontSizeBinding(pts), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text("pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }
                }
            }

            // Font color
            ColorPickerWithHex("Font Color", selection: fontColorBinding)
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

    private var fontColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: params.fontColor.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.fontColor = c
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
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .trailing)

            FlowLayout(spacing: 4) {
                ForEach(TemplateToken.all.filter { $0.category == category }) { token in
                    Button {
                        text.append(token.token)
                    } label: {
                        Text(token.label)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
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
