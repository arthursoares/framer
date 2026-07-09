// GPUEffectRegressionTests.swift
// Regressions raised in PR #12 review:
//
//   1. Blockify's shader had inverted the bucket-wide color-mode numbering
//      (it borrowed ASCII's separate `asciiColorMode` convention), so
//      `.source` painted flat fg/bg (white blocks on a fresh layer) and
//      `.foregroundBackground` painted sampled colour.
//
//   2. EdgeFieldRenderer dispatched by `payload.variant` instead of the
//      layer kind, so a stale `gpu_edge_variant` in a hand-edited YAML
//      file rendered a different effect than the layer label showed.

import XCTest
import CoreGraphics
@testable import FramerCore

final class GPUEffectRegressionTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSolidImage(red: Double, green: Double, blue: Double, size: Int = 64) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    private func makeGradientImage(size: Int = 128) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 4
                pixels[idx]     = UInt8((x * 13 + y * 7) % 256)
                pixels[idx + 1] = UInt8((x * 5 + y * 19) % 256)
                pixels[idx + 2] = UInt8(((x ^ y) * 11) % 256)
                pixels[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        out.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    /// Mean R/G/B over the whole image, in 0...255 byte units.
    private func meanRGB(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
        let p = bytes(image)
        let n = image.width * image.height
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<n {
            r += Double(p[i * 4])
            g += Double(p[i * 4 + 1])
            b += Double(p[i * 4 + 2])
        }
        return (r / Double(n), g / Double(n), b / Double(n))
    }

    private func requireMetal() throws {
        guard MetalEffectLibrary.shared != nil else {
            throw XCTSkip("Metal device unavailable on this host (likely CI sandbox).")
        }
    }

    private func renderBlockify(
        input: CGImage,
        color: GPUEffectColorParameters,
        params: TextCellParameters = TextCellParameters(variant: .blockify)
    ) throws -> CGImage {
        try TextCellRenderer.renderBlockifyFromBucket(
            input: input,
            common: GPUEffectCommonParameters(),
            geometry: GPUEffectGeometryParameters(),
            color: color,
            params: params,
            outputSize: CGSize(width: input.width, height: input.height)
        )
    }

    // MARK: - Blockify color-mode mapping

    func testBlockifySourceModeShowsSampledColor() throws {
        try requireMetal()
        let red = makeSolidImage(red: 1, green: 0, blue: 0)
        let output = try renderBlockify(
            input: red,
            color: GPUEffectColorParameters(mode: .source, backgroundIntensity: 0)
        )
        let mean = meanRGB(output)
        // Pre-fix the shader painted the flat foreground uniform (white) for
        // mode 0, so a fresh Blockify layer rendered white blocks.
        XCTAssertGreaterThan(mean.r, 180, "source mode should keep the sampled red")
        XCTAssertLessThan(mean.g, 60, "green channel should stay low — white output means the fg/bg uniform leaked in")
        XCTAssertLessThan(mean.b, 60, "blue channel should stay low — white output means the fg/bg uniform leaked in")
    }

    func testBlockifyForegroundBackgroundModeUsesFlatForeground() throws {
        try requireMetal()
        let red = makeSolidImage(red: 1, green: 0, blue: 0)
        let blue = try? CodableColor(hex: "#0000FF")
        let output = try renderBlockify(
            input: red,
            color: GPUEffectColorParameters(mode: .foregroundBackground, backgroundIntensity: 0),
            params: TextCellParameters(variant: .blockify, foreground: blue)
        )
        let mean = meanRGB(output)
        // Pre-fix mode 1 sampled the source, so the explicit foreground
        // colour was ignored and this came out red.
        XCTAssertGreaterThan(mean.b, 180, "fg/bg mode should paint the flat foreground colour")
        XCTAssertLessThan(mean.r, 60, "red source must not leak into fg/bg mode")
    }

    func testBlockifyMonochromeModeIsGrayscale() throws {
        try requireMetal()
        let red = makeSolidImage(red: 1, green: 0, blue: 0)
        let output = try renderBlockify(
            input: red,
            color: GPUEffectColorParameters(mode: .monochrome, backgroundIntensity: 0)
        )
        let mean = meanRGB(output)
        // Pre-fix mode 2 fell into the flat-foreground branch (white).
        XCTAssertEqual(mean.r, mean.g, accuracy: 10, "monochrome output should be gray")
        XCTAssertEqual(mean.g, mean.b, accuracy: 10, "monochrome output should be gray")
        XCTAssertLessThan(mean.r, 180, "luma of pure red is well below white — white means the fg uniform leaked in")
        XCTAssertGreaterThan(mean.r, 10, "luma of pure red is well above black")
    }

    // MARK: - EdgeField dispatch follows the layer kind

    func testEdgeFieldRendersByKindNotStaleVariant() throws {
        try requireMetal()
        let input = makeGradientImage()
        let outputSize = CGSize(width: input.width, height: input.height)
        let common = GPUEffectCommonParameters()
        let geometry = GPUEffectGeometryParameters()
        let color = GPUEffectColorParameters(mode: .monochrome, backgroundIntensity: 0.2)

        // Same payload twice, differing only in a stale `variant` — the kind
        // must win, so both renders are identical.
        let stale = try EdgeFieldRenderer.renderPreview(
            input: input,
            effect: .edgeDetection,
            parameters: .edgeField(
                common: common, geometry: geometry, color: color,
                edgeField: EdgeFieldParameters(variant: .contour)),
            outputSize: outputSize
        )
        let matching = try EdgeFieldRenderer.renderPreview(
            input: input,
            effect: .edgeDetection,
            parameters: .edgeField(
                common: common, geometry: geometry, color: color,
                edgeField: EdgeFieldParameters(variant: .edgeDetection)),
            outputSize: outputSize
        )
        XCTAssertEqual(bytes(stale), bytes(matching),
                       "a stale payload variant must not change which effect renders")
    }

    func testYAMLStaleEdgeVariantNormalizedToKind() throws {
        let yaml = """
        layers:
          - type: gpu_effect
            gpu_effect_kind: edgeDetection
            gpu_edge_variant: contour
        """
        let config = try YAMLConfig.decode(yaml)
        guard case .gpuEffect(let layerParams)? = config.layers?.first else {
            XCTFail("expected a gpu_effect layer"); return
        }
        XCTAssertEqual(layerParams.kind, .edgeDetection)
        guard case .edgeField(_, _, _, let payload) = layerParams.params else {
            XCTFail("expected edgeField parameters"); return
        }
        XCTAssertEqual(payload.variant, .edgeDetection,
                       "decode must normalize a stale gpu_edge_variant to the layer kind")
    }
}
