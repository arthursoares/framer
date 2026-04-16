import XCTest
import SwiftUI
@testable import Framer

@MainActor
final class StyledSliderSuffixTests: XCTestCase {
    /// StyledSlider must not render its own inline suffix Text. A caller who
    /// also uses SidebarTrailingUnitCluster would otherwise get two unit
    /// labels at divergent widths (the slider's 20pt vs the cluster's 24pt).
    func test_styledSliderBody_doesNotEmbedInlineSuffixText() {
        let slider = StyledSlider(value: .constant(50), range: 0...100)
        let bodyTypeName = String(reflecting: type(of: slider.body))

        XCTAssertFalse(
            bodyTypeName.contains("_ConditionalContent<ModifiedContent<Text"),
            "StyledSlider must not conditionally render a Text for a suffix. Body type: \(bodyTypeName)"
        )
    }

    /// StyledSlider's public surface should be free of the old suffix /
    /// inputWidth parameters. If they get reintroduced, pass-2 harmony is
    /// silently broken.
    func test_styledSlider_initializer_omitsSuffixAndInputWidth() {
        _ = StyledSlider(
            value: .constant(50),
            range: 0...100,
            accessibilityLabel: "Quality",
            step: 5
        )
        // Compilation is the assertion: if someone adds `suffix:` or
        // `inputWidth:` back, this closure stops compiling.
    }
}
