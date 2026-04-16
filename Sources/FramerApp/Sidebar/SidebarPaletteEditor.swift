import SwiftUI
import FramerCore

/// Swatch + hex + delete triplet rows for editable color palettes (Dither,
/// future quantisers). Enforces metric-derived spacing and stays within
/// `metrics.containedPreviewMaxWidth`. Adds a tiny "+ Add color" affordance
/// when below `maxColors`.
struct SidebarPaletteEditor: View {
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var colors: [CodableColor]
    var maxColors: Int = 16
    var minColors: Int = 1
    var defaultNewColor: CodableColor = .white

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: metrics.controlColumnSpacing) {
                    ColorPickerWithHex("", selection: colorBinding(at: index))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        guard colors.count > minColors else { return }
                        colors.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(colors.count > minColors ? Color.text3 : Color.text3.opacity(0.3))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(colors.count <= minColors)
                    .accessibilityLabel("Remove color")
                }
            }

            if colors.count < maxColors {
                Button {
                    colors.append(defaultNewColor)
                } label: {
                    Label("Add color", systemImage: "plus")
                        .font(AppFont.buttonText)
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add color")
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }

    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard index < colors.count else { return .white }
                return Color(nsColor: NSColor(cgColor: colors[index].cgColor) ?? .white)
            },
            set: { newColor in
                guard index < colors.count,
                      let hex = newColor.hexString,
                      let codable = try? CodableColor(hex: hex) else { return }
                colors[index] = codable
            }
        )
    }
}
