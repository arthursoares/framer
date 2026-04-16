import SwiftUI

enum StyledSliderValueResolver {
    static func constrain(_ rawValue: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let clampedValue = rawValue.clamped(to: range)

        guard step > 0 else {
            return clampedValue
        }

        return ((clampedValue / step).rounded() * step).clamped(to: range)
    }
}

/// Slider + inline numeric field. Unit rendering is intentionally NOT handled
/// here — callers that need a unit suffix compose either
/// `StyledUnitSlider` (convenience wrapper) or `SidebarTrailingUnitCluster`
/// from inside a `SidebarControlRow`'s `trailingValue`.
struct StyledSlider: View {
    @Environment(\.sidebarMetrics) private var metrics

    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: LocalizedStringKey? = nil
    var step: Double = 1

    var body: some View {
        HStack(spacing: metrics.controlTrailingClusterSpacing) {
            Slider(value: snappedBinding, in: range)
                .tint(Color.accentDim)
                .frame(maxWidth: .infinity)
                .modifier(StyledSliderAccessibilityLabel(label: accessibilityLabel))

            TextField("", value: constrainedTextFieldBinding, format: .number)
                .textFieldStyle(.plain)
                .font(AppFont.numericInput)
                .foregroundStyle(Color.text1)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: metrics.controlValueFieldWidth)
                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .modifier(StyledSliderAccessibilityLabel(label: accessibilityLabel))
        }
    }

    private var snappedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = StyledSliderValueResolver.constrain($0, range: range, step: step) }
        )
    }

    private var constrainedTextFieldBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = StyledSliderValueResolver.constrain($0, range: range, step: step) }
        )
    }
}

/// Wraps `StyledSlider` with a trailing unit suffix that matches the
/// `SidebarTrailingUnitCluster` width contract. Use when a row is
/// "slider + field + unit" as a single content unit, rather than splitting
/// across a `SidebarControlRow`'s content / trailingValue slots.
struct StyledUnitSlider: View {
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: LocalizedStringKey? = nil
    var step: Double = 1
    var unit: LocalizedStringKey

    var body: some View {
        HStack(spacing: metrics.controlTrailingClusterSpacing) {
            StyledSlider(
                value: $value,
                range: range,
                accessibilityLabel: accessibilityLabel,
                step: step
            )
            Text(unit)
                .font(AppFont.mono(9))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlUnitSuffixWidth, alignment: .leading)
        }
    }
}

private struct StyledSliderAccessibilityLabel: ViewModifier {
    let label: LocalizedStringKey?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
