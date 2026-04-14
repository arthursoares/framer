import XCTest
@testable import Framer

final class SidebarMetricsTests: XCTestCase {
    func test_defaultMetrics_matchApprovedSidebarRhythm() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.outerInset, 12)
        XCTAssertEqual(metrics.rowGap, 16)
        XCTAssertEqual(metrics.expandedBodyInset, 8)
        XCTAssertEqual(metrics.footerSpacing, 0)
    }

    func test_defaultMetrics_useApprovedSidebarWidthPolicy() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.widthPolicy, .default)
    }

    func test_metrics_delegateWidthClampingToProvidedPolicy() {
        let customPolicy = SidebarLayoutPolicy(
            minimumWidth: 280,
            idealWidth: 300,
            maximumWidth: 340
        )
        let metrics = SidebarMetrics(widthPolicy: customPolicy)

        XCTAssertEqual(metrics.clampedWidth(for: 260), 280)
        XCTAssertEqual(metrics.clampedWidth(for: 360), 340)
    }
}
