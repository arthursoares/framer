import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 0) {
            CanvasView()
            InspectorView()
                .frame(width: 280)
        }
        .frame(minWidth: 900, minHeight: 650)
    }
}
