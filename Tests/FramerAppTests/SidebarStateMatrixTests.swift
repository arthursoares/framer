import XCTest
@testable import Framer

final class SidebarStateMatrixTests: XCTestCase {
    func test_canonicalStates_matchApprovedSidebarMatrixInOrder() {
        XCTAssertEqual(
            SidebarStateMatrix.canonicalStates,
            [
                SidebarState.default,
                SidebarState.hover,
                SidebarState.expanded,
                SidebarState.selectedCurrent,
                SidebarState.disabled,
                SidebarState.dragging,
                SidebarState.dropTarget,
                SidebarState.focus,
            ]
        )
    }

    func test_canonicalStateNames_matchApprovedSidebarVocabulary() {
        XCTAssertEqual(
            SidebarStateMatrix.canonicalStates.map { $0.rawValue },
            ["default", "hover", "expanded", "selectedCurrent", "disabled", "dragging", "dropTarget", "focus"]
        )
    }
}
