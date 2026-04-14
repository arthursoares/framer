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

    func test_stateStyleCatalog_coversApprovedSidebarMatrix() {
        XCTAssertEqual(
            SidebarStateMatrix.canonicalStates.map(SidebarStateStyle.style(for:)),
            [
                .default,
                .hover,
                .expanded,
                .selectedCurrent,
                .disabled,
                .dragging,
                .dropTarget,
                .focus,
            ]
        )
    }

    func test_stateStyles_captureApprovedSidebarChassisDecisions() {
        XCTAssertEqual(
            SidebarStateStyle.default,
            SidebarStateStyle(
                background: .clear,
                border: .clear,
                foreground: .primary,
                opacity: 1
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.hover,
            SidebarStateStyle(
                background: .raisedSurface,
                border: .standard,
                foreground: .primary,
                opacity: 1
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.expanded,
            SidebarStateStyle(
                background: .raisedSurface,
                border: .standard,
                foreground: .primary,
                opacity: 1
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.selectedCurrent,
            SidebarStateStyle(
                background: .accentedSurface,
                border: .accent,
                foreground: .accent,
                opacity: 1
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.disabled,
            SidebarStateStyle(
                background: .clear,
                border: .clear,
                foreground: .secondary,
                opacity: 0.65
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.dragging,
            SidebarStateStyle(
                background: .raisedSurface,
                border: .active,
                foreground: .secondary,
                opacity: 0.72
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.dropTarget,
            SidebarStateStyle(
                background: .accentGlow,
                border: .accent,
                foreground: .primary,
                opacity: 1
            )
        )
        XCTAssertEqual(
            SidebarStateStyle.focus,
            SidebarStateStyle(
                background: .raisedSurface,
                border: .active,
                foreground: .primary,
                opacity: 1
            )
        )
    }
}
