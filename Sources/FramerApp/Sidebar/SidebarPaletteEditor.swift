import SwiftUI
import FramerCore

/// Swatch + hex + delete triplet rows for editable color palettes (Dither,
/// future quantisers). Enforces metric-derived spacing and stays within
/// `metrics.containedPreviewMaxWidth`. Adds a tiny "+ Add colour" affordance
/// when below `maxColors`.
///
/// Stable identities are maintained internally by tracking a per-swatch
/// `UUID` that persists across value mutations at the same index, so
/// removing a color at index `N` doesn't cause the remaining swatches to
/// retarget their ColorPicker / hex bindings.
struct SidebarPaletteEditor: View {
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var colors: [CodableColor]
    var maxColors: Int = 16
    var minColors: Int = 1
    var defaultNewColor: CodableColor = .white

    @State private var identities: [UUID] = []

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            ForEach(Array(resolvedIdentities.enumerated()), id: \.element) { index, _ in
                paletteRow(at: index)
            }

            if colors.count < maxColors {
                Button {
                    appendColor()
                } label: {
                    Label("Add colour", systemImage: "plus")
                        .font(AppFont.buttonText)
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add colour")
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
        .onAppear { syncIdentitiesToColors() }
        .onChange(of: colors.count) { _, _ in syncIdentitiesToColors() }
    }

    /// Returns `identities`, padding with fresh UUIDs if `colors` grew before
    /// `.onChange(of:)` had a chance to fire. Guarantees the `ForEach` binds
    /// to exactly `colors.count` stable IDs on every render.
    private var resolvedIdentities: [UUID] {
        if identities.count >= colors.count {
            return Array(identities.prefix(colors.count))
        }
        return identities + (identities.count..<colors.count).map { _ in UUID() }
    }

    @ViewBuilder
    private func paletteRow(at index: Int) -> some View {
        if index < colors.count {
            HStack(spacing: metrics.controlColumnSpacing) {
                ColorPickerWithHex("", selection: colorBinding(at: index))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    removeColor(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.count > minColors ? Color.text3 : Color.text3.opacity(0.3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(colors.count <= minColors)
                .accessibilityLabel("Remove colour")
            }
        }
    }

    private func syncIdentitiesToColors() {
        while identities.count < colors.count { identities.append(UUID()) }
        if identities.count > colors.count {
            identities.removeLast(identities.count - colors.count)
        }
    }

    private func appendColor() {
        colors.append(defaultNewColor)
        identities.append(UUID())
    }

    private func removeColor(at index: Int) {
        guard colors.count > minColors, index < colors.count else { return }
        colors.remove(at: index)
        if index < identities.count {
            identities.remove(at: index)
        }
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
