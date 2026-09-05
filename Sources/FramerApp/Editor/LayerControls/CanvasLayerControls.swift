import SwiftUI
import AppKit
import FramerCore

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

