import SwiftUI
import FramerCore

@main
struct FramerMobileApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        if let config = AppE2ETestConfiguration.load() {
            state.applyE2ETestConfiguration(config)
        }
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
