import SwiftUI
import FramerCore

struct FilmstripThumbnail: View {
    let item: PhotoItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        AsyncThumbnail(url: item.url)
            .frame(width: 48, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .rotationEffect(.degrees(Double(item.rotation)))
            .opacity(isSelected ? 1.0 : isHovered ? 0.85 : 0.55)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accent, lineWidth: isSelected ? 1.5 : 0)
            )
            .shadow(color: isSelected ? Color.accent.opacity(0.25) : .clear, radius: 8)
            .onHover { isHovered = $0 }
    }
}
