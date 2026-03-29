import SwiftUI
import FramerCore

struct InspectorView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        SettingsPanel()
    }
}
