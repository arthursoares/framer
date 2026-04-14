import CoreGraphics

struct SidebarMetrics: Sendable, Equatable {
    let outerInset: CGFloat
    let rowGap: CGFloat
    let expandedBodyInset: CGFloat
    let footerSpacing: CGFloat
    let widthPolicy: SidebarLayoutPolicy

    init(
        widthPolicy: SidebarLayoutPolicy = .default,
        outerInset: CGFloat = 12,
        rowGap: CGFloat = 16,
        expandedBodyInset: CGFloat = 8,
        footerSpacing: CGFloat = 0
    ) {
        self.widthPolicy = widthPolicy
        self.outerInset = outerInset
        self.rowGap = rowGap
        self.expandedBodyInset = expandedBodyInset
        self.footerSpacing = footerSpacing
    }

    var minimumWidth: CGFloat { widthPolicy.minimumWidth }
    var idealWidth: CGFloat { widthPolicy.idealWidth }
    var maximumWidth: CGFloat { widthPolicy.maximumWidth }

    func clampedWidth(for proposedWidth: CGFloat) -> CGFloat {
        widthPolicy.clampedWidth(for: proposedWidth)
    }

    func replacing(widthPolicy: SidebarLayoutPolicy) -> SidebarMetrics {
        SidebarMetrics(
            widthPolicy: widthPolicy,
            outerInset: outerInset,
            rowGap: rowGap,
            expandedBodyInset: expandedBodyInset,
            footerSpacing: footerSpacing
        )
    }
}
