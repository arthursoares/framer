import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            LivePreviewPanel()
        } detail: {
            SettingsPanel()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 700)
    }
}
