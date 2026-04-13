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
            return .glitch(common: common, geometry: geometry, color: color,
                           glitch: GlitchParameters(variant: .vhs))
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
}
