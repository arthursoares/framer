import SwiftUI
import AppKit
import FramerCore

struct BorderLayerControls: View {
    var params: BorderLayerParams
    var onChange: (BorderLayerParams) -> Void

    @State private var thicknessMode: ThicknessMode = .pixels

    private enum ThicknessMode: String, CaseIterable {
        case pixels = "px"
        case percent = "%"
    }

    init(params: BorderLayerParams, onChange: @escaping (BorderLayerParams) -> Void) {
        self.params = params
        self.onChange = onChange
        _thicknessMode = State(initialValue: Self.thicknessMode(for: params.thickness))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarMetrics().expandedBodyInset) {
            SidebarCompoundControlBlock {
                SidebarControlRow("Mode") {
                    Picker("Thickness Mode", selection: $thicknessMode) {
                        ForEach(ThicknessMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: SidebarMetrics().controlSegmentedModeWidth)
                    .labelsHidden()
                }
            } secondary: {
                SidebarControlRow("Thickness") {
                    Slider(value: thicknessValue, in: thicknessRange)
                        .tint(Color.accentDim)
                } trailingValue: {
                    SidebarTrailingUnitCluster(unit: LocalizedStringKey(thicknessMode.rawValue)) {
                        TextField("", value: thicknessValue, format: .number)
                            .simpleLayerEditorInputStyle(accessibilityLabel: "Thickness")
                            .monospacedDigit()
                    }
                }
            }

            ColorPickerWithHex("", selection: colorBinding)
                .denseControlRow("Color")
        }
        .onChange(of: params.thickness) { _, newThickness in
            thicknessMode = Self.thicknessMode(for: newThickness)
        }
    }

    private static func thicknessMode(for thickness: BorderSize) -> ThicknessMode {
        switch thickness {
        case .pixels:
            .pixels
        case .percent:
            .percent
        }
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
                switch thicknessMode {
                case .pixels: p.thickness = .pixels(Int(val))
                case .percent: p.thickness = .percent(val)
                }
                onChange(p)
            }
        )
    }

    private var thicknessRange: ClosedRange<Double> {
        thicknessMode == .pixels ? 0...300 : 0...20
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: params.color.cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString else { return }
                guard let c = try? CodableColor(hex: hex) else { return }
                var p = params
                p.color = c
                onChange(p)
            }
        )
    }
}

// MARK: - PaddingLayerControls

