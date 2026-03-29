import SwiftUI
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ZStack {
            LivePreviewPanel()

            // Floating filmstrip at bottom
            if !appState.library.isEmpty {
                VStack {
                    Spacer()
                    FilmstripView()
                        .padding(.leading, 14)
                        .padding(.trailing, 294) // clear inspector
                        .padding(.bottom, 14)
                }
            }
        }
    }
}
