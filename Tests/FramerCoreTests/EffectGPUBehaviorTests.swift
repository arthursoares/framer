// EffectGPUBehaviorTests.swift
// GPU-only behavioral and invariant checks for the effect renderers:
// pixel-sort flag wiring (reverse / randomness / threshold-skip), dither
// output invariants (binary BW, two-tone, palette-only, per-channel levels),
// dispatch routing (Riemersma → CPU by design), and dimension smoke checks.
//
// Pixel-level regression coverage lives in EffectGPUGoldenTests (frozen
// golden references). This file was EffectGPUParityTests until the CPU
// effect path was retired — the CPU-vs-GPU comparisons it held are
// superseded by the goldens (docs/adr/2026-07-09-retire-cpu-effect-path.md).
//
// All tests skip themselves when Metal is unavailable
// (`MetalEffectLibrary.shared` is nil — Linux CI, sandboxed environments
// without GPU), except the Riemersma routing test, which runs the kept CPU
// implementation directly.
//
// Run on Mac via:
//   swift test --filter EffectGPUBehaviorTests

import XCTest
import CoreGraphics
@testable import FramerCore

final class EffectGPUBehaviorTests: XCTestCase {

    // MARK: - Shared test image

    private func makeTestImage(width: Int = 256, height: Int = 256) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                // Deterministic gradient + checkerboard so every effect has
                // structure to act on (edges for ASCII / Kuwahara, gradients
                // for halftone / palette snap, saturation for color grades).
                let r = UInt8((x * 13 + y * 7) % 256)
                let g = UInt8((x * 5 + y * 19) % 256)
                let b = UInt8(((x ^ y) * 11) % 256)
                let darkBlock = ((x / 16) + (y / 16)) % 2 == 0
                let dim: Double = darkBlock ? 0.6 : 1.0
                pixels[idx]     = UInt8(Double(r) * dim)
                pixels[idx + 1] = UInt8(Double(g) * dim)
                pixels[idx + 2] = UInt8(Double(b) * dim)
                pixels[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    // MARK: - Pixel comparison

    /// Returns (mean abs delta, max abs delta) over RGB channels (alpha ignored).
    /// Both values in 0..255 byte units.
    private func compare(_ a: CGImage, _ b: CGImage) -> (mean: Double, max: Int) {
        XCTAssertEqual(a.width, b.width, "width mismatch")
        XCTAssertEqual(a.height, b.height, "height mismatch")
        let width = a.width
        let height = a.height

        let ap = drawToBytes(a)
        let bp = drawToBytes(b)

        var totalDelta = 0
        var maxDelta = 0
        let n = width * height
        for i in 0..<n {
            for ch in 0..<3 {
                let delta = abs(Int(ap[i * 4 + ch]) - Int(bp[i * 4 + ch]))
                totalDelta += delta
                if delta > maxDelta { maxDelta = delta }
            }
        }
        let mean = Double(totalDelta) / Double(n * 3)
        return (mean, maxDelta)
    }

    private func drawToBytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    // MARK: - Skip helpers

    private func requireMetal() throws {
        guard MetalEffectLibrary.shared != nil else {
            throw XCTSkip("Metal device unavailable on this host (likely CI sandbox).")
        }
    }

    // MARK: - PixelSort flag wiring

    func testPixelSortDiagonalDirectionDoesntCrash() throws {
        try requireMetal()
        let img = makeTestImage()
        let ps = PixelSortShaderParams(direction: .diagonal)
        let params = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                       params: .pixelSort(ps))
        let gpu = try PixelSortRenderer.render(to: img, params: params)
        XCTAssertEqual(gpu.width, img.width)
        XCTAssertEqual(gpu.height, img.height)
    }

