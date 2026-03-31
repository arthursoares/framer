import SwiftUI
import FramerCore

struct BottomPanel: View {
    @Environment(AppState.self) var appState
    let presetCache: PresetPreviewCache

    var body: some View {
        VStack(spacing: 0) {
            // Divider
            Rectangle().fill(Color.borderDefault).frame(height: 1)

            // Mode tabs
            HStack(spacing: 0) {
                tabButton("Presets", tab: .presets)
                tabButton("Layers", tab: .layers)
            }
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

    private func tabButton(_ title: String, tab: BottomTab) -> some View {
        let isActive = appState.activeTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.activeTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accent : Color.text3)
                Rectangle()
                    .fill(isActive ? Color.accent : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
