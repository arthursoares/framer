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

    @State private var identities: [UUID]

    init(
        colors: Binding<[CodableColor]>,
        maxColors: Int = 16,
        minColors: Int = 1,
        defaultNewColor: CodableColor = .white
    ) {
        self._colors = colors
        self.maxColors = maxColors
        self.minColors = minColors
        self.defaultNewColor = defaultNewColor
        // Pre-populate identities at init time so the first body render
        // already has stable IDs. Without this, `identities` would be empty
        // on the first render, the pure `resolvedIdentities` below would
        // return `[]`, the ForEach would render zero rows for one frame,
        // then `.onAppear` would populate identities and a second render
        // would flash the palette in. The init path avoids the flash by
        // giving the first render matching IDs.
        self._identities = State(initialValue: colors.wrappedValue.map { _ in UUID() })
    }

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
        .onChange(of: colors.count) { _, _ in syncIdentitiesToColors() }
    }

    /// Pure accessor: returns whatever IDs are currently stored, truncated to
    /// `colors.count` if the stored array is longer. Critically this does NOT
    /// mint fresh UUIDs when `identities.count < colors.count` — doing so
    /// inside `body` causes every render to hand ForEach a different ID for
    /// the trailing rows, which flickers the ColorPicker instances between
    /// frames. Instead, the missing IDs are added by `syncIdentitiesToColors()`
    /// via `.onChange`, and any new rows render one frame later.
    private var resolvedIdentities: [UUID] {
        Array(identities.prefix(colors.count))
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
