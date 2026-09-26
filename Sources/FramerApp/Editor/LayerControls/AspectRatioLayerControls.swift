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
        params.isCustomRatio || !presets.contains { $0.w == params.ratioWidth && $0.h == params.ratioHeight }
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
                                set: {
                                    var updated = params
                                    updated.ratioWidth = max(1, $0)
                                    updated.isCustomRatio = true
                                    onChange(updated)
                                }
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
                                set: {
                                    var updated = params
                                    updated.ratioHeight = max(1, $0)
                                    updated.isCustomRatio = true
                                    onChange(updated)
                                }
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
                if newValue == "custom" {
                    var updated = params
                    updated.isCustomRatio = true
                    onChange(updated)
                    return
                }
                if let preset = presets.first(where: { "\($0.w):\($0.h)" == newValue }) {
                    var updated = params
                    updated.ratioWidth = preset.w
                    updated.ratioHeight = preset.h
                    updated.isCustomRatio = false
                    onChange(updated)
                }
            }
        )
    }

    private var offsetXBinding: Binding<Double> {
        Binding(
            get: { params.offsetX },
            set: {
                var updated = params
                updated.offsetX = $0
                onChange(updated)
            }
        )
    }

    private var offsetYBinding: Binding<Double> {
        Binding(
            get: { params.offsetY },
            set: {
                var updated = params
                updated.offsetY = $0
                onChange(updated)
            }
        )
    }
}

// MARK: - OrientationLayerControls
