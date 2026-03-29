import SwiftUI
import FramerCore

@main
struct FramerApp: App {
    @State private var appState = AppState()

    init() {
        registerBundledFonts()
    }

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

    /// Registers all .ttf and .otf fonts found in the app bundle's Resources.
    private func registerBundledFonts() {
        let extensions = ["ttf", "otf"]
        for ext in extensions {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
