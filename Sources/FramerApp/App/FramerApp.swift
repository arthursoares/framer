import SwiftUI
import FramerCore

@main
struct FramerApp: App {
    @State private var appState: AppState

    init() {
        Self.registerBundledFonts()
        let state = AppState()
        if let config = AppE2ETestConfiguration.load() {
            state.applyE2ETestConfiguration(config)
        }
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .commands {
            FramerCommands(appState: appState)
        }

        Settings {
            PreferencesView()
        }
    }

    /// Registers all .ttf and .otf fonts found in the app bundle's Resources.
    private static func registerBundledFonts() {
        let extensions = ["ttf", "otf"]
        for ext in extensions {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
