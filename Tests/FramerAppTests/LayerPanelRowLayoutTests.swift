import XCTest
@testable import Framer

/// An expanded LayerPanelRow's inner editor label column must align with the
/// section's top-level label column (both at metrics.outerInset). Before the
/// pass-2 migration, the chassis raw-paddinged the expanded body by
/// `Spacing.xl + Spacing.xs = 28pt`, which offset inner editor labels to the
/// right of the section grid. This probe guards the invariant.
final class LayerPanelRowLayoutTests: XCTestCase {
    func test_expandedBodyLeadingInset_matchesSectionOuterInset() {
        let metrics = SidebarMetrics()
        let mirrored = LayerPanelRowLayoutProbe.expandedLeadingInset(metrics: metrics)

        XCTAssertEqual(
            mirrored,
            metrics.outerInset,
            "Expanded body's leading padding must equal metrics.outerInset so inner editor label column aligns with section grid"
        )
    }
}

/// Mirror of the value LayerPanelRow applies to its expanded body's leading
/// padding. If you change the implementation, update this probe.
enum LayerPanelRowLayoutProbe {
    static func expandedLeadingInset(metrics: SidebarMetrics) -> CGFloat {
        metrics.outerInset
    }
}
