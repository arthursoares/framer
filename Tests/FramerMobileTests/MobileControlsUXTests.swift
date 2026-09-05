import SwiftUI
import UIKit
import XCTest
import FramerCore
@testable import FramerMobile

@MainActor
final class MobileControlsUXTests: XCTestCase {
    func test_visibilityMutationTargetsStableLayerIDThroughEditorLayers() throws {
        let state = AppState()
        let borderID = try XCTUnwrap(UUID(uuidString: "18BA5657-490E-4CA1-A332-990E012D875F"))
        let paddingID = try XCTUnwrap(UUID(uuidString: "C7059F32-0F4B-4B1E-87C8-24DF25893D27"))
        let original: [CompositionLayer] = [
            .border(BorderLayerParams(id: borderID, enabled: true)),
            .padding(PaddingLayerParams(id: paddingID, enabled: false))
        ]
        state.editorLayers = original

        var updated = state.editorLayers
        XCTAssertTrue(LayerListMutation.toggleVisibility(of: paddingID, in: &updated))
        state.editorLayers = updated

        XCTAssertEqual(state.editorLayers.map(\.id), [borderID, paddingID])
        XCTAssertTrue(state.editorLayers[0].isEnabled)
        XCTAssertTrue(state.editorLayers[1].isEnabled)
        XCTAssertEqual(state.currentConfig.layers, state.editorLayers)

        let missingID = UUID()
        updated = state.editorLayers
        XCTAssertFalse(LayerListMutation.toggleVisibility(of: missingID, in: &updated))
        XCTAssertEqual(updated, state.editorLayers)
    }

    func test_reorderMutationsFollowCurrentIDsRatherThanCapturedIndexes() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "233C5C4C-CB9A-40EE-965B-FB0895285F42"))
        let secondID = try XCTUnwrap(UUID(uuidString: "FB899E4C-7861-49CC-9EE6-C2DA0D95BE8F"))
        let thirdID = try XCTUnwrap(UUID(uuidString: "8070D0FB-9F66-48BF-8BB5-36C5F8F8FCF6"))
        var layers: [CompositionLayer] = [
            .border(BorderLayerParams(id: firstID)),
            .padding(PaddingLayerParams(id: secondID)),
            .orientation(OrientationLayerParams(id: thirdID))
        ]

        XCTAssertTrue(LayerListMutation.move(firstID, to: thirdID, in: &layers))
        XCTAssertEqual(layers.map(\.id), [secondID, thirdID, firstID])

        XCTAssertTrue(LayerListMutation.move(thirdID, direction: .up, in: &layers))
        XCTAssertEqual(layers.map(\.id), [thirdID, secondID, firstID])
        XCTAssertFalse(LayerListMutation.move(thirdID, direction: .up, in: &layers))
        XCTAssertEqual(layers.map(\.id), [thirdID, secondID, firstID])

        XCTAssertTrue(LayerListMutation.delete(secondID, in: &layers))
        XCTAssertEqual(layers.map(\.id), [thirdID, firstID])
    }

    func test_modeTabUsesItsFullWidthRegionAndAccessibleMinimumHeight() {
        let proposedWidth: CGFloat = 160
        let size = hostedSize(
            of: MobileModeTabButton(title: "Presets", isSelected: true, action: {}),
            width: proposedWidth
        )

        XCTAssertEqual(size.width, proposedWidth, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(size.height, 44)
    }

    func test_layerVisibilityButtonMeetsMinimumHitTargetAtLargeDynamicType() {
        let size = hostedSize(
            of: LayerVisibilityButton(layerName: "Border", isEnabled: true, action: {}),
            width: 100
        )

        XCTAssertGreaterThanOrEqual(size.width, 44)
        XCTAssertGreaterThanOrEqual(size.height, 44)
    }

    private func hostedSize<Content: View>(of content: Content, width: CGFloat) -> CGSize {
        let controller = UIHostingController(
            rootView: content.environment(\.dynamicTypeSize, .accessibility5)
        )
        controller.loadViewIfNeeded()
        return controller.sizeThatFits(in: CGSize(width: width, height: 1_000))
    }
}
