import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
        } content: {
            switch appState.activeTab {
            case .library:
                LivePreviewPanel()
            case .presets:
                PresetManagerView()
            case .queue:
                ExportQueueView()
            }
        } detail: {
            SettingsPanel()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 700)
    }
}
