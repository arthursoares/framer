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
            fill: .dominantColor
        ))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(CompositionLayer.self, from: data)
        XCTAssertEqual(layer, decoded)
    }

    func test_canvasLayer_roundtripsJSON() throws {
        let layer = CompositionLayer.canvas(CanvasLayerParams(
            width: 1080,
            height: 1350,
            fill: .gradientLinear
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

    func test_layerArray_roundtripsJSON() throws {
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FFFFFF"))),
            .padding(PaddingLayerParams(thickness: 100, fill: .color(try CodableColor(hex: "#000000")))),
            .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .gradientRadial))
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
        let fill = LayerFill.dominantColor
        let data = try JSONEncoder().encode(fill)
        let decoded = try JSONDecoder().decode(LayerFill.self, from: data)
        XCTAssertEqual(fill, decoded)
    }

    func test_layerFill_gradientLinear_roundtripsJSON() throws {
        let fill = LayerFill.gradientLinear
        let data = try JSONEncoder().encode(fill)
        let decoded = try JSONDecoder().decode(LayerFill.self, from: data)
        XCTAssertEqual(fill, decoded)
    }

    // MARK: - fromLegacyConfig

    func test_fromLegacyConfig_solid() {
        var config = ProcessingConfig.default
        config.borderStyle = .solid
        config.borderThickness = .pixels(10)
        config.padding = 50
        let layers = CompositionLayer.fromLegacyConfig(config)

        XCTAssertEqual(layers.count, 2)
        if case .border(let p) = layers[0] {
            XCTAssertEqual(p.thickness, .pixels(10))
        } else {
            XCTFail("First layer should be border")
        }
        if case .padding(let p) = layers[1] {
            XCTAssertEqual(p.thickness, 50)
        } else {
            XCTFail("Second layer should be padding")
        }
    }

    func test_fromLegacyConfig_instagram() {
        var config = ProcessingConfig.default
        config.borderStyle = .instagram
        config.instagramMaxSize = 800
        let layers = CompositionLayer.fromLegacyConfig(config)

        XCTAssertEqual(layers.count, 4)
        if case .resize(let p) = layers[0] {
            XCTAssertEqual(p.maxWidth, 800)
            XCTAssertEqual(p.maxHeight, 800)
        } else {
            XCTFail("First layer should be resize")
        }
        if case .padding = layers[1] {} else {
            XCTFail("Second layer should be padding")
        }
        if case .border = layers[2] {} else {
            XCTFail("Third layer should be border")
        }
        if case .canvas(let p) = layers[3] {
            XCTAssertEqual(p.width, 1080)
            XCTAssertEqual(p.height, 1350)
        } else {
            XCTFail("Fourth layer should be canvas")
        }
    }

    func test_fromLegacyConfig_print() {
        var config = ProcessingConfig.default
        let format = PrintFormat(widthMM: 148, heightMM: 100, dpi: 300)
        config.borderStyle = .print(format)
        let layers = CompositionLayer.fromLegacyConfig(config)

        XCTAssertEqual(layers.count, 3)
        if case .resize = layers[0] {} else {
            XCTFail("First layer should be resize")
        }
        if case .border = layers[1] {} else {
            XCTFail("Second layer should be border")
        }
        if case .canvas(let p) = layers[2] {
            XCTAssertEqual(p.width, format.widthPixels)
            XCTAssertEqual(p.height, format.heightPixels)
        } else {
            XCTFail("Third layer should be canvas")
        }
    }

    // MARK: - applyLayers

    func test_applyLayers_borderOnly_correctDimensions() throws {
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FFFFFF")))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image)
        XCTAssertEqual(result.image.width, 120) // 100 + 2*10
        XCTAssertEqual(result.image.height, 120)
    }

    func test_applyLayers_borderAndPadding_correctDimensions() throws {
        let image = makeTestImage(width: 100, height: 100)
        let layers: [CompositionLayer] = [
            .border(BorderLayerParams(thickness: .pixels(10), color: try CodableColor(hex: "#FF0000"))),
            .padding(PaddingLayerParams(thickness: 20, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image)
        // 100 + 2*10 (border) + 2*20 (padding) = 160
        XCTAssertEqual(result.image.width, 160)
        XCTAssertEqual(result.image.height, 160)
    }

    func test_applyLayers_canvas_setsOriginAndSize() throws {
        let image = makeTestImage(width: 100, height: 80)
        let layers: [CompositionLayer] = [
            .canvas(CanvasLayerParams(width: 400, height: 300, fill: .color(try CodableColor(hex: "#FFFFFF"))))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image)
        XCTAssertEqual(result.image.width, 400)
        XCTAssertEqual(result.image.height, 300)
        XCTAssertNotNil(result.imageOrigin)
    }

    func test_applyLayers_resize_scalesDown() throws {
        let image = makeTestImage(width: 1000, height: 800)
        let layers: [CompositionLayer] = [
            .resize(ResizeLayerParams(maxWidth: 500, maxHeight: 500))
        ]
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image)
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
        let result = try BorderRenderer.applyLayers(layers, to: image, sourceImage: image)
        XCTAssertEqual(result.image.width, 1080)
        XCTAssertEqual(result.image.height, 1350)
        XCTAssertNotNil(result.imageOrigin)
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
}
