import SwiftUI
import AppKit
import FramerCore

struct ResizeLayerControls: View {
    var params: ResizeLayerParams
    var onChange: (ResizeLayerParams) -> Void

    var body: some View {
        SidebarCompoundControlBlock {
            SidebarControlRow("Max Width") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: maxWidthBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Max Width")
                        .monospacedDigit()
                }
            }
        } secondary: {
            SidebarControlRow("Max Height") {
                EmptyView()
            } trailingValue: {
                SidebarTrailingUnitCluster(unit: "px") {
                    TextField("", value: maxHeightBinding, format: .number)
                        .simpleLayerEditorInputStyle(accessibilityLabel: "Max Height")
                        .monospacedDigit()
                }
            }
        }
    }

    private var maxWidthBinding: Binding<Int> {
        Binding(
            get: { params.maxWidth },
            set: {
                var p = params
                p.maxWidth = $0
                onChange(p)
            }
        )
    }

    private var maxHeightBinding: Binding<Int> {
        Binding(
            get: { params.maxHeight },
            set: {
                var p = params
                p.maxHeight = $0
                onChange(p)
            }
        )
    }
}

// MARK: - AspectRatioLayerControls

