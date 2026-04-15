import Foundation
import CoreGraphics

struct SidebarLayoutPolicy: Sendable, Equatable {
    let minimumWidth: CGFloat
    let idealWidth: CGFloat
    let maximumWidth: CGFloat

    static let `default` = SidebarLayoutPolicy(
        minimumWidth: 300,
        idealWidth: 350,
        maximumWidth: 520
    )

    func clampedWidth(for proposedWidth: CGFloat) -> CGFloat {
        min(max(proposedWidth, minimumWidth), maximumWidth)
    }

    func clampedSidebarWidth(forTotalWidth totalWidth: CGFloat, dividerThickness: CGFloat, proposedWidth: CGFloat) -> CGFloat {
        let availableWidth = max(totalWidth - dividerThickness, 0)
        return min(clampedWidth(for: proposedWidth), availableWidth)
    }

    func dividerPosition(forTotalWidth totalWidth: CGFloat, dividerThickness: CGFloat, proposedSidebarWidth: CGFloat) -> CGFloat {
        let sidebarWidth = clampedSidebarWidth(
            forTotalWidth: totalWidth,
            dividerThickness: dividerThickness,
            proposedWidth: proposedSidebarWidth
        )
        return max(0, totalWidth - sidebarWidth - dividerThickness)
    }

    func adjustedDividerPosition(forTotalWidth totalWidth: CGFloat, dividerThickness: CGFloat, currentSidebarWidth: CGFloat) -> CGFloat? {
        let clampedSidebarWidth = clampedSidebarWidth(
            forTotalWidth: totalWidth,
            dividerThickness: dividerThickness,
            proposedWidth: currentSidebarWidth
        )

        guard abs(clampedSidebarWidth - currentSidebarWidth) > 0.5 else {
            return nil
        }

        return max(0, totalWidth - clampedSidebarWidth - dividerThickness)
    }
}

enum SidebarState: String, CaseIterable, Sendable {
    case `default`
    case hover
    case expanded
    case selectedCurrent
    case disabled
    case dragging
    case dropTarget
    case focus
}

enum SidebarStateMatrix {
    static let canonicalStates: [SidebarState] = SidebarState.allCases
    static let canonicalStateSet = Set(canonicalStates)
}
