import SwiftUI
import FramerCore

struct BottomPanel: View {
    @Environment(AppState.self) var appState
    let presetCache: PresetPreviewCache

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Divider
            Rectangle().fill(Color.borderDefault).frame(height: 1)

            // Mode tabs
            BottomModeTabs(selection: $appState.activeTab)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Content
            switch appState.activeTab {
            case .presets:
                PresetStrip(cache: presetCache)
                    .padding(.vertical, 12)
            case .layers:
                LayerStrip()
                    .padding(.vertical, 12)
            }
        }
        .background(Color.surface1.ignoresSafeArea(.container, edges: .bottom))
    }
}

struct BottomModeTabs: View {
    @Binding var selection: BottomTab

    var body: some View {
        HStack(spacing: 0) {
            MobileModeTabButton(
                title: "Presets",
                isSelected: selection == .presets,
                action: { selection = .presets }
            )
            MobileModeTabButton(
                title: "Layers",
                isSelected: selection == .layers,
                action: { selection = .layers }
            )
        }
    }
}

struct MobileModeTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accent : Color.text3)
                Rectangle()
                    .fill(isSelected ? Color.accent : .clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
