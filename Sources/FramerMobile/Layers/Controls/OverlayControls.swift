import SwiftUI
import FramerCore

// MARK: - Overlay Controls

struct OverlayControls: View {
    var params: OverlayLayerParams
    var onChange: (OverlayLayerParams) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ControlRow(label: "Category") {
                Picker("", selection: Binding(
                    get: { params.kind },
                    set: { var p = params; p.kind = $0; p.overlayName = ""; onChange(p) }
                )) {
                    Text("Frames").tag(OverlayKind.frame)
                    Text("Dust").tag(OverlayKind.dust)
                    Text("Light Leaks").tag(OverlayKind.lightLeak)
                    Text("Wet Plate").tag(OverlayKind.wetPlate)
                }
                .pickerStyle(.menu)
            }

            ControlRow(label: "Overlay") {
                let overlays = TextureFrameProvider.overlays(ofKind: params.kind)
                Picker("", selection: Binding(
                    get: { params.overlayName },
                    set: { var p = params; p.overlayName = $0; onChange(p) }
                )) {
                    Text("None").tag("")
                    ForEach(overlays, id: \.id) { overlay in
                        Text(overlay.displayName).tag(overlay.id)
                    }
                }
                .pickerStyle(.menu)
            }

            ControlRow(label: "Opacity") {
                HStack {
                    Slider(value: Binding(
                        get: { params.opacity },
                        set: { var p = params; p.opacity = $0; onChange(p) }
                    ), in: 0...100)
                    Text("\(Int(params.opacity))%")
                        .font(AppFont.mono(12))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            ControlRow(label: "Blend Mode") {
                Picker("", selection: Binding(
                    get: { params.blendMode },
                    set: { var p = params; p.blendMode = $0; onChange(p) }
                )) {
                    ForEach(OverlayBlendMode.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

