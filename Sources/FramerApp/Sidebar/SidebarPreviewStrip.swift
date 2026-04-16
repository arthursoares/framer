import SwiftUI

/// Horizontally scrolling tile strip bounded to `metrics.containedPreviewMaxWidth`.
/// Used for Overlay library, LUT library, and any future thumbnail-picker
/// affordance. Callers supply the tile size + content builder.
struct SidebarPreviewStrip<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
    @Environment(\.sidebarMetrics) private var metrics
    private let items: Data
    private let tileSize: CGFloat
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        items: Data,
        tileSize: CGFloat = 72,
        spacing: CGFloat? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.tileSize = tileSize
        self.spacing = spacing ?? 6
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                        .frame(width: tileSize, height: tileSize)
                }
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }
}
