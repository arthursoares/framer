import SwiftUI
import AppKit
import FramerCore

struct PaddingLayerControls: View {
    var params: PaddingLayerParams
    var onChange: (PaddingLayerParams) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarControlRow("Thickness") {
                Slider(value: thicknessBinding, in: 0...400)
                    .tint(Color.accentDim)
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: thicknessBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Thickness")
                        .monospacedDigit()
                }
            }

            SimpleLayerEditorDivider()

            LayerFillPicker(fill: params.fill) { newFill in
                var p = params
                p.fill = newFill
                onChange(p)
            }
        }
    }

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: { Double(params.thickness) },
            set: {
                var p = params
                p.thickness = Int($0)
                onChange(p)
            }
        )
    }
}

// MARK: - CanvasLayerControls

