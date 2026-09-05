import SwiftUI
import AppKit
import FramerCore

struct LayerFillPicker: View {
    var fill: LayerFill
    var onChange: (LayerFill) -> Void

    private static let signedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarControlRow("Fill") {
                Picker("Fill", selection: fillModeBinding) {
                    Text("Solid Color").tag(0)
                    Text("Dominant Color").tag(1)
                    Text("Linear Gradient").tag(2)
                    Text("Radial Gradient").tag(3)
                }
                .labelsHidden()
            }

            if case .color(let c) = fill {
                SimpleLayerEditorDivider()

                labeledColorPicker("Fill Color", selection: Binding(
                    get: { Color(nsColor: NSColor(cgColor: c.cgColor) ?? .white) },
                    set: { newColor in
                        guard let hex = newColor.hexString else { return }
                        guard let codable = try? CodableColor(hex: hex) else { return }
                        onChange(.color(codable))
                    }
                ))
            }

            if let params = fill.gradientParams {
                SimpleLayerEditorDivider()

                SidebarCompoundControlBlock {
                    SidebarControlRow("Saturation") {
                        Slider(value: saturationBinding(params), in: -50...50)
                            .tint(Color.accentDim)
                    } trailingValue: {
                        SidebarTrailingUnitCluster(unit: "") {
                            TextField("", value: saturationBinding(params), formatter: Self.signedFormatter)
                                .simpleLayerEditorInputStyle(accessibilityLabel: "Saturation")
                                .monospacedDigit()
                        }
                    }
                } secondary: {
                    SidebarControlRow("Brightness") {
                        Slider(value: lightnessBinding(params), in: -50...50)
                            .tint(Color.accentDim)
                    } trailingValue: {
                        SidebarTrailingUnitCluster(unit: "") {
                            TextField("", value: lightnessBinding(params), formatter: Self.signedFormatter)
                                .simpleLayerEditorInputStyle(accessibilityLabel: "Brightness")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var fillModeBinding: Binding<Int> {
        Binding(
            get: {
                switch fill {
                case .color: return 0
                case .dominantColor: return 1
                case .gradientLinear: return 2
                case .gradientRadial: return 3
                }
            },
            set: { idx in
                // Preserve existing gradient params when switching between gradient types
                let existingParams = fill.gradientParams ?? GradientParams()
                switch idx {
                case 0: onChange(.color(.white))
                case 1: onChange(.dominantColor(existingParams))
                case 2: onChange(.gradientLinear(existingParams))
                case 3: onChange(.gradientRadial(existingParams))
                default: break
                }
            }
        )
    }

    private func saturationBinding(_ params: GradientParams) -> Binding<Double> {
        Binding(
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
        )
    }

    private func lightnessBinding(_ params: GradientParams) -> Binding<Double> {
        Binding(
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
        )
    }
}

// MARK: - CaptionLayerControls

