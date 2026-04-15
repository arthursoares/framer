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
}
