import XCTest
import CoreImage
@testable import FramerCore

final class CIFilterPipelineTests: XCTestCase {

    // MARK: - Helpers

    private let context = CIContext()
    private let exif = ExifData()

    /// Create a test CIImage of a given size using a solid color.
    private func makeTestImage(width: Int, height: Int) -> CIImage {
        let color = CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        return CIImage(color: color)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Verify the image is renderable and return its extent.
    private func renderedExtent(_ image: CIImage) -> CGRect {
        // Verify we can actually render this image
        let cgImage = context.createCGImage(image, from: image.extent)
        XCTAssertNotNil(cgImage, "CIImage should be renderable")
        return image.extent
    }

    // MARK: - Passthrough (no layers)

    func test_noLayers_sizeUnchanged() {
        let input = makeTestImage(width: 800, height: 600)
        let result = CIFilterPipeline.apply(
            layers: [],
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        XCTAssertEqual(extent.width, 800, accuracy: 0.5)
        XCTAssertEqual(extent.height, 600, accuracy: 0.5)
    }

    // MARK: - Border

    func test_borderPixels_addsDimensions() {
        let input = makeTestImage(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(20), color: .white))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        // 800 + 20*2 = 840, 600 + 20*2 = 640
        XCTAssertEqual(extent.width, 840, accuracy: 0.5)
        XCTAssertEqual(extent.height, 640, accuracy: 0.5)
    }

    func test_borderPercent_addsDimensions() {
        let input = makeTestImage(width: 800, height: 600)
        // 10% of shorter dimension (600) = 60
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .percent(10), color: .white))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        // 800 + 60*2 = 920, 600 + 60*2 = 720
        XCTAssertEqual(extent.width, 920, accuracy: 0.5)
        XCTAssertEqual(extent.height, 720, accuracy: 0.5)
    }

    // MARK: - Padding

    func test_padding_addsDimensions() {
        let input = makeTestImage(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .padding(PaddingLayerParams(thickness: 50, fill: .color(.white)))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        // 800 + 50*2 = 900, 600 + 50*2 = 700
        XCTAssertEqual(extent.width, 900, accuracy: 0.5)
        XCTAssertEqual(extent.height, 700, accuracy: 0.5)
    }

    // MARK: - Resize

    func test_resize_scalesDown() {
        let input = makeTestImage(width: 2000, height: 1000)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 1000, maxHeight: 1000))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        // Scale = min(1000/2000, 1000/1000) = 0.5
        // 2000*0.5 = 1000, 1000*0.5 = 500
        XCTAssertEqual(extent.width, 1000, accuracy: 1.0)
        XCTAssertEqual(extent.height, 500, accuracy: 1.0)
    }

    func test_resize_doesNotUpscale() {
        let input = makeTestImage(width: 400, height: 300)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 1000, maxHeight: 1000))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        XCTAssertEqual(extent.width, 400, accuracy: 0.5)
        XCTAssertEqual(extent.height, 300, accuracy: 0.5)
    }

    // MARK: - Canvas

    func test_canvas_producesExactDimensions() {
        let input = makeTestImage(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .color(.white)))
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        XCTAssertEqual(extent.width, 1080, accuracy: 0.5)
        XCTAssertEqual(extent.height, 1350, accuracy: 0.5)
    }

    // MARK: - Multiple layers compose

    func test_multipleLayers_composeCorrectly() {
        let input = makeTestImage(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: .white)),
            .padding(PaddingLayerParams(thickness: 20, fill: .color(.black))),
        ]
        let result = CIFilterPipeline.apply(
            layers: layers,
            to: input,
            sourceImage: input,
            exif: exif
        )
        let extent = renderedExtent(result)
        // After border: 800+20=820, 600+20=620
        // After padding: 820+40=860, 620+40=660
        XCTAssertEqual(extent.width, 860, accuracy: 0.5)
        XCTAssertEqual(extent.height, 660, accuracy: 0.5)
    }
}
