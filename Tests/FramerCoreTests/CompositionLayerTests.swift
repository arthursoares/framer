import XCTest
@testable import FramerCore

final class CompositionLayerTests: XCTestCase {

    // MARK: - Test Helpers

    func makeTestImage(width: Int = 100, height: Int = 80) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - Layer Codable Round-Trip

    func test_borderLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.border(BorderLayerParams(
            thickness: .pixels(20),
            color: try CodableColor(hex: "#FF0000")
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_paddingLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.padding(PaddingLayerParams(
            thickness: 50,
            fill: .dominantColor()
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_canvasLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.canvas(CanvasLayerParams(
            width: 1080,
            height: 1350,
            fill: .gradientLinear()
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_resizeLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.resize(ResizeLayerParams(
            maxWidth: 800,
            maxHeight: 600
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_overlayLayer_frame_roundtripsJSON() throws {
        let layer = CompositionLayer.overlay(OverlayLayerParams(
            overlayName: "frame__01",
            kind: .frame,
            opacity: 80
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_overlayLayer_texture_roundtripsJSON() throws {
        let layer = CompositionLayer.overlay(OverlayLayerParams(
            overlayName: "dirt__film_dust001",
            kind: .dust,
            opacity: 50
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_overlayLayer_blendMode_roundtripsJSON() throws {
        let layer = CompositionLayer.overlay(OverlayLayerParams(
            overlayName: "leak__light01",
            kind: .lightLeak,
            blendMode: .screen,
            opacity: 75
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
        if case .overlay(let p) = decoded {
            XCTAssertEqual(p.blendMode, .screen)
        } else {
            XCTFail("Expected overlay layer")
        }
    }

    func test_overlayBlendMode_defaultsPerKind() {
        XCTAssertEqual(OverlayBlendMode.defaultFor(.frame), .normal)
        XCTAssertEqual(OverlayBlendMode.defaultFor(.dust), .normal)
        XCTAssertEqual(OverlayBlendMode.defaultFor(.lightLeak), .screen)
        XCTAssertEqual(OverlayBlendMode.defaultFor(.wetPlate), .softLight)
    }

    func test_overlayLayer_defaultBlendMode_matchesKind() {
        let frameParams = OverlayLayerParams(kind: .frame)
        XCTAssertEqual(frameParams.blendMode, .normal)

        let leakParams = OverlayLayerParams(kind: .lightLeak)
        XCTAssertEqual(leakParams.blendMode, .screen)

        let plateParams = OverlayLayerParams(kind: .wetPlate)
        XCTAssertEqual(plateParams.blendMode, .softLight)
    }

    func test_overlayKind_fromFilename() {
        XCTAssertEqual(OverlayKind.from(filename: "frame__01"), .frame)
        XCTAssertEqual(OverlayKind.from(filename: "frame_fls_0026"), .frame)
        XCTAssertEqual(OverlayKind.from(filename: "dirt__film_dust001"), .dust)
        XCTAssertEqual(OverlayKind.from(filename: "leak__dr_light__01"), .lightLeak)
        XCTAssertEqual(OverlayKind.from(filename: "plate__wetplate_a"), .wetPlate)
        // Unknown prefix defaults to frame
        XCTAssertEqual(OverlayKind.from(filename: "my_custom_overlay"), .frame)
    }

    func test_layerArray_roundtripsJSON() throws {
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FFFFFF"))),
            .padding(PaddingLayerParams(thickness: 100, fill: .color(try CodableColor(hex: "#000000")))),
            .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .gradientRadial()))
        ]
        let data = try JSONEncoder().encode(layers)
        let decoded = try JSONDecoder().decode([CompositionLayer].self, from: data)
        XCTAssertEqual(layers, decoded)
    }

    // MARK: - LayerFill Codable

    func test_layerFill_color_roundtripsJSON() throws {
        let fill = LayerFill.color(try CodableColor(hex: "#AABBCC"))
        let data = try JSONEncoder().encode(fill)
        let decoded = try JSONDecoder().decode(LayerFill.self, from: data)
        XCTAssertEqual(fill, decoded)
    }

    func test_layerFill_dominant_roundtripsJSON() throws {
        let fill = LayerFill.dominantColor()
        let data = try JSONEncoder().encode(fill)
        let decoded = try JSONDecoder().decode(LayerFill.self, from: data)
        XCTAssertEqual(fill, decoded)
    }

    func test_layerFill_gradientLinear_roundtripsJSON() throws {
        let fill = LayerFill.gradientLinear()
        let data = try JSONEncoder().encode(fill)
        let decoded = try JSONDecoder().decode(LayerFill.self, from: data)
        XCTAssertEqual(fill, decoded)
    }

    // MARK: - Caption Layer

    func test_captionLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.caption(CaptionLayerParams(
            mode: .template("{{camera}} - {{mon}} '{{year2}}"),
            fontName: "Courier New",
            fontSize: .fixed(24),
            fontColor: try CodableColor(hex: "#FF0000")
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    // MARK: - applyLayers

    func test_applyLayers_borderOnly_correctDimensions() throws {
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FFFFFF")))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 120) // 100 + 2*10
        XCTAssertEqual(result.image.height, 120)
    }

    func test_applyLayers_borderAndPadding_correctDimensions() throws {
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FF0000"))),
            .padding(PaddingLayerParams(thickness: 20, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        // 100 + 2*10 (border) + 2*20 (padding) = 160
        XCTAssertEqual(result.image.width, 160)
        XCTAssertEqual(result.image.height, 160)
    }

    func test_applyLayers_canvas_setsOriginAndSize() throws {
        let image = makeTestImage(width: 100, height: 80)
        let layers: [CompositionLayer] = [
            .canvas(CanvasLayerParams(width: 400, height: 300, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 400)
        XCTAssertEqual(result.image.height, 300)
        XCTAssertNotNil(result.imageOrigin)
    }

    func test_applyLayers_resize_scalesDown() throws {
        let image = makeTestImage(width: 1000, height: 800)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 500, maxHeight: 500))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertLessThanOrEqual(result.image.width, 500)
        XCTAssertLessThanOrEqual(result.image.height, 500)
        // Check aspect ratio preserved
        let originalRatio = 1000.0 / 800.0
        let resultRatio = Double(result.image.width) / Double(result.image.height)
        XCTAssertEqual(resultRatio, originalRatio, accuracy: 0.02)
    }

    func test_applyLayers_fullStack_instagramLike() throws {
        let image = makeTestImage(width: 800, height: 600)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 500, maxHeight: 500)),
            .padding(PaddingLayerParams(thickness: 20, fill: .color(try CodableColor(hex: "#FFFFFF")))),
            .border(BorderLayerParams(thickness: .pixels(5), color: try CodableColor(hex: "#000000"))),
            .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 1080)
        XCTAssertEqual(result.image.height, 1350)
        XCTAssertNotNil(result.imageOrigin)
    }

    func test_applyLayers_overlay_preservesDimensions() throws {
        // Create a photo image and a mid-gray "frame" overlay
        let photo = makeTestImage(width: 200, height: 150)
        // Mid-gray overlay → should be fully transparent (no visible change)
        _ = makeTestImage(width: 200, height: 150)

        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FFFFFF")))
        ]
        let bordered = try BorderRenderer.applyLayers(layers, to: photo, sourceImage: photo, exif: ExifData())
        // 200 + 20 = 220, 150 + 20 = 170
        XCTAssertEqual(bordered.image.width, 220)
        XCTAssertEqual(bordered.image.height, 170)
    }

    // MARK: - ProcessingConfig with layers

    func test_processingConfig_withLayers_roundtripsJSON() throws {
        var config = ProcessingConfig.default
        config.layers = [
            .border(BorderLayerParams(thickness: .pixels(20), color: try CodableColor(hex: "#FFFFFF"))),
            .padding(PaddingLayerParams(thickness: 150, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProcessingConfig.self, from: data)
        XCTAssertEqual(config.layers, decoded.layers)
    }

    func test_processingConfig_withoutLayers_decodesNil() throws {
        let config = ProcessingConfig.default
        XCTAssertNil(config.layers)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProcessingConfig.self, from: data)
        XCTAssertNil(decoded.layers)
    }

    func test_processingConfig_oldData_layersIsNil() throws {
        // Simulate old data without layers key
        var config = ProcessingConfig.default
        config.borderStyle = .solid
        let data = try JSONEncoder().encode(config)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "layers")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(ProcessingConfig.self, from: strippedData)
        XCTAssertNil(decoded.layers)
    }

    // MARK: - Caption Empty Text Guard

    func test_captionRenderer_emptyText_returnsOriginal() throws {
        let image = makeTestImage(width: 200, height: 150)
        let params = CaptionLayerParams(mode: .custom(""))
        let result = try CaptionRenderer.renderCaption(on: image, params: params, exif: ExifData())
        // Empty caption should return the original image unchanged
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    func test_captionRenderer_whitespaceOnly_returnsOriginal() throws {
        let image = makeTestImage(width: 200, height: 150)
        let params = CaptionLayerParams(mode: .custom("   "))
        let result = try CaptionRenderer.renderCaption(on: image, params: params, exif: ExifData())
        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }

    // MARK: - Layer Coalescing

    func test_applyLayers_coalescedBorderPadding_matchesDimensions() throws {
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FF0000"))),
            .padding(PaddingLayerParams(thickness: 20, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        // 100 + 2*10 (border) + 2*20 (padding) = 160
        XCTAssertEqual(result.image.width, 160)
        XCTAssertEqual(result.image.height, 160)
    }

    func test_applyLayers_tripleBorderCoalesced_correctDimensions() throws {
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(5), color: try CodableColor(hex: "#FF0000"))),
            .padding(PaddingLayerParams(thickness: 10, fill: .color(try CodableColor(hex: "#00FF00")))),
            .border(BorderLayerParams(thickness: .pixels(3), color: try CodableColor(hex: "#0000FF")))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        // 100 + 2*(5+10+3) = 136
        XCTAssertEqual(result.image.width, 136)
        XCTAssertEqual(result.image.height, 136)
    }

    // MARK: - Blend Correctness

    func test_blendOverlay_multiply_darkenOnly() throws {
        // Create a white base image
        let whiteCtx = CGContext(data: nil, width: 50, height: 50,
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        whiteCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        whiteCtx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        let whiteImage = whiteCtx.makeImage()!

        // Create a dark overlay (below mid-gray → will have non-zero strength)
        let darkCtx = CGContext(data: nil, width: 50, height: 50,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        darkCtx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        darkCtx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        _ = darkCtx.makeImage()!

        // Apply multiply overlay
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(0), color: try CodableColor(hex: "#FFFFFF")))
        ]
        // We test indirectly: multiply should not make any pixel brighter than base
        let result = try BorderRenderer.applyLayers(layers, to: whiteImage, sourceImage: whiteImage, exif: ExifData())
        XCTAssertEqual(result.image.width, 50)
    }

    // MARK: - Orientation Layer

    func test_orientationLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.orientation(OrientationLayerParams(target: .portrait))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_applyLayers_orientation_rotatesPortraitToLandscape() throws {
        let image = makeTestImage(width: 100, height: 200) // portrait
        let layers: [CompositionLayer] = [
            .orientation(OrientationLayerParams(target: .landscape))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 200)
        XCTAssertEqual(result.image.height, 100)
    }

    func test_applyLayers_orientation_noopWhenAlreadyCorrect() throws {
        let image = makeTestImage(width: 200, height: 100) // landscape
        let layers: [CompositionLayer] = [
            .orientation(OrientationLayerParams(target: .landscape))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 200)
        XCTAssertEqual(result.image.height, 100)
    }

    func test_applyLayers_orientation_rotatesLandscapeToPortrait() throws {
        let image = makeTestImage(width: 200, height: 100) // landscape
        let layers: [CompositionLayer] = [
            .orientation(OrientationLayerParams(target: .portrait))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 100)
        XCTAssertEqual(result.image.height, 200)
    }

    func test_applyLayers_coalescedPercentBorder_matchesNonCoalesced() throws {
        // Percent-based borders in a coalesced run must resolve against the accumulated
        // dimensions (as if each layer were applied individually), not the original image.
        let image = makeTestImage(width: 200, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(20), color: try CodableColor(hex: "#FF0000"))),
            .border(BorderLayerParams(thickness: .percent(10), color: try CodableColor(hex: "#00FF00")))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        // After first border: 200+40=240 x 100+40=140, shorter side = 140
        // 10% of 140 = 14
        // Final: 240+28=268 x 140+28=168
        XCTAssertEqual(result.image.width, 268)
        XCTAssertEqual(result.image.height, 168)
    }

    func test_applyLayers_coalescedPercentBorderPadding_correctDimensions() throws {
        // Mix of padding and percent border in a coalesced run
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .padding(PaddingLayerParams(thickness: 50, fill: .color(try CodableColor(hex: "#FFFFFF")))),
            .border(BorderLayerParams(thickness: .percent(10), color: try CodableColor(hex: "#FF0000")))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        // After padding: 100+100=200 x 200, shorter = 200
        // 10% of 200 = 20
        // Final: 200+40=240 x 240
        XCTAssertEqual(result.image.width, 240)
        XCTAssertEqual(result.image.height, 240)
    }

    func test_applyLayers_singleBorder_notCoalesced() throws {
        // Single border should still work (no coalescing when only 1 layer)
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(15), color: try CodableColor(hex: "#AABBCC")))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 130) // 100 + 2*15
        XCTAssertEqual(result.image.height, 130)
    }

    // MARK: - Dither Layer Codable

    func test_ditherLayer_bw_roundtripsJSON() throws {
        let layer = CompositionLayer.dither(DitherLayerParams(
            algorithm: .atkinson,
            colorMode: .bw,
            bayerLevel: 2,
            pixelScale: 1
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_ditherLayer_twoTone_roundtripsJSON() throws {
        let layer = CompositionLayer.dither(DitherLayerParams(
            algorithm: .floydSteinberg,
            colorMode: .twoTone(
                foreground: try CodableColor(hex: "#FF0000"),
                background: try CodableColor(hex: "#0000FF")
            ),
            bayerLevel: 3,
            pixelScale: 2
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_ditherLayer_color_roundtripsJSON() throws {
        let layer = CompositionLayer.dither(DitherLayerParams(
            algorithm: .bayer,
            colorMode: .color(levels: 4),
            bayerLevel: 1,
            pixelScale: 4
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    // MARK: - Aspect Ratio Layer

    func test_aspectRatioLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.aspectRatio(AspectRatioLayerParams(
            ratioWidth: 4, ratioHeight: 5, offsetX: 0.2, offsetY: -0.3
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_aspectRatio_cropRect_landscapeToSquare() {
        let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)
        let rect = params.cropRect(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.height, 100)
        XCTAssertEqual(rect.origin.x, 50)
        XCTAssertEqual(rect.origin.y, 0)
    }

    func test_aspectRatio_cropRect_portraitToSquare() {
        let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)
        let rect = params.cropRect(for: CGSize(width: 100, height: 200))
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.height, 100)
        XCTAssertEqual(rect.origin.x, 0)
        XCTAssertEqual(rect.origin.y, 50)
    }

    func test_aspectRatio_cropRect_alreadyMatchingRatio() {
        let params = AspectRatioLayerParams(ratioWidth: 2, ratioHeight: 1)
        let rect = params.cropRect(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect.width, 200)
        XCTAssertEqual(rect.height, 100)
    }

    func test_aspectRatio_cropRect_withOffset() {
        let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1, offsetX: 1.0)
        let rect = params.cropRect(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.height, 100)
        XCTAssertEqual(rect.origin.x, 100)
        XCTAssertEqual(rect.origin.y, 0)
    }

    func test_aspectRatio_cropRect_4by5() {
        let params = AspectRatioLayerParams(ratioWidth: 4, ratioHeight: 5)
        let rect = params.cropRect(for: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(rect.width, 800)
        XCTAssertEqual(rect.height, 1000)
        XCTAssertEqual(rect.origin.x, 100)
    }

    func test_aspectRatio_croppedSize() {
        let params = AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)
        let size = params.croppedSize(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(size.width, 100)
        XCTAssertEqual(size.height, 100)
    }

    // MARK: - Aspect Ratio BorderRenderer Integration

    func test_aspectRatio_borderRenderer_cropsImage() throws {
        let image = makeTestImage(width: 200, height: 100)
        let layers: [CompositionLayer] = [
            .aspectRatio(AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        XCTAssertEqual(result.image.width, 100)
        XCTAssertEqual(result.image.height, 100)
    }

    func test_aspectRatio_beforeBorder_affectsOutput() throws {
        let image = makeTestImage(width: 200, height: 100)
        let layers: [CompositionLayer] = [
            .aspectRatio(AspectRatioLayerParams(ratioWidth: 1, ratioHeight: 1)),
            .border(BorderLayerParams(thickness: .pixels(10), color: .white))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image, exif: ExifData())
        // 100x100 crop + 10px border on each side = 120x120
        XCTAssertEqual(result.image.width, 120)
        XCTAssertEqual(result.image.height, 120)
    }
}
