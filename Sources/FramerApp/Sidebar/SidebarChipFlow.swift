import SwiftUI

/// Wrapping grid of chips bounded to `metrics.containedPreviewMaxWidth`. Used
/// for caption template tokens, ASCII ramp glyphs, tag-like pickers. Replaces
/// inline ad-hoc `FlowLayout` implementations across the editor codebase.
struct SidebarChipFlow<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Hashable {
    @Environment(\.sidebarMetrics) private var metrics
    private let items: Data
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        items: Data,
        spacing: CGFloat = 4,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        SidebarFlowLayout(horizontalSpacing: spacing, verticalSpacing: spacing) {
            // Key ForEach by element identity (Hashable) not array offset so
            // inserting or removing a chip mid-list doesn't force SwiftUI to
            // discard and rebuild every chip at or after the changed index.
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }
}

/// Flow layout used by `SidebarChipFlow`. Named `SidebarFlowLayout` to avoid
/// collision with the unrelated `FlowLayout` that existed inside
/// `LayerListSection.swift`.
///
/// Uses SwiftUI's `Layout.Cache` to compute placement once per layout pass
/// (keyed by proposed width) and reuse it between `sizeThatFits` and
/// `placeSubviews`. Without the cache, both methods would re-walk the
/// subview list — meaningful cost for the caption token bar which can have
/// 12+ chips.
struct SidebarFlowLayout: Layout {
    struct CacheEntry {
        let maxWidth: CGFloat
        let subviewCount: Int
        let size: CGSize
        let origins: [CGPoint]
    }

    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func makeCache(subviews: Subviews) -> CacheEntry? {
        nil
    }

    func updateCache(_ cache: inout CacheEntry?, subviews: Subviews) {
        // Invalidate the cache when the subview count changes; width changes
        // are picked up inside `cached(...)` via the maxWidth comparison.
        if let entry = cache, entry.subviewCount != subviews.count {
            cache = nil
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheEntry?) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return cached(maxWidth: maxWidth, subviews: subviews, cache: &cache).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheEntry?) {
        let entry = cached(maxWidth: bounds.width, subviews: subviews, cache: &cache)
        for (index, origin) in entry.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func cached(maxWidth: CGFloat, subviews: Subviews, cache: inout CacheEntry?) -> CacheEntry {
        if let entry = cache, entry.maxWidth == maxWidth, entry.subviewCount == subviews.count {
            return entry
        }
        let layout = computeLayout(maxWidth: maxWidth, subviews: subviews)
        let entry = CacheEntry(
            maxWidth: maxWidth,
            subviewCount: subviews.count,
            size: layout.size,
            origins: layout.origins
        )
        cache = entry
        return entry
    }

    private func computeLayout(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            totalWidth = max(totalWidth, x - horizontalSpacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), origins)
    }
}
