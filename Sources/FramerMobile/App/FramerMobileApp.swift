import SwiftUI
import FramerCore

@main
struct FramerMobileApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
