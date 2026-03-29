import SwiftUI
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        LivePreviewPanel()
    }
}
