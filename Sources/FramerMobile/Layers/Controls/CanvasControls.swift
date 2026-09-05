import SwiftUI
import FramerCore

// MARK: - Canvas Controls

struct CanvasControls: View {
    var params: CanvasLayerParams
    var onChange: (CanvasLayerParams) -> Void

    private let presets: [(String, Int, Int)] = [
        ("Instagram 4:5", 1080, 1350),
        ("10×15cm 300dpi", 1772, 1181),
        ("Square 1080", 1080, 1080),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Size Presets") {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { name, w, h in
                        Button {
                            var p = params; p.width = w; p.height = h; onChange(p)
                        } label: {
                            Text(name)
                                .font(AppFont.body(11))
                                .foregroundStyle(params.width == w && params.height == h ? Color.accent : Color.text2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    params.width == w && params.height == h ? Color.accentSubtle : Color.surface3,
                                    in: RoundedRectangle(cornerRadius: CornerRadius.md)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                ControlRow(label: "Width") {
                    TextField("", value: Binding(
                        get: { params.width },
                        set: { var p = params; p.width = $0; onChange(p) }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
                ControlRow(label: "Height") {
                    TextField("", value: Binding(
                        get: { params.height },
                        set: { var p = params; p.height = $0; onChange(p) }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
            }

            FillPicker(fill: params.fill) { newFill in
                var p = params; p.fill = newFill; onChange(p)
            }
        }
    }
}

