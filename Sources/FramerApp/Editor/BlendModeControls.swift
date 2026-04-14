// BlendModeControls.swift
// Shared inspector section that renders a blend-mode picker + opacity
// slider for any visual adjustment layer. Used from LUTLayerControls,
// DitherLayerControls, ShaderLayerControls, and GPUEffectLayerControls
// so the affordance reads identically across layer types.
//
// The same pair of controls (blendMode: LayerBlendMode, opacity:
// Double ∈ [0,1]) drives `LayerCompositor.compose()` in BorderRenderer's
// dispatch loop — see Sources/FramerCore/Processing/LayerCompositor.swift
// for the composite math.

import SwiftUI
import FramerCore

struct BlendModeControls: View {
    @Binding var blendMode: LayerBlendMode
    @Binding var opacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Blend Mode", selection: $blendMode) {
                // Grouped by tier so the 20 entries don't look like a flat
                // alphabetical dump — mirrors how Photoshop's layer panel
                // separates the families (normal, multiply-group, screen-
                // group, contrast-group, difference-group, hsl-group).
                Group {
                    Text(LayerBlendMode.normal.label).tag(LayerBlendMode.normal)
                    Divider()
                    Text(LayerBlendMode.darken.label).tag(LayerBlendMode.darken)
                    Text(LayerBlendMode.multiply.label).tag(LayerBlendMode.multiply)
                    Text(LayerBlendMode.colorBurn.label).tag(LayerBlendMode.colorBurn)
                    Text(LayerBlendMode.linearBurn.label).tag(LayerBlendMode.linearBurn)
                    Divider()
                    Text(LayerBlendMode.lighten.label).tag(LayerBlendMode.lighten)
                    Text(LayerBlendMode.screen.label).tag(LayerBlendMode.screen)
                    Text(LayerBlendMode.colorDodge.label).tag(LayerBlendMode.colorDodge)
                    Text(LayerBlendMode.linearDodge.label).tag(LayerBlendMode.linearDodge)
                }
                Group {
                    Divider()
                    Text(LayerBlendMode.overlay.label).tag(LayerBlendMode.overlay)
                    Text(LayerBlendMode.softLight.label).tag(LayerBlendMode.softLight)
                    Text(LayerBlendMode.hardLight.label).tag(LayerBlendMode.hardLight)
                    Divider()
                    Text(LayerBlendMode.difference.label).tag(LayerBlendMode.difference)
                    Text(LayerBlendMode.exclusion.label).tag(LayerBlendMode.exclusion)
                    Text(LayerBlendMode.subtract.label).tag(LayerBlendMode.subtract)
                    Text(LayerBlendMode.divide.label).tag(LayerBlendMode.divide)
                    Divider()
                    Text(LayerBlendMode.hue.label).tag(LayerBlendMode.hue)
                    Text(LayerBlendMode.saturation.label).tag(LayerBlendMode.saturation)
                    Text(LayerBlendMode.color.label).tag(LayerBlendMode.color)
                    Text(LayerBlendMode.luminosity.label).tag(LayerBlendMode.luminosity)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Opacity: \(Int((opacity * 100).rounded()))%")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
            }
            Slider(value: $opacity, in: 0...1, step: 0.01)
        }
    }
}
