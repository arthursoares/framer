import Foundation
import CoreGraphics

struct SidebarLayoutPolicy: Sendable, Equatable {
    let minimumWidth: CGFloat
    let idealWidth: CGFloat
    let maximumWidth: CGFloat

    static let `default` = SidebarLayoutPolicy(
        minimumWidth: 304,
        idealWidth: 320,
        maximumWidth: 352
    )

    func clampedWidth(for proposedWidth: CGFloat) -> CGFloat {
        min(max(proposedWidth, minimumWidth), maximumWidth)
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
