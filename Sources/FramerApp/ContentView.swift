import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            LibrarySidebar()
        } content: {
            VStack(spacing: 0) {
                Picker("", selection: $state.activeTab) {
                    Label("Library", systemImage: "photo.on.rectangle").tag(AppState.Tab.library)
                    Label("Presets", systemImage: "slider.horizontal.3").tag(AppState.Tab.presets)
                    Label("Queue", systemImage: "tray").tag(AppState.Tab.queue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .labelsHidden()

                Divider()

                switch appState.activeTab {
                case .library:
                    LivePreviewPanel()
                case .presets:
                    PresetManagerView()
                case .queue:
                    ExportQueueView()
                }
            }
        } detail: {
            SettingsPanel()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 700)
    }
}
