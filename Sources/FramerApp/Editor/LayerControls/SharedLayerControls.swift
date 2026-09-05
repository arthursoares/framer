import SwiftUI
import AppKit
import FramerCore


/// Wraps a `ColorPickerWithHex` leaf in a `denseControlRow` so the visible
/// label appears in the sidebar's 104pt label column instead of floating
/// inline next to the color well. Introduced as part of sidebar harmony
/// pass 3 to eliminate the stray "Color" / "Fill Color" / "Foreground" /
/// etc. chips rendered by `ColorPicker`'s own label.
@MainActor
func labeledColorPicker(
    _ label: String,
    selection: Binding<Color>,
    onHexCommit: ((CodableColor) -> Void)? = nil
) -> some View {
    ColorPickerWithHex(LocalizedStringKey(label), selection: selection, onHexCommit: onHexCommit)
        .denseControlRow(LocalizedStringKey(label))
}


extension View {
    func simpleLayerEditorInputStyle(width: CGFloat? = SidebarMetrics().controlValueFieldWidth) -> some View {
        self
            .textFieldStyle(.plain)
            .font(AppFont.numericInput)
            .foregroundStyle(Color.text1)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: width)
            .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Color.borderDefault, lineWidth: 1)
            )
    }

    func simpleLayerEditorInputStyle(width: CGFloat? = SidebarMetrics().controlValueFieldWidth, accessibilityLabel: String) -> some View {
        simpleLayerEditorInputStyle(width: width)
            .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct SimpleLayerEditorDivider: View {
    @Environment(\.sidebarMetrics) private var metrics

    var body: some View {
        Rectangle()
            .fill(Color.borderDefault)
            .frame(height: metrics.controlStackDividerThickness)
            .padding(.horizontal, metrics.controlStackDividerInset)
            .accessibilityHidden(true)
    }
}



struct DenseSliderControlRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: LocalizedStringKey? = nil
    let step: Double
    var unit: LocalizedStringKey? = nil
    /// Double-clicking the row's label area resets to this value (the
    /// parameter's canonical default). The slider and text field consume
    /// their own clicks, so the gesture effectively targets the label.
    var resetValue: Double? = nil

    var body: some View {
        SidebarControlRow(title) {
            Slider(value: snappedBinding, in: range)
                .tint(Color.accentDim)
                .accessibilityLabel(Text(accessibilityLabel ?? title))
        } trailingValue: {
            SidebarTrailingUnitCluster(unit: unit ?? "") {
                TextField("", value: snappedBinding, format: .number)
                    .simpleLayerEditorInputStyle()
                    .monospacedDigit()
                    .accessibilityLabel(Text(accessibilityLabel ?? title))
            }
        }
        .onTapGesture(count: 2) {
            if let resetValue {
                value = StyledSliderValueResolver.constrain(resetValue, range: range, step: step)
            }
        }
    }

    /// Shared snap-to-step binding — both the slider (drag) and the text
    /// field (typed entry) route through it so their values stay locked to
    /// `step` and within `range`.
    private var snappedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = StyledSliderValueResolver.constrain($0, range: range, step: step) }
        )
    }
}

private struct DenseSupplementaryControlRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    @Environment(\.sidebarMetrics) private var metrics

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.controlColumnSpacing) {
            Text(title)
                .font(AppFont.body(10))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlLabelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, metrics.outerInset)
        .padding(.top, 3)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func denseControlRow(_ title: LocalizedStringKey) -> some View {
        SidebarControlRow(title) {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func denseSupportingRow(_ title: LocalizedStringKey) -> some View {
        DenseSupplementaryControlRow(title) {
            self
        }
    }
}

