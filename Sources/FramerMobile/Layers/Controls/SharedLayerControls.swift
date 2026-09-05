import SwiftUI
import FramerCore

/// Mobile blend-mode + opacity picker used by every visual adjustment
/// layer's inspector. Mirrors `BlendModeControls` on the desktop.
struct MobileBlendModeControls: View {
    @Binding var blendMode: LayerBlendMode
    @Binding var opacity: Double

    var body: some View {
        ControlRow(label: "Blend") {
            Picker("", selection: $blendMode) {
                ForEach(LayerBlendMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        ControlRow(label: "Opacity (\(Int((opacity * 100).rounded()))%)") {
            Slider(value: $opacity, in: 0...1, step: 0.01)
        }
    }
}


// MARK: - Shared Helpers

struct ControlRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    /// Snap increment — mirrors the desktop sidebar's 0.05 step so both
    /// platforms store the same precision. nil = continuous.
    var step: Double? = nil
    /// Double-tapping the row resets to this value (the parameter's
    /// canonical default from GPUEffectKind.defaultParameters()).
    var resetValue: Double? = nil

    /// Narrow ranges (0...1, 0.2...2, …) are fractional parameters — an
    /// integer readout would render every value as "0" or "1". Wide ranges
    /// (angles, counts, sizes) read better as whole numbers.
    private var formattedValue: String {
        if range.upperBound - range.lowerBound <= 10 {
            return String(format: "%.2f", value)
        }
        return "\(Int(value))"
    }

    var body: some View {
        ControlRow(label: label) {
            HStack {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text("\(formattedValue)\(unit)")
                    .font(AppFont.mono(12))
                    .foregroundStyle(Color.text1)
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .onTapGesture(count: 2) {
            if let resetValue {
                value = min(range.upperBound, max(range.lowerBound, resetValue))
            }
        }
    }
}


// MARK: - Fill Picker (shared)

struct FillPicker: View {
    var fill: LayerFill
    var onChange: (LayerFill) -> Void

    var body: some View {
        ControlRow(label: "Fill") {
            Picker("", selection: Binding(
                get: {
                    switch fill {
                    case .color: return 0
                    case .dominantColor: return 1
                    case .gradientLinear: return 2
                    case .gradientRadial: return 3
                    }
                },
                set: { idx in
                    let existing = fill.gradientParams ?? GradientParams()
                    switch idx {
                    case 0: onChange(.color(.white))
                    case 1: onChange(.dominantColor(existing))
                    case 2: onChange(.gradientLinear(existing))
                    case 3: onChange(.gradientRadial(existing))
                    default: break
                    }
                }
            )) {
                Text("Solid").tag(0)
                Text("Dominant").tag(1)
                Text("Linear").tag(2)
                Text("Radial").tag(3)
            }
            .pickerStyle(.segmented)
        }

        if case .color(let c) = fill {
            ControlRow(label: "Color") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: c.cgColor) },
                    set: { newColor in
                        guard let hex = newColor.hexString, let codable = try? CodableColor(hex: hex) else { return }
                        onChange(.color(codable))
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Fill Color")
            }
        }

        if let params = fill.gradientParams {
            ControlRow(label: "Saturation") {
                HStack {
                    Slider(value: Binding(
                        get: { params.saturationShift },
                        set: { val in
                            let newParams = GradientParams(saturationShift: val, lightnessShift: params.lightnessShift)
                            switch fill {
                            case .dominantColor: onChange(.dominantColor(newParams))
                            case .gradientLinear: onChange(.gradientLinear(newParams))
                            case .gradientRadial: onChange(.gradientRadial(newParams))
                            default: break
                            }
                        }
                    ), in: -50...50)
                    Text("\(Int(params.saturationShift))")
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }

            ControlRow(label: "Brightness") {
                HStack {
                    Slider(value: Binding(
                        get: { params.lightnessShift },
                        set: { val in
                            let newParams = GradientParams(saturationShift: params.saturationShift, lightnessShift: val)
                            switch fill {
                            case .dominantColor: onChange(.dominantColor(newParams))
                            case .gradientLinear: onChange(.gradientLinear(newParams))
                            case .gradientRadial: onChange(.gradientRadial(newParams))
                            default: break
                            }
                        }
                    ), in: -50...50)
                    Text("\(Int(params.lightnessShift))")
                        .font(AppFont.mono(12))
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}


// MARK: - Saved palettes row

/// "Saved" palettes row: apply a stored user palette, save the current
/// colours under a name, or delete stored palettes. Backed by
/// UserPaletteStore — the same file the desktop UserPaletteMenu reads, so
/// palettes are shared across editors (and across devices if the container
/// syncs). Used by the Dither palette editor and the GPU-effect palette
/// colour mode above.
struct MobileUserPaletteRow: View {
    var currentColors: [CodableColor]
    var onApply: ([CodableColor]) -> Void

    @State private var palettes: [UserPalette] = []
    @State private var showingSavePrompt = false
    @State private var saveName = ""

    private let store = UserPaletteStore()

    var body: some View {
        ControlRow(label: "Saved") {
            Menu {
                if palettes.isEmpty {
                    Text("No Saved Palettes")
                } else {
                    ForEach(palettes) { palette in
                        Button(palette.name) { onApply(palette.colors) }
                    }
                }
                Divider()
                Button("Save Current Palette…") {
                    saveName = ""
                    showingSavePrompt = true
                }
                if !palettes.isEmpty {
                    Menu("Delete Palette") {
                        ForEach(palettes) { palette in
                            Button(palette.name, role: .destructive) {
                                try? store.delete(id: palette.id)
                                palettes = store.list()
                            }
                        }
                    }
                }
            } label: {
                Label("Saved Palettes", systemImage: "swatchpalette")
            }
        }
        .onAppear { palettes = store.list() }
        .alert("Save Palette", isPresented: $showingSavePrompt) {
            TextField("Name", text: $saveName)
            Button("Save") {
                let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try? store.save(UserPalette(name: trimmed, colors: currentColors))
                palettes = store.list()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current \(currentColors.count) colours for reuse in any palette editor.")
        }
    }
}
