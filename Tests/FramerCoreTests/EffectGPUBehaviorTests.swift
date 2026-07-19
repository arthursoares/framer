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
        XCTAssertEqual(identity[0], 0, accuracy: 0.005)
        XCTAssertEqual(identity[255], 1, accuracy: 0.005)
        XCTAssertEqual(identity[128], 128.0 / 255.0, accuracy: 0.01)
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
        XCTAssertEqual(ortho.curveGamma, 0.3, "curve must survive a response change")
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

<<<<<<< HEAD
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
=======
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
>>>>>>> feat/bw-film-effect
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
