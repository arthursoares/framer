import SwiftUI
import AppKit
import FramerCore

struct OrientationLayerControls: View {
    var params: OrientationLayerParams
    var onChange: (OrientationLayerParams) -> Void

    var body: some View {
        SidebarControlRow("Target") {
            Picker("Target", selection: targetBinding) {
                ForEach(OrientationTarget.allCases, id: \.self) { target in
                    Text(target.rawValue.capitalized).tag(target)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var targetBinding: Binding<OrientationTarget> {
        Binding(
            get: { params.target },
            set: {
                var p = params
                p.target = $0
                onChange(p)
            }
        )
    }
}

// MARK: - OverlayLayerControls

