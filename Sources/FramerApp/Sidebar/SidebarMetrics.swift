import CoreGraphics

struct SidebarMetrics: Sendable, Equatable {
    let outerInset: CGFloat
    let rowGap: CGFloat
    let expandedBodyInset: CGFloat
    let footerSpacing: CGFloat
    let controlRowMinHeight: CGFloat
    let controlLabelWidth: CGFloat
    let controlColumnSpacing: CGFloat
    let controlTrailingValueWidth: CGFloat
    let controlStackSpacing: CGFloat
    let widthPolicy: SidebarLayoutPolicy

    init(
        widthPolicy: SidebarLayoutPolicy = .default,
        outerInset: CGFloat = 12,
        rowGap: CGFloat = 16,
        expandedBodyInset: CGFloat = 6,
        footerSpacing: CGFloat = 0,
        controlRowMinHeight: CGFloat = 30,
        controlLabelWidth: CGFloat = 104,
        controlColumnSpacing: CGFloat = 10,
        controlTrailingValueWidth: CGFloat = 48,
        controlStackSpacing: CGFloat = 0
    ) {
        self.widthPolicy = widthPolicy
        self.outerInset = outerInset
        self.rowGap = rowGap
        self.expandedBodyInset = expandedBodyInset
        self.footerSpacing = footerSpacing
        self.controlRowMinHeight = controlRowMinHeight
        self.controlLabelWidth = controlLabelWidth
        self.controlColumnSpacing = controlColumnSpacing
        self.controlTrailingValueWidth = controlTrailingValueWidth
        self.controlStackSpacing = controlStackSpacing
    }

    var minimumWidth: CGFloat { widthPolicy.minimumWidth }
    var idealWidth: CGFloat { widthPolicy.idealWidth }
    var maximumWidth: CGFloat { widthPolicy.maximumWidth }
    var controlStackDividerInset: CGFloat { outerInset }
    var controlStackDividerThickness: CGFloat { 1 }

    func clampedWidth(for proposedWidth: CGFloat) -> CGFloat {
        widthPolicy.clampedWidth(for: proposedWidth)
    }

    func replacing(widthPolicy: SidebarLayoutPolicy) -> SidebarMetrics {
        SidebarMetrics(
            widthPolicy: widthPolicy,
            outerInset: outerInset,
            rowGap: rowGap,
            expandedBodyInset: expandedBodyInset,
            footerSpacing: footerSpacing,
            controlRowMinHeight: controlRowMinHeight,
            controlLabelWidth: controlLabelWidth,
            controlColumnSpacing: controlColumnSpacing,
            controlTrailingValueWidth: controlTrailingValueWidth,
            controlStackSpacing: controlStackSpacing
        )
    }
}
