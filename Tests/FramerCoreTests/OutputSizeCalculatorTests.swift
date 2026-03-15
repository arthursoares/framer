import XCTest
import CoreGraphics
@testable import FramerCore

final class OutputSizeCalculatorTests: XCTestCase {

    // MARK: - No Layers

    func testNoLayers_returnsOriginalSize() {
        let input = CGSize(width: 1000, height: 800)
        let result = OutputSizeCalculator.outputSize(for: input, layers: [])
        XCTAssertEqual(result.width, 1000)
        XCTAssertEqual(result.height, 800)
    }

    // MARK: - Border Layer

    func testBorderPixels_addsTwiceThickness() {
        let input = CGSize(width: 1000, height: 800)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(50)))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 1100)
        XCTAssertEqual(result.height, 900)
    }

    func testBorderPercent_relativeToShorterDimension() {
        // 10% of shorter dimension (800) = 80, added twice = 160
        let input = CGSize(width: 1000, height: 800)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .percent(10)))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 1160)
        XCTAssertEqual(result.height, 960)
    }

    func testBorderPercent_squareImage() {
        // 5% of 500 = 25, added twice = 50
        let input = CGSize(width: 500, height: 500)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .percent(5)))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 550)
        XCTAssertEqual(result.height, 550)
    }

    // MARK: - Padding Layer

    func testPadding_addsTwiceThickness() {
        let input = CGSize(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .padding(PaddingLayerParams(thickness: 100))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 1000)
        XCTAssertEqual(result.height, 800)
    }

    // MARK: - Canvas Layer

    func testCanvas_outputIsExactCanvasSize() {
        let input = CGSize(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .canvas(CanvasLayerParams(width: 1080, height: 1350))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 1080)
        XCTAssertEqual(result.height, 1350)
    }

    // MARK: - Resize Layer

    func testResize_downscalePreservingAspectRatio() {
        // 2000x1000 into max 1000x1000 → 1000x500
        let input = CGSize(width: 2000, height: 1000)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 1000, maxHeight: 1000))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 1000)
        XCTAssertEqual(result.height, 500)
    }

    func testResize_downscaleConstrainedByHeight() {
        // 1000x2000 into max 1000x1000 → 500x1000
        let input = CGSize(width: 1000, height: 2000)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 1000, maxHeight: 1000))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 500)
        XCTAssertEqual(result.height, 1000)
    }

    func testResize_noUpscaleWhenAlreadyFits() {
        let input = CGSize(width: 500, height: 300)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 1000, maxHeight: 1000))
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 500)
        XCTAssertEqual(result.height, 300)
    }

    // MARK: - Passthrough Layers

    func testOverlay_noDimensionChange() {
        let input = CGSize(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .overlay(OverlayLayerParams())
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    func testDither_noDimensionChange() {
        let input = CGSize(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .dither(DitherLayerParams())
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    func testOrientation_noDimensionChange() {
        let input = CGSize(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .orientation(OrientationLayerParams())
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    func testCaption_noDimensionChange() {
        let input = CGSize(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .caption(CaptionLayerParams())
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    // MARK: - Multiple Layers

    func testMultipleLayers_appliedInSequence() {
        // Start: 1000x800
        // Border 50px: 1100x900
        // Padding 25: 1150x950
        // Resize 1000x1000: fits within, scale = min(1000/1150, 1000/950) = min(0.869, 1.052) = 0.869
        //   → 1150*0.869 = 999.35 ≈ 999, 950*0.869 = 825.55 ≈ 825
        // Actually let's use floor to be safe. Let me pick values that work out cleanly.

        // Start: 2000x1000
        // Border 100px: 2200x1200
        // Resize max 1100x600: scale = min(1100/2200, 600/1200) = min(0.5, 0.5) = 0.5
        //   → 1100x600
        let input = CGSize(width: 2000, height: 1000)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(100))),
            .resize(ResizeLayerParams(maxWidth: 1100, maxHeight: 600)),
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 1100)
        XCTAssertEqual(result.height, 600)
    }

    func testMultipleLayers_borderThenCanvas() {
        // Start: 1000x800
        // Border 50px: 1100x900
        // Canvas 500x500: output is 500x500
        let input = CGSize(width: 1000, height: 800)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(50))),
            .canvas(CanvasLayerParams(width: 500, height: 500)),
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        XCTAssertEqual(result.width, 500)
        XCTAssertEqual(result.height, 500)
    }

    func testMultipleLayers_passthroughsDoNotAffectResult() {
        let input = CGSize(width: 1000, height: 800)
        let layers: [CompositionLayer] = [
            .dither(DitherLayerParams()),
            .border(BorderLayerParams(thickness: .pixels(50))),
            .overlay(OverlayLayerParams()),
            .orientation(OrientationLayerParams()),
            .caption(CaptionLayerParams()),
        ]
        let result = OutputSizeCalculator.outputSize(for: input, layers: layers)
        // Only border affects: 1000+100=1100, 800+100=900
        XCTAssertEqual(result.width, 1100)
        XCTAssertEqual(result.height, 900)
    }
}
