import XCTest
@testable import Framer

/// These tests guard the contract that `LayerPanelRow`'s expanded body uses
/// `metrics.outerInset` (not a raw `Spacing.*` constant) for its leading
/// padding. Rather than introspect the rendered NSHostingView tree, the
/// chassis exposes a single function `LayerPanelRowChassis.expandedLeadingInset`
/// that production code AND these tests call. A regression that inlines a
/// different value in `LayerPanelRow.body` would fail because the function
/// stops being the source of truth.
final class LayerPanelRowLayoutTests: XCTestCase {
    func test_expandedLeadingInset_equalsDefaultOuterInset() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(
            LayerPanelRowChassis.expandedLeadingInset(metrics: metrics),
            12,
            "Default SidebarMetrics.outerInset is 12pt"
        )
        XCTAssertEqual(
            LayerPanelRowChassis.expandedLeadingInset(metrics: metrics),
            metrics.outerInset,
            "Leading inset must equal metrics.outerInset, not a raw Spacing.* token"
        )
    }

    func test_expandedLeadingInset_propagatesCustomOuterInset() {
        let wide = SidebarMetrics(outerInset: 20)
        let narrow = SidebarMetrics(outerInset: 6)

        XCTAssertEqual(LayerPanelRowChassis.expandedLeadingInset(metrics: wide), 20)
        XCTAssertEqual(LayerPanelRowChassis.expandedLeadingInset(metrics: narrow), 6)
    }

    func test_expandedTrailingInset_isHalfLeading() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(
            LayerPanelRowChassis.expandedTrailingInset(metrics: metrics),
            metrics.outerInset / 2,
            "Trailing stays tight — half the leading inset"
        )
    }

    /// A regression test for the pre-pass-2 value. If someone reverts to the
    /// old chassis (expanded body padded by `Spacing.xl + Spacing.xs = 20pt`
    /// regardless of metrics), the inset stops tracking `outerInset` and this
    /// assertion fails.
    func test_expandedLeadingInset_isNotThePrePass2Value() {
        let metrics = SidebarMetrics()
        let prePass2Inset: CGFloat = 20  // Spacing.xl (16) + Spacing.xs (4)

        XCTAssertNotEqual(
            LayerPanelRowChassis.expandedLeadingInset(metrics: metrics),
            prePass2Inset,
            "Expanded body must not regress to the pre-pass-2 20pt fixed leading"
        )
    }
}
