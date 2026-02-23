import SwiftUI
import FramerCore

@main
struct FramerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            FramerCommands(appState: appState)
        }

        Settings {
            PreferencesView()
        }
    }
}
