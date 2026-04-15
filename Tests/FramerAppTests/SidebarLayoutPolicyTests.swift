import XCTest
@testable import Framer

final class SidebarLayoutPolicyTests: XCTestCase {
    func test_defaultPolicy_matchesApprovedWidthBand() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.minimumWidth, 300)
        XCTAssertEqual(policy.idealWidth, 350)
        XCTAssertEqual(policy.maximumWidth, 520)
    }

    func test_clampedWidth_belowMinimum_returnsMinimumWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.clampedWidth(for: 280), 300)
    }

    func test_clampedWidth_atIdealWidth_returnsIdealWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.clampedWidth(for: 350), 350)
    }

    func test_clampedWidth_aboveMaximum_returnsMaximumWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.clampedWidth(for: 600), 520)
    }

    func test_clampedSidebarWidth_belowMinimumProposal_returnsMinimumWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(
            policy.clampedSidebarWidth(forTotalWidth: 900, dividerThickness: 1, proposedWidth: 240),
            300
        )
    }

    func test_clampedSidebarWidth_aboveMaximumProposal_returnsMaximumWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(
            policy.clampedSidebarWidth(forTotalWidth: 1200, dividerThickness: 1, proposedWidth: 640),
            520
        )
    }

    func test_clampedSidebarWidth_usesAvailableWidthWhenWindowIsNarrowerThanMinimum() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(
            policy.clampedSidebarWidth(forTotalWidth: 240, dividerThickness: 1, proposedWidth: policy.idealWidth),
            239
        )
    }

    func test_dividerPosition_usesClampedSidebarWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(
            policy.dividerPosition(forTotalWidth: 1000, dividerThickness: 1, proposedSidebarWidth: 640),
            479
        )
    }

    func test_adjustedDividerPosition_returnsNil_whenCurrentSidebarWidthIsWithinBounds() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertNil(
            policy.adjustedDividerPosition(forTotalWidth: 1000, dividerThickness: 1, currentSidebarWidth: 350)
        )
    }

    func test_adjustedDividerPosition_clampsSidebarWidthBelowMinimum() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(
            policy.adjustedDividerPosition(forTotalWidth: 900, dividerThickness: 1, currentSidebarWidth: 240),
            599
        )
    }

    func test_adjustedDividerPosition_returnsNil_whenWindowIsNarrowerThanMinimumButAlreadyAtAvailableWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertNil(
            policy.adjustedDividerPosition(forTotalWidth: 240, dividerThickness: 1, currentSidebarWidth: 239)
        )
    }
}
