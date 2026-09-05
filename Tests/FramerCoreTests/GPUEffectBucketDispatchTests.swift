// GPUEffectBucketDispatchTests.swift
// Smoke test for the `.gpuEffect` layer dispatch chain — for each of the 15
// GPUEffectKind variants, build a minimal GPUEffectParameters payload, route
// through `GPUEffectsPlatform.renderPreview`, and assert the output is
// rendered (dimensions preserved + non-empty + differs from zeros). Catches
// integration breakage (missing bucket case, silent renderer no-op, crash)
// that the deeper shader-style parity tests don't cover.
//
// These are CPU-path tests today (bucket renderers are CPU stubs that don't
// touch Metal). If a variant is later ported to GPU, the dispatch contract
// should stay the same and this test keeps passing.

import XCTest
import CoreGraphics
import CryptoKit
@testable import FramerCore

final class GPUEffectBucketDispatchTests: XCTestCase {

    // MARK: - Fixture

    private func makeTestImage(width: Int = 128, height: Int = 128) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Gradient + checkerboard to give every effect structure to act on.
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = UInt8((x * 13 + y * 7) % 256)
                let g = UInt8((x * 5 + y * 19) % 256)
                let b = UInt8(((x ^ y) * 11) % 256)
                let dark = ((x / 16) + (y / 16)) % 2 == 0
                let dim: Double = dark ? 0.6 : 1.0
                data[idx]     = UInt8(Double(r) * dim)
                data[idx + 1] = UInt8(Double(g) * dim)
                data[idx + 2] = UInt8(Double(b) * dim)
                data[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    // Map each GPUEffectKind to its bucket + a TextCell/PrintSampling/EdgeField
    // /Glitch parameter payload with the `variant` field set so the bucket
    // renderer dispatches to the right per-variant code.
    private func makeParameters(for kind: GPUEffectKind) -> GPUEffectParameters {
        let common = GPUEffectCommonParameters()
        let geometry = GPUEffectGeometryParameters()
        let color = GPUEffectColorParameters(mode: .source, backgroundIntensity: 0.5)

        switch kind {
        // TextCell bucket
        case .ascii:
            return .textCell(common: common, geometry: geometry, color: color,
                             textCell: TextCellParameters(variant: .ascii))
        case .dots:
            return .textCell(common: common, geometry: geometry, color: color,
                             textCell: TextCellParameters(variant: .dots))
        case .blockify:
            return .textCell(common: common, geometry: geometry, color: color,
                             textCell: TextCellParameters(variant: .blockify))
        case .matrixRain:
            return .textCell(common: common, geometry: geometry, color: color,
                             textCell: TextCellParameters(variant: .matrixRain))

        // PrintSampling bucket
        case .dithering:
            return .printSampling(common: common, geometry: geometry, color: color,
                                  printSampling: PrintSamplingParameters(variant: .dithering))
        case .halftone:
            return .printSampling(common: common, geometry: geometry, color: color,
                                  printSampling: PrintSamplingParameters(variant: .halftone))
        case .threshold:
            return .printSampling(common: common, geometry: geometry, color: color,
                                  printSampling: PrintSamplingParameters(variant: .threshold))
        case .crosshatch:
            return .printSampling(common: common, geometry: geometry, color: color,
                                  printSampling: PrintSamplingParameters(variant: .crosshatch))

        // EdgeField bucket
        case .contour:
            return .edgeField(common: common, geometry: geometry, color: color,
                              edgeField: EdgeFieldParameters(variant: .contour))
        case .edgeDetection:
            return .edgeField(common: common, geometry: geometry, color: color,
                              edgeField: EdgeFieldParameters(variant: .edgeDetection))
        case .waveLines:
            return .edgeField(common: common, geometry: geometry, color: color,
                              edgeField: EdgeFieldParameters(variant: .waveLines))
        case .voronoi:
            return .edgeField(common: common, geometry: geometry, color: color,
                              edgeField: EdgeFieldParameters(variant: .voronoi))
        case .noiseField:
            return .edgeField(common: common, geometry: geometry, color: color,
                              edgeField: EdgeFieldParameters(variant: .noiseField))

        // Glitch bucket
        case .pixelSort:
            return .glitch(common: common, geometry: geometry, color: color,
                           glitch: GlitchParameters(variant: .pixelSort))
        case .vhs:
            // Defaults for every sub-factor (distortion/colorBleed/scanlines/
            // trackingError) are 0 on GlitchParameters, so `variant: .vhs`
            // alone produces a pass-through — `amount` is a multiplier on
            // each factor. Seed non-zero values so the shader actually
            // applies visible modulation (matches what makeDefaultLayer()
            // ships for user-facing layer creation).
            var p = GlitchParameters(variant: .vhs)
            p.amount = 0.5
            p.distortion = 0.3
            p.colorBleed = 0.5
            p.scanlines = 0.5
            p.trackingError = 0.3
            return .glitch(common: common, geometry: geometry, color: color, glitch: p)
        }
    }

    // MARK: - Helpers

    private func readBytes(_ image: CGImage) -> [UInt8] {
        let w = image.width
        let h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &bytes, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    // MARK: - Dispatch smoke test

    /// The hidden legacy ASCII bucket remains CPU-rendered for saved projects.
    /// Lock its exact RGBA output, including mismatched variant payloads that
    /// still influence the CPU fallback's color and background styling.
    func testLegacyCPUASCIIFallbackPreservesExactOutput() throws {
        struct Scenario {
            let name: String
            let effect: GPUEffectKind
            let parameters: GPUEffectParameters
            let outputSize: CGSize
            let expectedSHA256: String
        }

        let scenarios = [
            Scenario(
                name: "canonical dense ASCII with palette styling",
                effect: .ascii,
                parameters: .textCell(
                    common: .init(brightness: 0.11, contrast: 1.27, saturation: 0.73, hueRotation: 18, gamma: 0.9),
                    geometry: .init(scale: 1.4, spacing: 2.2, outputWidth: 211),
                    color: .init(mode: .palette, backgroundIntensity: 0.42),
                    textCell: .init(characterSet: .dense, variant: .ascii, intensity: 0.66)
                ),
                outputSize: CGSize(width: 31, height: 23),
                expectedSHA256: "45790b7f1f1cabac8b8f4fd89f18a242910d3f1beb7391058d41bff3774d1766"
            ),
            Scenario(
                name: "fallback effect with matrix-rain styling",
                effect: .threshold,
                parameters: .textCell(
                    common: .init(brightness: -0.07, contrast: 0.91, saturation: 1.18, hueRotation: -25, gamma: 1.2),
                    geometry: .init(scale: 0.85, spacing: 1.6, outputWidth: 173),
                    color: .init(mode: .foregroundBackground, backgroundIntensity: 0.37),
                    textCell: .init(characterSet: .binary, variant: .matrixRain, intensity: 0.82)
                ),
                outputSize: CGSize(width: 34, height: 27),
                expectedSHA256: "e44e45e14d79daec5fb6390dd848cd7f07b5fbf32950b47516cd0418c1772d10"
            ),
            Scenario(
                name: "fallback effect with monochrome dots styling",
                effect: .threshold,
                parameters: .textCell(
                    common: .init(brightness: 0.08, contrast: 1.36, saturation: 0.64, hueRotation: 40, gamma: 0.8),
                    geometry: .init(scale: 1.1, spacing: 0.7, outputWidth: 149),
                    color: .init(mode: .monochrome, backgroundIntensity: 0.23),
                    textCell: .init(characterSet: .blocks, variant: .dots, intensity: 0.74)
                ),
                outputSize: CGSize(width: 33, height: 25),
                expectedSHA256: "e11cc79d3b9c9727ecd33d16fe64336480ffa0f9513ac1d74b16304a99e12570"
            ),
            Scenario(
                name: "fallback effect with blockify source styling",
                effect: .threshold,
                parameters: .textCell(
                    common: .init(brightness: 0.04, contrast: 1.12, saturation: 1.31, hueRotation: 12, gamma: 1.1),
                    geometry: .init(scale: 1.25, spacing: 1.4, outputWidth: 187),
                    color: .init(mode: .source, backgroundIntensity: 0.61),
                    textCell: .init(characterSet: .classicASCII, variant: .blockify, intensity: 0.57)
                ),
                outputSize: CGSize(width: 35, height: 26),
                expectedSHA256: "f42846439e2c988e954a0d9dacbb913f921ac492673d17d56bc0edf88414a180"
            ),
        ]

        for scenario in scenarios {
            // Avoid OS-dependent interpolation in exact pixel baselines.
            let input = makeTestImage(
                width: Int(scenario.outputSize.width),
                height: Int(scenario.outputSize.height)
            )
            let output = try TextCellBucketRenderer.renderPreview(
                input: input,
                effect: scenario.effect,
                parameters: scenario.parameters,
                outputSize: scenario.outputSize
            )
            let digest = SHA256.hash(data: Data(readBytes(output)))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, scenario.expectedSHA256, scenario.name)
        }
    }

    /// For every GPUEffectKind, render the fixture through GPUEffectsPlatform
    /// and assert the output is structurally non-trivial: dimensions match
    /// the requested output size, and the image is not all zeros.
    func testAllEffectKindsDispatchAndRenderNonTrivialOutput() throws {
        let platform = try GPUEffectsPlatform.makeForTests()
        let input = makeTestImage()
        let outputSize = CGSize(width: input.width, height: input.height)

        for kind in GPUEffectKind.allCases {
            let params = makeParameters(for: kind)
            let output: CGImage
            do {
                output = try platform.renderPreview(
                    input: input,
                    effect: kind,
                    parameters: params,
                    outputSize: outputSize
                )
            } catch {
                XCTFail("\(kind.label): renderPreview threw — \(error)")
                continue
            }

            XCTAssertEqual(output.width, input.width,
                           "\(kind.label): width mismatch")
            XCTAssertEqual(output.height, input.height,
                           "\(kind.label): height mismatch")

            let bytes = readBytes(output)
            let nonZero = bytes.contains { $0 != 0 }
            XCTAssertTrue(nonZero, "\(kind.label): output is entirely black — renderer likely a no-op stub")
        }
    }

    /// Separate assertion: every bucket dispatch should produce an output that
    /// visibly differs from the raw input on this test fixture (if a renderer
    /// were missing-cased in the switch, it would often return the input
    /// verbatim, which the all-black check above misses).
    func testEveryEffectActuallyTransformsInput() throws {
        let platform = try GPUEffectsPlatform.makeForTests()
        let input = makeTestImage()
        let outputSize = CGSize(width: input.width, height: input.height)
        let inputBytes = readBytes(input)

        for kind in GPUEffectKind.allCases {
            let output = try platform.renderPreview(
                input: input,
                effect: kind,
                parameters: makeParameters(for: kind),
                outputSize: outputSize
            )
            let outputBytes = readBytes(output)
            let identical = outputBytes == inputBytes
            XCTAssertFalse(identical,
                           "\(kind.label): output is byte-identical to input — renderer pass-through, likely no-op dispatch")
        }
    }

    /// NoiseField now supports three noise primitives (value/IGN, simplex,
    /// cellular). Each must produce a visually distinct field — if the
    /// MSL switch is broken or a primitive silently aliases another, the
    /// outputs would match. Catches both regression in the dispatch and
    /// a silent CPU fallback (which would only ever produce the CPU's
    /// `value`-style output).
    func testNoiseFieldNoiseTypesProduceDistinctOutputs() throws {
        let platform = try GPUEffectsPlatform.makeForTests()
        let input = makeTestImage()
        let outputSize = CGSize(width: input.width, height: input.height)

        let common   = GPUEffectCommonParameters()
        let geometry = GPUEffectGeometryParameters()
        let color    = GPUEffectColorParameters(mode: .source, backgroundIntensity: 0.5)

        func render(_ noiseType: NoiseFieldType) throws -> [UInt8] {
            var payload = EdgeFieldParameters(variant: .noiseField)
            payload.noiseType = noiseType
            payload.lineStrength = 1.0
            payload.amplitude = 0.5
            payload.octaves = 3
            let params: GPUEffectParameters = .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)
            let out = try platform.renderPreview(input: input, effect: .noiseField, parameters: params, outputSize: outputSize)
            return readBytes(out)
        }

        let value    = try render(.value)
        let simplex  = try render(.simplex)
        let cellular = try render(.cellular)

        XCTAssertNotEqual(value,    simplex,  "value/IGN and simplex produce identical output — switch likely broken")
        XCTAssertNotEqual(value,    cellular, "value/IGN and cellular produce identical output — switch likely broken")
        XCTAssertNotEqual(simplex,  cellular, "simplex and cellular produce identical output — primitive collision")
    }