    func testPixelSortKimAsendorfModesProduceOutput() throws {
        try requireMetal()
        let img = makeTestImage()
        let modes: [PixelSortSpanMode] = [.kimBlack, .kimWhite, .kimBright, .kimDark]
        for mode in modes {
            let ps = PixelSortShaderParams(threshold: 0.5, spanMode: mode)
            let params = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                           params: .pixelSort(ps))
            let gpu = try PixelSortRenderer.render(to: img, params: params)
            XCTAssertEqual(gpu.width, img.width, "\(mode) wrong width")
            XCTAssertEqual(gpu.height, img.height, "\(mode) wrong height")
        }
    }

    func testPixelSortReverseFlipsSortOrder() throws {
        try requireMetal()
        let img = makeTestImage()
        let normal = PixelSortShaderParams(threshold: 0.3)
        let reversed = PixelSortShaderParams(threshold: 0.3, reverse: true)
        let normalParams = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                              params: .pixelSort(normal))
        let reversedParams = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                                params: .pixelSort(reversed))
        let gpuNormal = try PixelSortRenderer.render(to: img, params: normalParams)
        let gpuReversed = try PixelSortRenderer.render(to: img, params: reversedParams)
        // Reverse must produce different output from normal — if it didn't,
        // the reverse flag isn't reaching the shader.
        let (mean, _) = compare(gpuNormal, gpuReversed)
        XCTAssertGreaterThan(mean, 1.0,
                             "Reverse sort should differ from ascending sort (mean delta \(mean))")
    }

    func testPixelSortRandomnessChangesOutput() throws {
        try requireMetal()
        let img = makeTestImage()
        let plain = PixelSortShaderParams(threshold: 0.3, randomness: 0.0)
        let jittered = PixelSortShaderParams(threshold: 0.3, randomness: 1.0)
        let plainP = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                        params: .pixelSort(plain))
        let jitterP = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                         params: .pixelSort(jittered))
        let gpuPlain = try PixelSortRenderer.render(to: img, params: plainP)
        let gpuJitter = try PixelSortRenderer.render(to: img, params: jitterP)
        let (mean, _) = compare(gpuPlain, gpuJitter)
        XCTAssertGreaterThan(mean, 0.5,
                             "Randomness should perturb output (mean delta \(mean))")
    }

    func testPixelSortRespectsThresholdSkip() throws {
        try requireMetal()
        // Threshold = 1.0 — no pixel exceeds it, every pixel returns source.
        // GPU output must equal source pixel-for-pixel (subject to the CIContext
        // sRGB roundtrip, which can introduce ≤ 1-byte deltas).
        let img = makeTestImage()
        let ps = PixelSortShaderParams(threshold: 1.0)
        let params = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                       params: .pixelSort(ps))
        let gpu = try PixelSortRenderer.render(to: img, params: params)
        let (mean, max) = compare(img, gpu)
        XCTAssertLessThan(mean, 2.0, "PixelSort threshold-skip diverged from source (mean \(mean))")
        XCTAssertLessThan(max, 8, "PixelSort threshold-skip max delta too high (\(max))")
    }

    // MARK: - Dither
    //
    // Dither output is noise-like, so these tests assert structure rather
    // than exact pixels: output dimensions, output range (binary for bw
    // mode), palette membership, per-channel quantization grid, and the
    // Riemersma explicit CPU dispatch.

    func testDitherBayerOutputIsBinaryBW() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .bw,
                                       bayerLevel: 2, pixelScale: 1,
                                       threshold: 0.5)
        let gpu = try DitherGPURenderer.apply(to: img, params: params)
        XCTAssertEqual(gpu.width, img.width)
        XCTAssertEqual(gpu.height, img.height)

        // BW output: every pixel's RGB should be either ~0 or ~255 (allowing
        // sRGB-roundtrip slop of a few bytes).
        let bytes = drawToBytes(gpu)
        var binaryViolations = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[i]
            if r > 8 && r < 247 { binaryViolations += 1 }
        }
        // Allow ≤ 1% non-binary pixels (sub-pixel sampling at edges).
        let pixelCount = bytes.count / 4
        XCTAssertLessThan(binaryViolations, pixelCount / 100,
                          "Bayer mono dither produced too many non-binary pixels (\(binaryViolations)/\(pixelCount))")
    }

    func testDitherTwoToneMapsToColors() throws {
        try requireMetal()
        let img = makeTestImage()
        let fg = try CodableColor(hex: "#FF0000")  // pure red
        let bg = try CodableColor(hex: "#0000FF")  // pure blue
        let params = DitherLayerParams(algorithm: .floydSteinberg,
                                       colorMode: .twoTone(foreground: fg, background: bg),
                                       bayerLevel: 2, pixelScale: 1, threshold: 0.5)
        let gpu = try DitherGPURenderer.apply(to: img, params: params)
        let bytes = drawToBytes(gpu)
        var redCount = 0, blueCount = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[i], g = bytes[i + 1], b = bytes[i + 2]
            if r > 200 && g < 50 && b < 50 { redCount += 1 }
            else if r < 50 && g < 50 && b > 200 { blueCount += 1 }
        }
        let pixelCount = bytes.count / 4
        XCTAssertGreaterThan(redCount + blueCount, pixelCount * 95 / 100,
                             "TwoTone output should be predominantly fg/bg (got red=\(redCount) blue=\(blueCount) of \(pixelCount))")
    }

    func testDitherRiemersmaRoutesToCPU() throws {
        // Riemersma has no GPU implementation (inherently serial Hilbert-curve
        // error history); the public `apply` dispatches it to the kept CPU
        // implementation BY ALGORITHM — an explicit capability route, not an
        // error-triggered fallback (the CPU dither path was otherwise retired,
        // docs/adr/2026-07-09-retire-cpu-effect-path.md). Runs without Metal.
        let img = makeTestImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .riemersma, colorMode: .bw,
                                       bayerLevel: 2, pixelScale: 1, threshold: 0.5)
        let result = try DitherRenderer.apply(to: img, params: params)
        XCTAssertEqual(result.width, img.width)
        XCTAssertEqual(result.height, img.height)
        // Make sure it actually ran (not pass-through): bw output must be binary.
        let bytes = drawToBytes(result)
        var binary = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[i] < 8 || bytes[i] > 247 { binary += 1 }
        }
        XCTAssertGreaterThan(binary, bytes.count / 4 * 90 / 100,
                             "Riemersma CPU route didn't actually dither (got \(binary) binary pixels)")
    }

    func testDitherSierraOutputIsBinaryBW() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = DitherLayerParams(algorithm: .sierra, colorMode: .bw,
                                       bayerLevel: 2, pixelScale: 1, threshold: 0.5)
        let gpu = try DitherGPURenderer.apply(to: img, params: params)
        XCTAssertEqual(gpu.width, img.width)
        let bytes = drawToBytes(gpu)
        var nonBinary = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[i] > 8 && bytes[i] < 247 { nonBinary += 1 }
        }
        XCTAssertLessThan(nonBinary, bytes.count / 4 / 100,
                          "Sierra mono dither produced too many non-binary pixels (\(nonBinary))")
    }

    func testDitherIGNAlgorithmRouts() throws {
        try requireMetal()
        let img = makeTestImage()
        // Just verify the new IGN algorithm doesn't crash and produces dithered
        // output. Exact noise pattern depends on the IGN function — checking
        // structural properties only.
        let params = DitherLayerParams(algorithm: .interleavedGradientNoise,
                                       colorMode: .bw, bayerLevel: 2,
                                       pixelScale: 1, threshold: 0.5)
        let gpu = try DitherGPURenderer.apply(to: img, params: params)
        let bytes = drawToBytes(gpu)
        var binary = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[i] < 8 || bytes[i] > 247 { binary += 1 }
        }
        XCTAssertGreaterThan(binary, bytes.count / 4 * 95 / 100,
                             "IGN dither output should be near-binary (\(binary)/\(bytes.count / 4))")
    }

    func testDitherPaletteUsesOnlyPaletteColors() throws {
        try requireMetal()
        let img = makeTestImage()
        let palette = VintagePalette.gameBoy
        let params = DitherLayerParams(algorithm: .floydSteinberg,
                                       colorMode: .palette(palette),
                                       bayerLevel: 2, pixelScale: 1, threshold: 0.5)
        let gpu = try DitherGPURenderer.apply(to: img, params: params)

        // Every output pixel should be one of the 4 GameBoy greens (allowing
        // ±2 byte sRGB-roundtrip slop per channel). Count palette hits.
        let bytes = drawToBytes(gpu)
        let paletteRGB: [(UInt8, UInt8, UInt8)] = palette.map {
            (UInt8(round($0.red * 255)), UInt8(round($0.green * 255)), UInt8(round($0.blue * 255)))
        }
        var inPalette = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[i], g = bytes[i + 1], b = bytes[i + 2]
            for (pr, pg, pb) in paletteRGB {
                if abs(Int(r) - Int(pr)) <= 3 && abs(Int(g) - Int(pg)) <= 3 && abs(Int(b) - Int(pb)) <= 3 {
                    inPalette += 1
                    break
                }
            }
        }
        let pixelCount = bytes.count / 4
        XCTAssertGreaterThan(inPalette, pixelCount * 95 / 100,
                             "Palette dither emitted too many off-palette pixels (\(inPalette)/\(pixelCount))")
    }

    func testDitherCMYKHalftoneRendersOnGPU() throws {
        // CMYK halftone is GPU-only; the degraded monochrome CPU fallback was
        // deleted with the CPU-path retirement — on a Metal-less host this
        // algorithm now throws instead of silently rendering mono.
        try requireMetal()
        let img = makeTestImage(width: 64, height: 64)
        let params = DitherLayerParams(algorithm: .cmykHalftone, colorMode: .bw,
                                       bayerLevel: 2, pixelScale: 1, threshold: 0.5)
        let result = try DitherRenderer.apply(to: img, params: params)
        XCTAssertEqual(result.width, img.width)
        XCTAssertEqual(result.height, img.height)
    }

    func testDitherColorLevelsQuantizesPerChannel() throws {
        try requireMetal()
        let img = makeTestImage()
        let levels = 4
        let params = DitherLayerParams(algorithm: .bayer, colorMode: .color(levels: levels),
                                       bayerLevel: 2, pixelScale: 1, threshold: 0.5)
        let gpu = try DitherGPURenderer.apply(to: img, params: params)
        let bytes = drawToBytes(gpu)

        // With `levels` per channel, each channel byte should snap to one of
        // `levels` evenly-spaced values: round(i * 255 / (levels - 1)).
        let allowedValues = (0..<levels).map { UInt8(round(Double($0) * 255.0 / Double(levels - 1))) }
        let allowedSet = Set(allowedValues)
        var offGrid = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            for ch in 0..<3 {
                if !allowedSet.contains(bytes[i + ch]) {
                    // Allow ±1 byte tolerance for sRGB roundtrip slop.
                    let v = Int(bytes[i + ch])
                    let near = allowedValues.contains { abs(Int($0) - v) <= 1 }
                    if !near { offGrid += 1 }
                }
            }
        }
        let totalChannels = (bytes.count / 4) * 3
        XCTAssertLessThan(offGrid, totalChannels / 100,
                          "Color-levels output had too many off-grid values (\(offGrid)/\(totalChannels))")
    }

    // MARK: - Smoke: all GPU paths return same-sized output

    func testGPUOutputDimensionsMatchInput() throws {
        try requireMetal()
        let img = makeTestImage(width: 200, height: 150)
        let params: [(ShaderLayerParams, () throws -> CGImage)] = [
            (ShaderLayerParams(style: .crimewave, intensity: 0.5,
                               params: .crimewave(CrimewaveShaderParams())),
             { try ColorGradeRenderer.renderCrimewave(
                to: img,
                params: ShaderLayerParams(style: .crimewave, intensity: 0.5,
                                          params: .crimewave(CrimewaveShaderParams()))) }),
            (ShaderLayerParams(style: .crt, intensity: 1.0, params: .crt(CRTShaderParams())),
             { try CRTRenderer.render(
                to: img,
                params: ShaderLayerParams(style: .crt, intensity: 1.0,
                                          params: .crt(CRTShaderParams()))) }),
        ]
        for (_, runGPU) in params {
            let out = try runGPU()
            XCTAssertEqual(out.width, img.width)
            XCTAssertEqual(out.height, img.height)
        }
    }

    // MARK: - RoughBorder invariants

    private func roughBorderParams(
        size: Double = 0.08, spread: Double = 0.5, roughness: Double = 0.5,
        seed: Int = 42, color: CodableColor = .white
    ) -> ShaderLayerParams {
        ShaderLayerParams(
            style: .roughBorder, intensity: 1.0,
            params: .roughBorder(RoughBorderShaderParams(
                size: size, spread: spread, roughness: roughness,
                seed: seed, borderColor: color))
        )
    }

    func testRoughBorderSameSeedIsDeterministic() throws {
        try requireMetal()
        let img = makeTestImage()
        let a = try RoughBorderRenderer.render(to: img, params: roughBorderParams(seed: 2201))
        let b = try RoughBorderRenderer.render(to: img, params: roughBorderParams(seed: 2201))
        let (mean, maxDelta) = compare(a, b)
        XCTAssertEqual(maxDelta, 0,
                       "Same seed must reproduce the identical border (mean \(mean), max \(maxDelta))")
    }

    func testRoughBorderDifferentSeedsVary() throws {
        try requireMetal()
        let img = makeTestImage()
        let a = try RoughBorderRenderer.render(to: img, params: roughBorderParams(seed: 1))
        let b = try RoughBorderRenderer.render(to: img, params: roughBorderParams(seed: 2))
        let (mean, _) = compare(a, b)
        XCTAssertGreaterThan(mean, 0.05,
                             "Different seeds should produce different borders (mean delta \(mean))")
    }

    func testRoughBorderCornersAreBorderColorAndCenterUntouched() throws {
        try requireMetal()
        let img = makeTestImage()
        let out = try RoughBorderRenderer.render(to: img, params: roughBorderParams())
        let bytes = drawToBytes(out)
        let src = drawToBytes(img)
        let w = out.width, h = out.height

        // Corner pixel sits well inside the border band (d≈0 < any threshold).
        let cornerIdx = 0
        XCTAssertGreaterThan(bytes[cornerIdx], 250, "corner should be border white (r)")
        XCTAssertGreaterThan(bytes[cornerIdx + 1], 250, "corner should be border white (g)")
        XCTAssertGreaterThan(bytes[cornerIdx + 2], 250, "corner should be border white (b)")

        // Center pixel is far outside the border reach (max threshold
        // 0.08 * (1 + 0.5) = 0.12 of min dim; center is at 0.5).
        let centerIdx = ((h / 2) * w + (w / 2)) * 4
        for ch in 0..<3 {
            let delta = abs(Int(bytes[centerIdx + ch]) - Int(src[centerIdx + ch]))
            XCTAssertLessThanOrEqual(delta, 2,
                                     "center pixel should pass through unchanged (ch \(ch) delta \(delta))")
        }
    }

    func testRoughBorderThicknessIsProportionalAcrossAspectRatios() throws {
        try requireMetal()
        // Same min-dimension, different aspect: the border band measured
        // along the vertical centerline (in units of min dim) must match,
        // because thickness is defined in min(w,h) units.
        let square = makeTestImage(width: 256, height: 256)
        let wide = makeTestImage(width: 512, height: 256)
        // spread 0 → clean straight border: thickness is exactly `size`.
        let p = roughBorderParams(size: 0.1, spread: 0.0)
        let outSquare = try RoughBorderRenderer.render(to: square, params: p)
        let outWide = try RoughBorderRenderer.render(to: wide, params: p)

        func topBorderRows(_ image: CGImage) -> Int {
            let bytes = drawToBytes(image)
            let w = image.width
            let x = w / 2
            var rows = 0
            for y in 0..<image.height {
                let idx = (y * w + x) * 4
                if bytes[idx] > 250 && bytes[idx + 1] > 250 && bytes[idx + 2] > 250 {
                    rows += 1
                } else {
                    break
                }
            }
            return rows
        }

        let sqRows = topBorderRows(outSquare)
        let wideRows = topBorderRows(outWide)
        // 0.1 × 256 = ~26 rows on both, independent of the width.
        XCTAssertGreaterThan(sqRows, 20, "square top border missing (\(sqRows) rows)")
        XCTAssertLessThanOrEqual(abs(sqRows - wideRows), 2,
                                 "border thickness should be aspect-independent (square \(sqRows) vs wide \(wideRows))")
    }

    func testRoughBorderShapeScalesWithResolution() throws {
        try requireMetal()
        // Doubling resolution must not change the border's relative
        // thickness: measure top-border rows as a fraction of height.
        let small = makeTestImage(width: 128, height: 128)
        let large = makeTestImage(width: 256, height: 256)
        let p = roughBorderParams(size: 0.1, spread: 0.0)
        let outSmall = try RoughBorderRenderer.render(to: small, params: p)
        let outLarge = try RoughBorderRenderer.render(to: large, params: p)

        func topBorderFraction(_ image: CGImage) -> Double {
            let bytes = drawToBytes(image)
            let w = image.width
            let x = w / 2
            var rows = 0
            for y in 0..<image.height {
                let idx = (y * w + x) * 4
                if bytes[idx] > 250 && bytes[idx + 1] > 250 && bytes[idx + 2] > 250 {
                    rows += 1
                } else {
                    break
                }
            }
            return Double(rows) / Double(image.height)
        }

        let smallFrac = topBorderFraction(outSmall)
        let largeFrac = topBorderFraction(outLarge)
        XCTAssertEqual(smallFrac, largeFrac, accuracy: 0.02,
                       "border fraction should be resolution-independent (\(smallFrac) vs \(largeFrac))")
    }

    func testRoughBorderAllTypesRenderDeterministicallyAndDistinctly() throws {
        try requireMetal()
        let img = makeTestImage(width: 192, height: 192)

        var outputs: [RoughBorderType: CGImage] = [:]
        for type in RoughBorderType.allCases {
            let p = RoughBorderShaderParams(
                borderType: type, size: 0.08, spread: 0.6, roughness: 0.6, seed: 7)
            let layer = ShaderLayerParams(style: .roughBorder, intensity: 1.0,
                                          params: .roughBorder(p))
            let a = try RoughBorderRenderer.render(to: img, params: layer)
            let b = try RoughBorderRenderer.render(to: img, params: layer)
            XCTAssertEqual(a.width, img.width, "\(type) wrong width")
            let (_, maxDelta) = compare(a, b)
            XCTAssertEqual(maxDelta, 0, "\(type) not deterministic")
            outputs[type] = a
        }

        // Every type must be visually distinct from every other at the same
        // settings — if two recipes render identically, one of them isn't
        // wired to the switch.
        let all = RoughBorderType.allCases
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                let (mean, _) = compare(outputs[all[i]]!, outputs[all[j]]!)
                XCTAssertGreaterThan(
                    mean, 0.01,
                    "\(all[i]) and \(all[j]) render identically (mean delta \(mean))")
            }
        }
    }

    func testRoughBorderVaryPerImageDerivesStableSeedFromIdentity() throws {
        try requireMetal()
        let img = makeTestImage()
        var p = RoughBorderShaderParams(size: 0.08, spread: 0.5, roughness: 0.5, seed: 42)
        p.varyPerImage = true
        let layer = ShaderLayerParams(style: .roughBorder, intensity: 1.0, params: .roughBorder(p))

        let a1 = try RoughBorderRenderer.render(to: img, params: layer, sourceIdentity: "IMG_0001.jpg")
        let a2 = try RoughBorderRenderer.render(to: img, params: layer, sourceIdentity: "IMG_0001.jpg")
        let b = try RoughBorderRenderer.render(to: img, params: layer, sourceIdentity: "IMG_0002.jpg")

        let (_, sameMax) = compare(a1, a2)
        XCTAssertEqual(sameMax, 0, "same identity must reproduce the identical border")
        let (diffMean, _) = compare(a1, b)
        XCTAssertGreaterThan(diffMean, 0.05,
                             "different identities should produce different borders (mean \(diffMean))")

        // Toggle off: identity must be ignored.
        var off = p; off.varyPerImage = false
        let offLayer = ShaderLayerParams(style: .roughBorder, intensity: 1.0, params: .roughBorder(off))
        let c1 = try RoughBorderRenderer.render(to: img, params: offLayer, sourceIdentity: "IMG_0001.jpg")
        let c2 = try RoughBorderRenderer.render(to: img, params: offLayer, sourceIdentity: "IMG_0002.jpg")
        let (_, offMax) = compare(c1, c2)
        XCTAssertEqual(offMax, 0, "with varyPerImage off, identity must not affect the border")
    }

    // MARK: - FilmGrain invariants

    private func filmGrainParams(
        stock: FilmGrainStock = .custom, grainsPerPixel: Double? = nil,
        softness: Double? = nil, protectHighlights: Double = 0.15,
        protectShadows: Double = 0.15, seed: Int = 7, intensity: Double = 1.0
    ) -> ShaderLayerParams {
        ShaderLayerParams(
            style: .filmGrain, intensity: intensity,
            params: .filmGrain(FilmGrainShaderParams(
                stock: stock, grainsPerPixel: grainsPerPixel, softness: softness,
                protectHighlights: protectHighlights, protectShadows: protectShadows,
                seed: seed))
        )
    }

    func testFilmGrainDeterministicPerSeedAndVariesAcrossSeeds() throws {
        try requireMetal()
        let img = makeTestImage()
        let a1 = try FilmGrainRenderer.render(to: img, params: filmGrainParams(seed: 42))
        let a2 = try FilmGrainRenderer.render(to: img, params: filmGrainParams(seed: 42))
        let b = try FilmGrainRenderer.render(to: img, params: filmGrainParams(seed: 43))
        let (_, sameMax) = compare(a1, a2)
        XCTAssertEqual(sameMax, 0, "same seed must reproduce the identical grain field")
        let (diffMean, _) = compare(a1, b)
        XCTAssertGreaterThan(diffMean, 0.05, "different seeds should differ (mean \(diffMean))")
    }

    func testFilmGrainActuallyGrainsAndDensityMatters() throws {
        try requireMetal()
        let img = makeTestImage()
        let fine = try FilmGrainRenderer.render(to: img, params: filmGrainParams(grainsPerPixel: 500))
        let chunky = try FilmGrainRenderer.render(to: img, params: filmGrainParams(grainsPerPixel: 30))
        let (fineMean, _) = compare(img, fine)
        XCTAssertGreaterThan(fineMean, 0.3, "fine grain should visibly alter the image")
        let (densityMean, _) = compare(fine, chunky)
        XCTAssertGreaterThan(densityMean, 0.5,
                             "grains-per-pixel should change the grain character (mean \(densityMean))")
    }

    func testFilmGrainProtectsTonalExtremes() throws {
        try requireMetal()
        // Flat near-white image with full highlight protection: grain must
        // be (near) absent. Same with protection off: grain must appear.
        let width = 128, height = 128
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = ctx.makeImage()!

        let protected = try FilmGrainRenderer.render(
            to: white, params: filmGrainParams(protectHighlights: 1.0))
        let unprotected = try FilmGrainRenderer.render(
            to: white, params: filmGrainParams(protectHighlights: 0.0))
        let (protMean, _) = compare(white, protected)
        let (openMean, _) = compare(white, unprotected)
        XCTAssertLessThan(protMean, 0.5,
                          "protected highlights should carry almost no grain (mean \(protMean))")
        XCTAssertGreaterThan(openMean, protMean * 2,
                             "disabling protection should let grain through (\(openMean) vs \(protMean))")
    }

    func testFilmGrainStockProfileApplies() {
        // Picking a stock re-tunes the dials to its profile; sliders stay
        // editable afterwards. No Metal needed.
        let start = FilmGrainShaderParams(stock: .custom, grainsPerPixel: 111, softness: 0.9)
        let triX = start.applyingStockProfile(.kodakTriX400)
        XCTAssertEqual(triX.stock, .kodakTriX400)
        XCTAssertEqual(triX.grainsPerPixel, FilmGrainStock.kodakTriX400.grainProfile.grainsPerPixel)
        XCTAssertEqual(triX.softness, FilmGrainStock.kodakTriX400.grainProfile.softness)
    }

    func testFilmGrainSoftnessChangesCharacter() throws {
        try requireMetal()
        // Isolate softness (Codex review on PR #18): hold density fixed at a
        // chunky pitch so the hard-specks vs soft-blobs kernels are visibly
        // different — if the renderer dropped the softness uniform, these
        // renders would be identical.
        let img = makeTestImage()
        let hard = try FilmGrainRenderer.render(
            to: img, params: filmGrainParams(grainsPerPixel: 40, softness: 0.0))
        let soft = try FilmGrainRenderer.render(
            to: img, params: filmGrainParams(grainsPerPixel: 40, softness: 1.0))
        let (mean, _) = compare(hard, soft)
        XCTAssertGreaterThan(mean, 0.3,
                             "softness should change grain character (mean delta \(mean))")
    }

    func testFilmGrainPreviewBaseDimensionScalesGrain() throws {
        try requireMetal()
        // Lock the preview→export pitch compensation (Codex review on PR
        // #18): with previewBase = half the render size, pitchScale is 2 and
        // the grain lattice must coarsen; with previewBase == render size,
        // pitchScale is 1 and output must be byte-identical to the nil path.
        let img = makeTestImage()
        let p = filmGrainParams(grainsPerPixel: 250)
        let plain = try FilmGrainRenderer.render(to: img, params: p)
        let scaled = try FilmGrainRenderer.render(to: img, params: p, previewBaseDimension: 128)
        let neutral = try FilmGrainRenderer.render(to: img, params: p, previewBaseDimension: 256)

        let (scaledMean, _) = compare(plain, scaled)
        XCTAssertGreaterThan(scaledMean, 0.3,
                             "previewBase at half size should coarsen the grain (mean \(scaledMean))")
        let (neutralMax) = compare(plain, neutral).max
        XCTAssertEqual(neutralMax, 0,
                       "previewBase equal to render size must not alter the grain")
    }

    func testFilmGrainStockProfilesArePairwiseDistinct() {
        // Two stocks with the same (grainsPerPixel, softness) render
        // identically — a silent duplicate in the catalog (Retro 80S and
        // Delta 100 shipped as exact twins before this lock).
        let stocks = FilmGrainStock.allCases
        for i in 0..<stocks.count {
            for j in (i + 1)..<stocks.count {
                let a = stocks[i].grainProfile
                let b = stocks[j].grainProfile
                XCTAssertFalse(
                    a.grainsPerPixel == b.grainsPerPixel && a.softness == b.softness,
                    "\(stocks[i]) and \(stocks[j]) share an identical grain profile")
            }
        }
    }

    func testFilmGrainUnknownStockDecodesToCustomInsteadOfThrowing() throws {
        // Forward-compat: same preset-deletion guard as the border type.
        let layer = ShaderLayerParams(style: .filmGrain, params: .filmGrain(FilmGrainShaderParams()))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(layer)) as! [String: Any]
        var paramsObj = json["params"] as! [String: Any]
        var inner = paramsObj["params"] as! [String: Any]
        inner["stock"] = "kodakFuture9000"
        paramsObj["params"] = inner
        json["params"] = paramsObj
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .filmGrain(let p) = decoded.params else { return XCTFail("style lost") }
        XCTAssertEqual(p.stock, .custom, "unknown stock must fall back, not throw")
    }

    func testFilmGrainRoundTripsThroughJSON() throws {
        // All fields non-default so a dropped encode key can't hide behind
        // decode fallbacks (same discipline as the rough-border round-trip).
        var original = FilmGrainShaderParams(
            stock: .ilfordDelta3200, grainsPerPixel: 77, softness: 0.9,
            protectHighlights: 0.6, protectShadows: 0.4, seed: 4242)
        original.varyPerImage = true
        let layer = ShaderLayerParams(style: .filmGrain, params: .filmGrain(original))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .filmGrain(let roundTripped) = decoded.params else {
            return XCTFail("style did not round-trip")
        }
        XCTAssertEqual(roundTripped, original)
    }

    func testRoughBorderUnknownTypeDecodesToType3InsteadOfThrowing() throws {
        // Forward-compat: a preset written by a future version with a new
        // border type must not throw — PresetStore deletes files that fail
        // to decode (house rule 4).
        let layer = ShaderLayerParams(style: .roughBorder, params: .roughBorder(RoughBorderShaderParams()))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(layer)) as! [String: Any]
        var paramsObj = json["params"] as! [String: Any]
        var inner = paramsObj["params"] as! [String: Any]
        inner["borderType"] = "type99"
        paramsObj["params"] = inner
        json["params"] = paramsObj
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .roughBorder(let p) = decoded.params else { return XCTFail("style lost") }
        XCTAssertEqual(p.borderType, .type3, "unknown border type must fall back, not throw")
    }

    func testRoughBorderRoundTripsThroughJSON() throws {
        // Codable round-trip (preset safety, house rule 4). No Metal needed.
        // Every field must be NON-default (Codex review on PR #17): with
        // default values, an accidentally dropped key still round-trips via
        // the decode fallback and the regression goes unseen — a user preset
        // saved as Type 14 + vary-per-image would silently reopen as Type 3.
        let original = RoughBorderShaderParams(
            borderType: .type14,
            size: 0.12, spread: 0.79, roughness: 0.67, seed: 2201,
            varyPerImage: true,
            borderColor: .white)
        let layer = ShaderLayerParams(style: .roughBorder, params: .roughBorder(original))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .roughBorder(let roundTripped) = decoded.params else {
            return XCTFail("style did not round-trip")
        }
        XCTAssertEqual(roundTripped, original)
    }

    func testRoughBorderTypeShaderIndicesAreLocked() {
        // The enum label ↔ shader recipe mapping is load-bearing: a swapped
        // shaderIndex would render the wrong recipe under a correct label
        // while every behavioral test still passes (all outputs remain
        // distinct). Lock the full table (Codex review on PR #17).
        let expected: [RoughBorderType: Int] = [
            .type1: 1, .type2: 2, .type3: 3, .type4: 4, .type5: 5,
            .type6: 6, .type7: 7, .type8: 8, .type9: 9, .type10: 10,
            .type11: 11, .type12: 12, .type13: 13, .type14: 14,
        ]
        for (type, index) in expected {
            XCTAssertEqual(type.shaderIndex, index, "\(type) maps to wrong shader recipe")
        }
    }

    func testRoughBorderNoisyShapeIsResolutionIndependent() throws {
        try requireMetal()
        // Unlike testRoughBorderShapeScalesWithResolution (spread 0, straight
        // edge), this locks the NOISY path: with spread on, the displaced
        // boundary must still be a pure function of normalized position, so
        // the border-depth profile measured at the same normalized columns
        // must match across resolutions (Codex review on PR #17 — a shader
        // regression from normalized to raw pixel coords would pass the
        // spread-0 test).
        let p = ShaderLayerParams(
            style: .roughBorder, intensity: 1.0,
            params: .roughBorder(RoughBorderShaderParams(
                borderType: .type3, size: 0.1, spread: 0.6, roughness: 0.5,
                seed: 7, borderColor: .white)))
        let outSmall = try RoughBorderRenderer.render(to: makeTestImage(width: 128, height: 128), params: p)
        let outLarge = try RoughBorderRenderer.render(to: makeTestImage(width: 256, height: 256), params: p)

        func topBorderFraction(_ image: CGImage, atNormalizedX x: Double) -> Double {
            let bytes = drawToBytes(image)
            let w = image.width
            let col = min(w - 1, Int(Double(w) * x))
            var rows = 0
            for y in 0..<image.height {
                let idx = (y * w + col) * 4
                if bytes[idx] > 250 && bytes[idx + 1] > 250 && bytes[idx + 2] > 250 {
                    rows += 1
                } else {
                    break
                }
            }
            return Double(rows) / Double(image.height)
        }

        for x in [0.2, 0.35, 0.5, 0.65, 0.8] {
            let small = topBorderFraction(outSmall, atNormalizedX: x)
            let large = topBorderFraction(outLarge, atNormalizedX: x)
            XCTAssertEqual(small, large, accuracy: 0.03,
                           "noisy border depth at x=\(x) drifts across resolutions (\(small) vs \(large))")
        }
    }
    // MARK: - BWFilm invariants

    private func bwParams(_ p: BWFilmShaderParams, intensity: Double = 1.0) -> ShaderLayerParams {
        ShaderLayerParams(style: .bwFilm, intensity: intensity, params: .bwFilm(p))
    }

    func testBWFilmOutputIsMonochrome() throws {
        try requireMetal()
        let img = makeTestImage()
        let out = try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams()))
        let bytes = drawToBytes(out)
        var maxChannelSpread = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
            maxChannelSpread = max(maxChannelSpread,
                                   max(abs(r - g), max(abs(g - b), abs(r - b))))
        }
        XCTAssertLessThanOrEqual(maxChannelSpread, 1,
                                 "B&W output must be achromatic (spread \(maxChannelSpread))")
    }

    func testBWFilmSensitivityShiftsHueFamilies() throws {
        try requireMetal()
        // Left half pure red, right half pure blue. Boosting red sensitivity
        // must brighten the red half relative to suppressing it; the blue
        // half must stay (nearly) unchanged by the red dial.
        let width = 128, height = 64
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        let img = ctx.makeImage()!

        func meanLuma(_ image: CGImage, xRange: Range<Int>) -> Double {
            let bytes = drawToBytes(image)
            var total = 0.0, n = 0.0
            for y in 0..<image.height {
                for x in xRange {
                    total += Double(bytes[(y * image.width + x) * 4])
                    n += 1
                }
            }
            return total / n
        }

        let boosted = try BWFilmRenderer.render(
            to: img, params: bwParams(BWFilmShaderParams(sensRed: 100)))
        let cut = try BWFilmRenderer.render(
            to: img, params: bwParams(BWFilmShaderParams(sensRed: -100)))

        let redBoosted = meanLuma(boosted, xRange: 0..<(width / 2))
        let redCut = meanLuma(cut, xRange: 0..<(width / 2))
        XCTAssertGreaterThan(redBoosted, redCut + 30,
                             "red sensitivity should govern red rendering (\(redBoosted) vs \(redCut))")

        let blueBoosted = meanLuma(boosted, xRange: (width / 2)..<width)
        let blueCut = meanLuma(cut, xRange: (width / 2)..<width)
        XCTAssertLessThanOrEqual(abs(blueBoosted - blueCut), 6,
                                 "red dial should not move blue rendering (\(blueBoosted) vs \(blueCut))")
    }

    func testBWFilmBrightnessAndContrastBehave() throws {
        try requireMetal()
        let img = makeTestImage()
        func stats(_ image: CGImage) -> (mean: Double, spread: Double) {
            let bytes = drawToBytes(image)
            var total = 0.0, n = 0.0
            for i in stride(from: 0, to: bytes.count, by: 4) { total += Double(bytes[i]); n += 1 }
            let mean = total / n
            var dev = 0.0
            for i in stride(from: 0, to: bytes.count, by: 4) { dev += abs(Double(bytes[i]) - mean) }
            return (mean, dev / n)
        }
        let neutral = stats(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams())))
        let bright = stats(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams(brightness: 60))))
        let punchy = stats(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams(contrast: 80))))
        XCTAssertGreaterThan(bright.mean, neutral.mean + 10, "brightness should raise mean luma")
        XCTAssertGreaterThan(punchy.spread, neutral.spread + 5, "contrast should widen the tonal spread")
    }

    func testBWFilmCurveBlackLiftRaisesFloor() throws {
        try requireMetal()
        let img = makeTestImage()
        let lifted = try BWFilmRenderer.render(
            to: img, params: bwParams(BWFilmShaderParams(curveLowY: 0.2)))
        let bytes = drawToBytes(lifted)
        var minLuma = 255
        for i in stride(from: 0, to: bytes.count, by: 4) { minLuma = min(minLuma, Int(bytes[i])) }
        XCTAssertGreaterThanOrEqual(minLuma, 44,
                                    "black lift 0.2 should floor output near 51/255 (min \(minLuma))")
    }

    func testBWFilmCurveBakeSortsUnsortedPoints() {
        // SEP stores curve points UNSORTED — the bake must sort by x.
        let sorted = BWFilmShaderParams(
            curvePoints: [BWCurvePoint(x: 0.25, y: 0.2), BWCurvePoint(x: 0.75, y: 0.85)])
        let unsorted = BWFilmShaderParams(
            curvePoints: [BWCurvePoint(x: 0.75, y: 0.85), BWCurvePoint(x: 0.25, y: 0.2)])
        XCTAssertEqual(BWFilmRenderer.bakeCurve(sorted), BWFilmRenderer.bakeCurve(unsorted))
        // And the identity bake really is identity.
        let identity = BWFilmRenderer.bakeCurve(BWFilmShaderParams())
        XCTAssertEqual(identity.count, 256)
        // Assert the QUARTER points too — the endpoint-duplication bug bent
        // the default curve into an S that passed midpoint/endpoint checks.
        for i in [0, 32, 64, 128, 192, 224, 255] {
            XCTAssertEqual(identity[i], Float(i) / 255.0, accuracy: 0.005,
                           "default curve must be identity at \(i)")
        }
    }

    func testBWFilmResponseProfilesArePairwiseDistinctAndApply() throws {
        // No two films may share an identical spectral profile (the film-
        // grain catalog shipped exact twins once — same lock here), and
        // applying a response must set all six dials while leaving
        // tonality/curve untouched.
        let all = BWFilmResponse.allCases
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                XCTAssertFalse(all[i].sensitivities == all[j].sensitivities,
                               "\(all[i]) and \(all[j]) share an identical response profile")
            }
        }
        let start = BWFilmShaderParams(sensRed: 99, contrast: 42, curveGamma: 0.3)
        let ortho = start.applyingResponse(.rolleiOrtho25)
        XCTAssertEqual(ortho.response, .rolleiOrtho25)
        XCTAssertEqual(ortho.sensRed, BWFilmResponse.rolleiOrtho25.sensitivities.r)
        XCTAssertEqual(ortho.contrast, 42, "tonality must survive a response change")
        // A film's Levels & Curves is part of its character: unmeasured
        // films reset the curve to identity...
        XCTAssertEqual(ortho.curveGamma, 0, "film selection replaces the curve")
        XCTAssertTrue(ortho.curvePoints.isEmpty)
        // ...measured films install their measured curve...
        let triX = start.applyingResponse(.kodakTriX400)
        XCTAssertFalse(triX.curvePoints.isEmpty, "measured film must install its curve")
        XCTAssertEqual(triX.curvePoints.count, 7)
        // ...and .custom leaves the user's curve untouched.
        let backToCustom = triX.applyingResponse(.custom)
        XCTAssertEqual(backToCustom.curvePoints.count, 7, "custom must not clear the curve")
    }

    func testBWFilmOrthoRendersRedDarkerThanNeutral() throws {
        try requireMetal()
        // Red-blind orthochromatic film: a red patch must render clearly
        // darker than under the neutral response.
        let width = 64, height = 64
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.15, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let red = ctx.makeImage()!

        func meanLuma(_ image: CGImage) -> Double {
            let bytes = drawToBytes(image)
            var total = 0.0
            for i in stride(from: 0, to: bytes.count, by: 4) { total += Double(bytes[i]) }
            return total / Double(bytes.count / 4)
        }

        let neutral = try BWFilmRenderer.render(to: red, params: bwParams(BWFilmShaderParams()))
        let ortho = try BWFilmRenderer.render(
            to: red, params: bwParams(BWFilmShaderParams().applyingResponse(.rolleiOrtho25)))
        XCTAssertLessThan(meanLuma(ortho), meanLuma(neutral) - 25,
                          "ortho film must render red much darker than neutral")
    }

    func testBWFilmToningTintsHighlightsAndShadowsSeparately() throws {
        try requireMetal()
        let img = makeTestImage()
        // Sepia silver (warm, hue 38) + blue paper (hue 220): highlights
        // must lean warm (R > B), shadows must lean cool (B > R).
        let p = BWFilmShaderParams(
            toningStrength: 80, toneHueHigh: 38, toneStrengthHigh: 60,
            toneHueLow: 220, toneStrengthLow: 60)
        let out = try BWFilmRenderer.render(to: img, params: bwParams(p))
        let bytes = drawToBytes(out)
        var warmHi = 0.0, coolSh = 0.0, nHi = 0.0, nSh = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
            let luma = (r + g + b) / 3
            if luma > 170 { warmHi += r - b; nHi += 1 }
            if luma < 85 { coolSh += b - r; nSh += 1 }
        }
        XCTAssertGreaterThan(nHi, 100, "test image should have highlights")
        XCTAssertGreaterThan(nSh, 100, "test image should have shadows")
        XCTAssertGreaterThan(warmHi / nHi, 2, "highlights should tint warm (silver hue)")
        XCTAssertGreaterThan(coolSh / nSh, 2, "shadows should tint cool (paper hue)")
    }

    func testBWFilmToningPresetTableIsDistinctAndApplies() {
        // Non-neutral presets must be pairwise distinct; applying one sets
        // the dials without touching conversion settings.
        let all = BWToningPreset.allCases.filter { $0 != .neutral }
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                XCTAssertFalse(all[i].toning == all[j].toning,
                               "\(all[i]) and \(all[j]) share identical toning values")
            }
        }
        let start = BWFilmShaderParams(sensRed: 33, contrast: 21)
        let sepia = start.applyingToningPreset(.sepia2)
        XCTAssertEqual(sepia.toningPreset, .sepia2)
        XCTAssertEqual(sepia.toningStrength, BWToningPreset.sepia2.toning.strength)
        XCTAssertEqual(sepia.sensRed, 33, "conversion must survive a toning change")
    }

    func testBWFilmVignetteDarkensCornersOnly() throws {
        try requireMetal()
        let img = makeTestImage()
        let plain = try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams()))
        let vig = try BWFilmRenderer.render(
            to: img, params: bwParams(BWFilmShaderParams(vigStrength: -80, vigSize: 40)))
        let pb = drawToBytes(plain), vb = drawToBytes(vig)
        let w = img.width
        func luma(_ b: [UInt8], _ x: Int, _ y: Int) -> Double { Double(b[(y * w + x) * 4]) }
        // The vignette is multiplicative, so assert a RELATIVE darkening —
        // the test image's corners are already dim, making absolute deltas
        // small.
        let cornerPlain = luma(pb, 2, 2)
        let cornerVig = luma(vb, 2, 2)
        let centerDelta = abs(luma(pb, w / 2, img.height / 2) - luma(vb, w / 2, img.height / 2))
        XCTAssertLessThan(cornerVig, cornerPlain * 0.55 + 2,
                          "corner should darken to <~half under -80 vignette (\(cornerPlain) → \(cornerVig))")
        XCTAssertLessThanOrEqual(centerDelta, 3, "center should be untouched")
    }

    func testBWFilmBurnEdgesAreIndependent() throws {
        try requireMetal()
        let img = makeTestImage()
        let topOnly = try BWFilmRenderer.render(
            to: img, params: bwParams(BWFilmShaderParams(beStrengthTop: 90, beSizeTop: 40)))
        let plain = try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams()))
        let tb = drawToBytes(topOnly), pb = drawToBytes(plain)
        let w = img.width, h = img.height
        func rowMean(_ b: [UInt8], _ y: Int) -> Double {
            var t = 0.0
            for x in 0..<w { t += Double(b[(y * w + x) * 4]) }
            return t / Double(w)
        }
        XCTAssertLessThan(rowMean(tb, 2), rowMean(pb, 2) - 15, "top rows should burn darker")
        XCTAssertEqual(rowMean(tb, h - 3), rowMean(pb, h - 3), accuracy: 3,
                       "bottom rows should be untouched by a top-only burn")
    }

    func testBWFilmUnknownResponseDecodesToCustomInsteadOfThrowing() throws {
        // Forward-compat guard: a preset written by a FUTURE version with a
        // new film name must not make this version's decode throw —
        // PresetStore deletes files that fail to decode (house rule 4).
        let layer = ShaderLayerParams(style: .bwFilm, params: .bwFilm(BWFilmShaderParams()))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(layer)) as! [String: Any]
        var paramsObj = json["params"] as! [String: Any]
        var inner = paramsObj["params"] as! [String: Any]
        inner["response"] = "futureFilm2030"
        paramsObj["params"] = inner
        json["params"] = paramsObj
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .bwFilm(let p) = decoded.params else { return XCTFail("style lost") }
        XCTAssertEqual(p.response, .custom, "unknown film must fall back, not throw")
    }

    func testBWFilmStructureAmplifiesLocalContrast() throws {
        try requireMetal()
        let img = makeTestImage()
        func highFreqEnergy(_ image: CGImage) -> Double {
            // Mean |horizontal neighbor delta| of the red channel — a cheap
            // local-contrast metric.
            let bytes = drawToBytes(image)
            let w = image.width
            var total = 0.0, n = 0.0
            for y in 0..<image.height {
                for x in 1..<w {
                    total += abs(Double(bytes[(y * w + x) * 4]) - Double(bytes[(y * w + x - 1) * 4]))
                    n += 1
                }
            }
            return total / n
        }
        let neutral = highFreqEnergy(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams())))
        let boosted = highFreqEnergy(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams(structure: 80))))
        let softened = highFreqEnergy(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams(structure: -80))))
        let fine = highFreqEnergy(try BWFilmRenderer.render(to: img, params: bwParams(BWFilmShaderParams(fineStructure: 90))))
        XCTAssertGreaterThan(boosted, neutral * 1.1,
                             "positive structure should amplify local contrast (\(neutral) → \(boosted))")
        XCTAssertLessThan(softened, neutral * 0.97,
                          "negative structure should soften (\(neutral) → \(softened))")
        XCTAssertGreaterThan(fine, neutral * 1.1,
                             "fine structure should amplify detail (\(neutral) → \(fine))")
    }

    func testBWFilmStructureLeavesFlatFieldsUntouched() throws {
        try requireMetal()
        // Unsharp masking has nothing to amplify on a constant field.
        let width = 96, height = 96
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let flat = ctx.makeImage()!
        let plain = try BWFilmRenderer.render(to: flat, params: bwParams(BWFilmShaderParams()))
        let structured = try BWFilmRenderer.render(
            to: flat, params: bwParams(BWFilmShaderParams(structure: 100, fineStructure: 100)))
        let (mean, _) = compare(plain, structured)
        XCTAssertLessThan(mean, 0.5, "flat field should be unaffected by structure (mean \(mean))")
    }

    func testBWFilmDeterministicAndRoundTrips() throws {
        try requireMetal()
        let img = makeTestImage()
        let p = BWFilmShaderParams(sensRed: 40, sensBlue: -60, contrast: 30, curveGamma: 0.2)
        let a = try BWFilmRenderer.render(to: img, params: bwParams(p))
        let b = try BWFilmRenderer.render(to: img, params: bwParams(p))
        let (_, maxDelta) = compare(a, b)
        XCTAssertEqual(maxDelta, 0, "render must be deterministic")

        // All-non-default JSON round-trip (house discipline).
        let original = BWFilmShaderParams(
            response: .kodakTriX400,
            sensRed: 10, sensYellow: -20, sensGreen: 30, sensCyan: -40,
            sensBlue: 50, sensMagenta: -60,
            brightness: 5, brightnessHighlights: -10, brightnessMidtones: 15,
            brightnessShadows: -20, contrast: 25, protectHighlights: 30,
            protectShadows: 35,
            structure: 22, structureHighlights: -11, structureMidtones: 12,
            structureShadows: 13, fineStructure: 27,
            toningPreset: .selenium2, toningStrength: 44, toneHueHigh: 100,
            toneStrengthHigh: 22, toneHueLow: 200, toneStrengthLow: 33,
            toneBalance: -12, vigStrength: -40, vigSize: 60, vigShape: 4.2,
            beStrengthTop: 11, beStrengthBottom: 12, beStrengthLeft: 13,
            beStrengthRight: 14, beSizeTop: 21, beSizeBottom: 22,
            beSizeLeft: 23, beSizeRight: 24, beTransitionTop: 31,
            beTransitionBottom: 32, beTransitionLeft: 33, beTransitionRight: 34,
            curveGamma: -0.4, curveLowX: 0.05,
            curveLowY: 0.1, curveHighX: 0.9, curveHighY: 0.95,
            curvePoints: [BWCurvePoint(x: 0.3, y: 0.25)])
        let layer = ShaderLayerParams(style: .bwFilm, params: .bwFilm(original))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .bwFilm(let roundTripped) = decoded.params else {
            return XCTFail("style did not round-trip")
        }
        XCTAssertEqual(roundTripped, original)
    }
}
