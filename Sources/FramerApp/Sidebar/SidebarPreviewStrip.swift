import SwiftUI

/// Horizontally scrolling tile strip bounded to `metrics.containedPreviewMaxWidth`.
/// Used for Overlay library, LUT library, and any future thumbnail-picker
/// affordance. Callers supply the tile size + content builder.
struct SidebarPreviewStrip<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
    @Environment(\.sidebarMetrics) private var metrics
    private let items: Data
    private let tileWidth: CGFloat?
    private let tileHeight: CGFloat?
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        items: Data,
        tileWidth: CGFloat? = 72,
        tileHeight: CGFloat? = 72,
        spacing: CGFloat = 6,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.spacing = spacing
        self.content = content
    }

    /// Convenience initialiser: square tiles.
    init(
        items: Data,
        tileSize: CGFloat,
        spacing: CGFloat = 6,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(
            items: items,
            tileWidth: tileSize,
            tileHeight: tileSize,
            spacing: spacing,
            content: content
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                        .frame(width: tileWidth, height: tileHeight)
                }
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }
}
