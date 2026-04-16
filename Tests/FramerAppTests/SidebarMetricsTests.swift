import XCTest
@testable import Framer

final class SidebarMetricsTests: XCTestCase {
    func test_defaultMetrics_matchApprovedSidebarRhythm() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.outerInset, 12)
        XCTAssertEqual(metrics.rowGap, 16)
        XCTAssertEqual(metrics.expandedBodyInset, 6)
        XCTAssertEqual(metrics.footerSpacing, 0)
    }

    func test_defaultMetrics_matchDenseInspectorRowRhythm() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.controlRowMinHeight, 30)
        XCTAssertEqual(metrics.controlLabelWidth, 104)
        XCTAssertEqual(metrics.controlColumnSpacing, 10)
        XCTAssertEqual(metrics.controlTrailingValueWidth, 48)
        XCTAssertEqual(metrics.controlStackSpacing, 0)
    }

    func test_defaultMetrics_defineNumericTrailingCluster() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.controlTrailingClusterSpacing, 6)
        XCTAssertEqual(metrics.controlUnitSuffixWidth, 24)
        XCTAssertEqual(metrics.controlValueFieldWidth, 55)
    }

    func test_defaultMetrics_exposeReadoutTokens() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.controlReadoutWidth, 55)
        XCTAssertEqual(
            metrics.controlReadoutWidth,
            metrics.controlValueFieldWidth,
            "Read-only readouts must share editable field width so rows align"
        )
    }

    func test_defaultMetrics_exposeSegmentedAndUnitPickerWidths() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.controlSegmentedModeWidth, 80)
        XCTAssertEqual(metrics.controlUnitPickerWidth, 100)
    }

    func test_defaultMetrics_definePreviewContainmentInsets() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.fullWidthRowHorizontalInset, metrics.outerInset)
        XCTAssertEqual(metrics.containedPreviewMaxWidth, 350 - (metrics.outerInset * 2))
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
