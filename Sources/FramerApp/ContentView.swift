import SwiftUI
import FramerCore

struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            // Top menu bar — spans full width
            TopMenuBar(showOriginal: $showOriginal)

            // Main content
            HStack(spacing: 0) {
                CanvasView(showOriginal: $showOriginal)
                InspectorView()
                    .frame(width: 320)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
    }
}

// MARK: - Top Menu Bar

struct TopMenuBar: View {
    @Environment(AppState.self) var appState
    @Binding var showOriginal: Bool

    var body: some View {
        HStack {
            BeforeAfterToggle(showOriginal: $showOriginal)
                .opacity(appState.selectedPhoto != nil ? 1 : 0)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Color.surface1
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.borderDefault).frame(height: 1)
                }
        }
    }
}
