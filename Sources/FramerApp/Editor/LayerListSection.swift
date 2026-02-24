import SwiftUI
import FramerCore

// MARK: - LayerListSection

struct LayerListSection: View {
    @Binding var layers: [CompositionLayer]
    @State private var draggingLayerID: UUID?

    var body: some View {
        Section {
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                LayerRow(
                    layer: binding(for: index),
                    onDelete: { removeLayer(at: index) },
                    onMoveUp: index > 0 ? { layers.swapAt(index, index - 1) } : nil,
                    onMoveDown: index < layers.count - 1 ? { layers.swapAt(index, index + 1) } : nil
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layers.move(fromOffsets: IndexSet(integer: fromIndex),
                                    toOffset: index > fromIndex ? index + 1 : index)
                    }
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
        } label: {
            Label("Add Layer", systemImage: "plus.circle")
        }
    }

    private func removeLayer(at index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.remove(at: index)
        }
    }

    private func addLayer(_ layer: CompositionLayer) {
        withAnimation(.easeInOut(duration: 0.2)) {
            layers.append(layer)
        }
    }

    private func binding(for index: Int) -> Binding<CompositionLayer> {
        Binding(
            get: { layers[index] },
            set: { layers[index] = $0 }
        )
    }
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
        } label: {
            HStack(spacing: 4) {
                // Reorder buttons
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { onMoveUp?() }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                            .frame(width: 16, height: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(onMoveUp == nil)
                    .opacity(onMoveUp == nil ? 0.25 : 0.6)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { onMoveDown?() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .frame(width: 16, height: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(onMoveDown == nil)
                    .opacity(onMoveDown == nil ? 0.25 : 0.6)
                }

                Image(systemName: layer.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

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
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
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

        ColorPicker("Color", selection: colorBinding)
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

// MARK: - LayerFillPicker

struct LayerFillPicker: View {
    var fill: LayerFill
    var onChange: (LayerFill) -> Void

    var body: some View {
        Picker("Fill", selection: fillModeBinding) {
            Text("Solid Color").tag(0)
            Text("Dominant Color").tag(1)
            Text("Linear Gradient").tag(2)
            Text("Radial Gradient").tag(3)
        }

        if case .color(let c) = fill {
            ColorPicker("Fill Color", selection: Binding(
                get: { Color(nsColor: NSColor(cgColor: c.cgColor) ?? .white) },
                set: { newColor in
                    guard let hex = newColor.hexString else { return }
                    guard let codable = try? CodableColor(hex: hex) else { return }
                    onChange(.color(codable))
                }
            ))
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
                switch idx {
                case 0: onChange(.color(try! CodableColor(hex: "#FFFFFF")))
                case 1: onChange(.dominantColor)
                case 2: onChange(.gradientLinear)
                case 3: onChange(.gradientRadial)
                default: break
                }
            }
        )
    }
}

// MARK: - Color Helper

private extension Color {
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
