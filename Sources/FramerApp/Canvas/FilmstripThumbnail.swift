import SwiftUI
import FramerCore

struct FilmstripThumbnail: View {
    @Environment(AppState.self) var appState
    let item: PhotoItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color.surface3
            AsyncThumbnail(url: item.url)
                .rotationEffect(.degrees(Double(item.rotation)))
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(isSelected ? 1.0 : isHovered ? 0.85 : 0.7)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accent, lineWidth: isSelected ? 1.5 : 0)
        )
        .shadow(color: isSelected ? Color.accent.opacity(0.25) : .clear, radius: 8)
            .onHover { isHovered = $0 }
            .contextMenu {
                Button {
                    appState.rotateItem(item.id, clockwise: true)
                } label: {
                    Label("Rotate Right", systemImage: "rotate.right")
                }
                Button {
                    appState.rotateItem(item.id, clockwise: false)
                } label: {
                    Label("Rotate Left", systemImage: "rotate.left")
                }
                Divider()
                Button(role: .destructive) {
                    withAnimation {
                        appState.library.removeAll { $0.id == item.id }
                        appState.selectedItems.remove(item.id)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
    }
}
