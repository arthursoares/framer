import SwiftUI
import FramerCore

// MARK: - Resize Controls

struct ResizeControls: View {
    var params: ResizeLayerParams
    var onChange: (ResizeLayerParams) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ControlRow(label: "Max Width") {
                TextField("", value: Binding(
                    get: { params.maxWidth },
                    set: { var p = params; p.maxWidth = $0; onChange(p) }
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
            }
            ControlRow(label: "Max Height") {
                TextField("", value: Binding(
                    get: { params.maxHeight },
                    set: { var p = params; p.maxHeight = $0; onChange(p) }
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
            }
        }
    }
}

