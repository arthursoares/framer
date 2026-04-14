import XCTest
@testable import Framer

final class LayerPanelRowStateResolverTests: XCTestCase {
    func test_resolve_prefersDropTargetOverDraggingExpandedAndHover() {
        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: true,
                isHovering: true,
                isEnabled: true,
                isDragging: true,
                isDropTarget: true
            ),
            LayerPanelRowResolvedState(
                chassis: .dropTarget,
                availability: .default
            )
        )
    }

    func test_resolve_keepsExpandedChassisWhenLayerIsDisabled() {
        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: true,
                isHovering: false,
                isEnabled: false,
                isDragging: false,
                isDropTarget: false
            ),
            LayerPanelRowResolvedState(
                chassis: .expanded,
                availability: .disabled
            )
        )
    }

    func test_resolve_usesHoverChassisForCollapsedEnabledRows() {
        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: false,
                isHovering: true,
                isEnabled: true,
                isDragging: false,
                isDropTarget: false
            ),
            LayerPanelRowResolvedState(
                chassis: .hover,
                availability: .default
            )
        )
    }
}
