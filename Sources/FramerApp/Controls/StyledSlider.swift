import SwiftUI

struct StyledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix: String = ""
    var inputWidth: CGFloat = 55

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: snappedBinding, in: range)
                .tint(Color.accentDim)

            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .font(AppFont.numericInput)
                .foregroundStyle(Color.text1)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: inputWidth)
                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )

            if !suffix.isEmpty {
                Text(suffix)
                    .font(AppFont.mono(9))
                    .foregroundStyle(Color.text3)
                    .frame(width: 20)
            }
        }
    }

    private var snappedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = (($0 / step).rounded() * step).clamped(to: range) }
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
