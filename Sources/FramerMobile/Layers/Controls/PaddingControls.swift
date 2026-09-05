import SwiftUI
import FramerCore

// MARK: - Padding Controls

struct PaddingControls: View {
    var params: PaddingLayerParams
    var onChange: (PaddingLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Thickness") {
                HStack {
                    Slider(value: Binding(
                        get: { Double(params.thickness) },
                        set: { var p = params; p.thickness = Int($0); onChange(p) }
                    ), in: 0...400)
                    Text("\(params.thickness)px")
                        .font(AppFont.mono(12))
                        .foregroundStyle(Color.text1)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            FillPicker(fill: params.fill) { newFill in
                var p = params; p.fill = newFill; onChange(p)
            }
        }
    }
}