    /// Bucket fragments wrap their source sample in `applyCommonAdjustments`.
    /// Verify the dispatch reaches the helper by hue-rotating a saturated-red
    /// fixture and confirming the dot pixels (which carry source colour
    /// through to output) shift to a different hue. Only the dots variant is
    /// probed: VHS hardcodes intensity=1.0 so its `mix(srcOrig, scanned, 1)`
    /// drops srcOrig entirely and source-side adjustments don't surface.
    /// Bg dominates the byte count (most pixels are non-dot), so the
    /// threshold only requires "more than a few hundred bytes change" —
    /// enough to prove the wiring without depending on the dot fill ratio.
    func testCommonAdjustmentsAffectBucketOutput() throws {
        let platform = try GPUEffectsPlatform.makeForTests()
        let input = makeSolidColorImage(r: 220, g: 30, b: 30, width: 64, height: 64)
        let outputSize = CGSize(width: input.width, height: input.height)

        let neutralCommon = GPUEffectCommonParameters()
        var rotatedCommon = GPUEffectCommonParameters()
        rotatedCommon.hueRotation = 120.0
        let geometry = GPUEffectGeometryParameters()
        let color = GPUEffectColorParameters(mode: .source, backgroundIntensity: 0.5)

        let neutralParams: GPUEffectParameters =
            .textCell(common: neutralCommon, geometry: geometry, color: color, textCell: TextCellParameters(variant: .dots))
        let rotatedParams: GPUEffectParameters =
            .textCell(common: rotatedCommon, geometry: geometry, color: color, textCell: TextCellParameters(variant: .dots))

        let neutralOut = try platform.renderPreview(input: input, effect: .dots, parameters: neutralParams, outputSize: outputSize)
        let rotatedOut = try platform.renderPreview(input: input, effect: .dots, parameters: rotatedParams, outputSize: outputSize)

        let diffs = zip(readBytes(neutralOut), readBytes(rotatedOut)).filter { $0 != $1 }.count
        XCTAssertGreaterThan(diffs, 200,
                             "dots: only \(diffs) bytes differ between hueRotation=0 and 120 — applyCommonAdjustments not reaching the dot colour")
    }

    private func makeSolidColorImage(r: UInt8, g: UInt8, b: UInt8, width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            data[i * 4] = r
            data[i * 4 + 1] = g
            data[i * 4 + 2] = b
            data[i * 4 + 3] = 255
        }
        return ctx.makeImage()!
    }

    private func makeVHSPayload() -> GlitchParameters {
        var p = GlitchParameters(variant: .vhs)
        p.amount = 0.5
        p.distortion = 0.3
        p.colorBleed = 0.5
        p.scanlines = 0.5
        p.trackingError = 0.3
        return p
    }
}
