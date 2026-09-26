import SwiftUI
import FramerCore

// MARK: - Aspect Ratio Controls

struct AspectRatioControls: View {
    var params: AspectRatioLayerParams
    var onChange: (AspectRatioLayerParams) -> Void

    private let presets: [(String, Int, Int)] = [
        ("1:1", 1, 1), ("4:5", 4, 5), ("5:4", 5, 4),
        ("3:2", 3, 2), ("2:3", 2, 3), ("16:9", 16, 9), ("9:16", 9, 16),
    ]

    private var isCustom: Bool {
        params.isCustomRatio || !presets.contains { $0.1 == params.ratioWidth && $0.2 == params.ratioHeight }
    }

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Ratio") {
                Picker("", selection: Binding(
                    get: {
                        isCustom ? "Custom" : (presets.first { $0.1 == params.ratioWidth && $0.2 == params.ratioHeight }?.0 ?? "Custom")
                    },
                    set: { val in
                        if let preset = presets.first(where: { $0.0 == val }) {
                            var updated = params
                            updated.ratioWidth = preset.1
                            updated.ratioHeight = preset.2
                            updated.isCustomRatio = false
                            onChange(updated)
                        } else if val == "Custom" {
                            var updated = params
                            updated.isCustomRatio = true
                            onChange(updated)
                        }
                    }
                )) {
                    ForEach(presets, id: \.0) { Text($0.0).tag($0.0) }
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.menu)
            }

            if isCustom {
                HStack(spacing: 8) {
                    ControlRow(label: "Width") {
                        TextField("", value: Binding(
                            get: { params.ratioWidth },
                            set: {
                                var updated = params
                                updated.ratioWidth = max(1, $0)
                                updated.isCustomRatio = true
                                onChange(updated)
                            }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                    }
                    ControlRow(label: "Height") {
                        TextField("", value: Binding(
                            get: { params.ratioHeight },
                            set: {
                                var updated = params
                                updated.ratioHeight = max(1, $0)
                                updated.isCustomRatio = true
                                onChange(updated)
                            }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                    }
                }
            }

            ControlRow(label: "Offset X") {
                HStack {
                    Slider(value: Binding(
                        get: { params.offsetX },
                        set: { var updated = params; updated.offsetX = $0; onChange(updated) }
                    ), in: -1...1)
                    Text(String(format: "%.1f", params.offsetX))
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }

            ControlRow(label: "Offset Y") {
                HStack {
                    Slider(value: Binding(
                        get: { params.offsetY },
                        set: { var updated = params; updated.offsetY = $0; onChange(updated) }
                    ), in: -1...1)
                    Text(String(format: "%.1f", params.offsetY))
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}
