import SwiftUI
import FramerCore

// MARK: - Border Controls

struct BorderControls: View {
    var params: BorderLayerParams
    var onChange: (BorderLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Thickness") {
                HStack {
                    Slider(value: thicknessValue, in: thicknessRange)
                    Text("\(Int(thicknessValue.wrappedValue))\(thicknessUnit)")
                        .font(AppFont.mono(12))
                        .foregroundStyle(Color.text1)
                        .frame(width: 50, alignment: .trailing)
                }
            }

            ControlRow(label: "Color") {
                ColorPicker("", selection: colorBinding)
                    .labelsHidden()
                    .accessibilityLabel("Border Color")
            }
        }
    }

    private var thicknessUnit: String {
        if case .percent = params.thickness { return "%" }
        return "px"
    }

    private var thicknessRange: ClosedRange<Double> {
        if case .percent = params.thickness { return 0...20 }
        return 0...300
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
                switch params.thickness {
                case .pixels: p.thickness = .pixels(Int(val))
                case .percent: p.thickness = .percent(val)
                }
                onChange(p)
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(cgColor: params.color.cgColor) },
            set: { newColor in
                guard let hex = newColor.hexString, let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.color = c
                onChange(p)
            }
        )
    }
}

