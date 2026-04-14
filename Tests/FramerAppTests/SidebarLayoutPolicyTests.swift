import XCTest
@testable import Framer

final class SidebarLayoutPolicyTests: XCTestCase {
    func test_defaultPolicy_matchesApprovedWidthBand() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.minimumWidth, 304)
        XCTAssertEqual(policy.idealWidth, 320)
        XCTAssertEqual(policy.maximumWidth, 352)
    }

    func test_clampedWidth_belowMinimum_returnsMinimumWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.clampedWidth(for: 280), 304)
    }

    func test_clampedWidth_atIdealWidth_returnsIdealWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.clampedWidth(for: 320), 320)
    }

    func test_clampedWidth_aboveMaximum_returnsMaximumWidth() {
        let policy = SidebarLayoutPolicy.default

        XCTAssertEqual(policy.clampedWidth(for: 400), 352)
    }
}
