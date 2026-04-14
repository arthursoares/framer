import XCTest
import FramerCore
@testable import Framer

final class InspectorOutputControlStateTests: XCTestCase {
    func test_formatSelection_returnsExpectedTagForOutputFormat() {
        XCTAssertEqual(InspectorOutputControlState.formatSelection(for: .png), "png")
        XCTAssertEqual(InspectorOutputControlState.formatSelection(for: .jpeg(quality: 72)), "jpeg")
    }

    func test_applyFormatSelection_preservesExistingOutputSemantics() {
        var config = ProcessingConfig(outputFormat: .jpeg(quality: 72))

        InspectorOutputControlState.applyFormatSelection("png", to: &config)
        XCTAssertEqual(config.outputFormat, .png)

        InspectorOutputControlState.applyFormatSelection("jpeg", to: &config)
        XCTAssertEqual(config.outputFormat, .jpeg(quality: 100))
    }

    func test_jpegQuality_returnsValueOnlyForJpegOutput() {
        XCTAssertEqual(InspectorOutputControlState.jpegQuality(for: .jpeg(quality: 85)), 85)
        XCTAssertNil(InspectorOutputControlState.jpegQuality(for: .png))
    }

    func test_setJPEGQuality_updatesOutputFormatToMatchingIntegerQuality() {
        var config = ProcessingConfig(outputFormat: .png)

        InspectorOutputControlState.setJPEGQuality(90, on: &config)

        XCTAssertEqual(config.outputFormat, .jpeg(quality: 90))
    }
}
