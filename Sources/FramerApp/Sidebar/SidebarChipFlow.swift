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
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                content(item)
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }
}

/// Flow layout used by `SidebarChipFlow`. Named `SidebarFlowLayout` to avoid
/// collision with the unrelated `FlowLayout` that existed inside
/// `LayerListSection.swift`.
struct SidebarFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return computeLayout(maxWidth: maxWidth, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = computeLayout(maxWidth: bounds.width, subviews: subviews)
        for (index, origin) in layout.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
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
