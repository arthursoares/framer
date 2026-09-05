import SwiftUI
import FramerCore

// MARK: - Orientation Controls

struct OrientationControls: View {
    var params: OrientationLayerParams
    var onChange: (OrientationLayerParams) -> Void

    var body: some View {
        ControlRow(label: "Target Orientation") {
            Picker("", selection: Binding(
                get: { params.target },
                set: { var p = params; p.target = $0; onChange(p) }
            )) {
                ForEach(OrientationTarget.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

