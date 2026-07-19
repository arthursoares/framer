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

    func testRoughBorderRoundTripsThroughJSON() throws {
        // Codable round-trip (preset safety, house rule 4). No Metal needed.
        let original = RoughBorderShaderParams(
            size: 0.12, spread: 0.79, roughness: 0.67, seed: 2201,
            borderColor: .black)
        let layer = ShaderLayerParams(style: .roughBorder, params: .roughBorder(original))
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(ShaderLayerParams.self, from: data)
        guard case .roughBorder(let roundTripped) = decoded.params else {
            return XCTFail("style did not round-trip")
        }
        XCTAssertEqual(roundTripped, original)
    }
}
