import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
        } content: {
            LivePreviewPanel()
        } detail: {
            SettingsPanel()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 700)
    }
}
