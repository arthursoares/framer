import XCTest
import AppKit
import CryptoKit
import SwiftUI
@testable import Framer

/// Guards the pass-2 invariant that `StyledSlider` renders ONLY a
/// slider + numeric field and does not embed its own unit label. Callers
/// that need a unit must compose `StyledUnitSlider` or pair the slider with
/// `SidebarTrailingUnitCluster` via `SidebarControlRow.trailingValue`.
@MainActor
final class StyledSliderSuffixTests: XCTestCase {
    /// Compile-time guard: references the canonical `StyledSlider` init by
    /// its full parameter-label chain. If someone reintroduces `suffix:` or
    /// `inputWidth:` as the PRIMARY init parameters (rather than an
    /// additional overload), this reference breaks and the test target
    /// fails to build.
    func test_styledSliderInitSignature_matchesCanonicalLabels() {
        let canonical: (Binding<Double>, ClosedRange<Double>, LocalizedStringKey?, Double) -> StyledSlider = {
            StyledSlider(value: $0, range: $1, accessibilityLabel: $2, step: $3)
        }
        _ = canonical(.constant(50), 0...100, nil, 1)
    }

    /// Behavioural guard: a `StyledSlider` rendered at identical frame
    /// produces a DIFFERENT bitmap than `StyledUnitSlider` with the same
    /// value/range. If someone reintroduces an inline suffix inside
    /// `StyledSlider`, the two renderings collapse to the same bitmap and
    /// this test fails.
    func test_styledSlider_rendersDistinctBitmapFromStyledUnitSlider() {
        let size = CGSize(width: 240, height: 30)

        let bareSHA = bitmapSHA256(
            of: StyledSlider(value: .constant(50), range: 0...100),
            size: size
        )
        let unitSHA = bitmapSHA256(
            of: StyledUnitSlider(value: .constant(50), range: 0...100, unit: "%"),
            size: size
        )

        XCTAssertNotEqual(
            bareSHA,
            unitSHA,
            "StyledSlider must render a distinct bitmap from StyledUnitSlider. If they match, StyledSlider is rendering its own inline suffix."
        )
    }

    /// Behavioural guard for the flip side: two `StyledUnitSlider` instances
    /// with DIFFERENT units must render different bitmaps. Catches a
    /// regression where someone silently drops the unit Text from the
    /// wrapper.
    func test_styledUnitSlider_unitParameterAffectsRendering() {
        let size = CGSize(width: 240, height: 30)

        let percentSHA = bitmapSHA256(
            of: StyledUnitSlider(value: .constant(50), range: 0...100, unit: "%"),
            size: size
        )
        let pixelSHA = bitmapSHA256(
            of: StyledUnitSlider(value: .constant(50), range: 0...100, unit: "px"),
            size: size
        )

        XCTAssertNotEqual(
            percentSHA,
            pixelSHA,
            "StyledUnitSlider's unit parameter must visibly affect rendering. If % and px produce identical bitmaps, the unit label is being dropped."
        )
    }

    /// Type-shape guard: the body should not contain a `_ConditionalContent`
    /// leaf, which is how an `if !suffix.isEmpty` branch used to show up in
    /// the body type. Cheap layered regression trap.
    func test_styledSliderBody_hasNoConditionalBranches() {
        let bodyTypeName = String(reflecting: type(of: StyledSlider(
            value: .constant(50),
            range: 0...100
        ).body))

        XCTAssertFalse(
            bodyTypeName.contains("_ConditionalContent"),
            "StyledSlider.body must not contain a ConditionalContent branch (would indicate a reintroduced `if !suffix.isEmpty`). Body type: \(bodyTypeName)"
        )
    }

    // MARK: - Helpers

    private func bitmapSHA256<V: View>(of view: V, size: CGSize) -> String {
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        )
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Failed to create bitmap")
            return ""
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode PNG")
            return ""
        }

        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
