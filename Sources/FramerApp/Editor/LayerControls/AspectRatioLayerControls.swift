import SwiftUI
import AppKit
import FramerCore

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
                        EmptyView()
                    } trailingValue: {
                        SidebarTrailingUnitCluster(unit: "") {
                            TextField("", value: Binding(
                                get: { params.ratioWidth },
                                set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: max(1, $0), ratioHeight: params.ratioHeight, offsetX: params.offsetX, offsetY: params.offsetY)) }
                            ), format: .number)
                            .simpleLayerEditorInputStyle(accessibilityLabel: "Width")
                            .monospacedDigit()
                        }
                    }
                } secondary: {
                    SidebarControlRow("Height") {
                        EmptyView()
                    } trailingValue: {
                        SidebarTrailingUnitCluster(unit: "") {
                            TextField("", value: Binding(
                                get: { params.ratioHeight },
                                set: { onChange(AspectRatioLayerParams(id: params.id, ratioWidth: params.ratioWidth, ratioHeight: max(1, $0), offsetX: params.offsetX, offsetY: params.offsetY)) }
                            ), format: .number)
                            .simpleLayerEditorInputStyle(accessibilityLabel: "Height")
                            .monospacedDigit()
                        }
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

