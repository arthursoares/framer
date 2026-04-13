// EffectGPUParityTests.swift
// Per-effect CPU vs GPU parity check. For each shader effect, render the same
// synthetic image through the legacy CPU path and the new Metal renderer, then
// assert mean / max per-channel deltas stay under per-effect tolerances.
//
// All tests skip themselves when Metal is unavailable
// (`MetalEffectLibrary.shared` is nil — Linux CI, sandboxed environments
// without GPU). They also skip the ASCII case if the LUT atlas PNGs aren't
// reachable via `TextureFrameProvider.searchPaths`.
//
// Tolerances are deliberately generous because there are several legitimate
// sources of per-pixel divergence:
//   - Floating-point precision (CPU uses Double, GPU uses Float / half).
//   - Sub-cell sampling differences (ASCII GPU samples 4×4 stratified vs.
//     CPU exhaustive cell average).
//   - sRGB roundtrip through CIContext on readback.
//   - CGContext interpolation when the GPU output is upscaled back to the
//     original dimensions (currently only happens for ASCII at preview sizes).
//
// Run on Mac via:
//   swift test --filter EffectGPUParityTests
//
// Authored on Linux Cloud — has not yet been compiled / executed. Treat the
// tolerance numbers as starting points; tighten or loosen on first run.

import XCTest
import CoreGraphics
@testable import FramerCore

final class EffectGPUParityTests: XCTestCase {

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

    // MARK: - ASCII

    func testASCIIParity() throws {
        try requireMetal()
        // Skip if the LUT atlases aren't reachable — the GPU path will throw
        // textureLoadFailed and fall back to CPU, which would make the test
        // tautological.
        guard let _ = try MetalTextureSupport.loadLUTTexture(
            named: "edgesASCII.png",
            device: MetalEffectLibrary.shared!.device
        ) else {
            throw XCTSkip("ASCII LUT atlases not present in TextureFrameProvider.searchPaths.")
        }

        let img = makeTestImage()
        let params = ShaderLayerParams(style: .ascii, intensity: 1.0,
                                       params: .ascii(ASCIIShaderParams(cellSize: 8)))

        let cpu = try ShaderASCIIRenderer.apply(to: img, params: params)
        let gpu = try TextCellRenderer.renderASCII(to: img, params: params)

        let (mean, max) = compare(cpu, gpu)
        // ASCII has the loosest tolerance: the GPU samples 4×4 stratified per
        // cell vs. CPU's exhaustive cell average, and Sobel uses cell-spaced
        // neighbour averages instead of summed per-pixel gradients.
        XCTAssertLessThan(mean, 25.0,  "ASCII mean delta too high (\(mean))")
        XCTAssertLessThan(max,  255,   "ASCII max delta saturated (\(max))")
    }

    // MARK: - Color grade trio

    func testCrimewaveParity() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .crimewave, intensity: 1.0,
                                       params: .crimewave(CrimewaveShaderParams(softness: 0)))
        let cpu = try ShaderRenderer.applyCrimewave(to: img,
                                                    params: CrimewaveShaderParams(softness: 0),
                                                    intensity: 1.0)
        let gpu = try ColorGradeRenderer.renderCrimewave(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        XCTAssertLessThan(mean, 6.0, "Crimewave mean delta too high (\(mean))")
        XCTAssertLessThan(max,  40,  "Crimewave max delta too high (\(max))")
    }

    func testNarcParity() throws {
        try requireMetal()
        let img = makeTestImage()
        let np = NarcShaderParams()
        let params = ShaderLayerParams(style: .narc, intensity: 1.0, params: .narc(np))
        let cpu = try ShaderRenderer.applyNarc(to: img, params: np, intensity: 1.0)
        let gpu = try ColorGradeRenderer.renderNarc(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        XCTAssertLessThan(mean, 6.0, "Narc mean delta too high (\(mean))")
        XCTAssertLessThan(max,  40,  "Narc max delta too high (\(max))")
    }

    func testShibaParity() throws {
        try requireMetal()
        let img = makeTestImage()
        let sp = ShibaShaderParams(softness: 0)
        let params = ShaderLayerParams(style: .shiba, intensity: 1.0, params: .shiba(sp))
        let cpu = try ShaderRenderer.applyShiba(to: img, params: sp, intensity: 1.0)
        let gpu = try ColorGradeRenderer.renderShiba(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        XCTAssertLessThan(mean, 6.0, "Shiba mean delta too high (\(mean))")
        XCTAssertLessThan(max,  40,  "Shiba max delta too high (\(max))")
    }

    // MARK: - DistantPast

    func testDistantPastParity() throws {
        try requireMetal()
        let img = makeTestImage()
        // Use softness 0 to remove the blur stage from comparison — blur
        // implementations differ subtly in border handling and would inflate
        // delta without buying signal.
        let dp = DistantPastShaderParams(softness: 0)
        let params = ShaderLayerParams(style: .distantPast, intensity: 1.0,
                                       params: .distantPast(dp))
        let cpu = try ShaderRenderer.applyDistantPast(to: img, params: dp, intensity: 1.0)
        let gpu = try DistantPastRenderer.render(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        // Palette snap is brittle near boundaries — pixels close to the
        // midpoint between two palette colours can flip on tiny noise / fp
        // rounding. Looser tolerance accordingly.
        XCTAssertLessThan(mean, 12.0, "DistantPast mean delta too high (\(mean))")
    }

    // MARK: - CRT

    func testCRTParity() throws {
        try requireMetal()
        let img = makeTestImage()
        let crt = CRTShaderParams()
        let params = ShaderLayerParams(style: .crt, intensity: 1.0, params: .crt(crt))
        let cpu = try ShaderRenderer.applyCRT(to: img, params: crt, intensity: 1.0)
        let gpu = try CRTRenderer.render(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        // CRT samples the source at distorted UVs — CPU uses nearest pixel
        // (`Int.rounded(.down)`), GPU uses linear sampling, so even a uniform
        // source produces a few-byte delta along the barrel curve.
        XCTAssertLessThan(mean, 8.0, "CRT mean delta too high (\(mean))")
    }

    // MARK: - Halftone

    func testHalftoneMonoParity() throws {
        try requireMetal()
        let img = makeTestImage()
        let h = HalftoneShaderParams(monochrome: true)
        let params = ShaderLayerParams(style: .halftone, intensity: 1.0, params: .halftone(h))
        let cpu = try ShaderRenderer.applyHalftone(to: img, params: h, intensity: 1.0)
        let gpu = try HalftoneRenderer.render(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        // Halftone output is binary per channel — single-pixel noise at the
        // dot threshold can cascade. Tolerance is for the threshold-edge
        // pixels; bulk should match.
        XCTAssertLessThan(mean, 15.0, "Halftone mono mean delta too high (\(mean))")
    }

    // MARK: - Kuwahara

    func testKuwaharaParity() throws {
        try requireMetal()
        let img = makeTestImage(width: 128, height: 128)  // smaller — Kuwahara is slow
        let k = KuwaharaShaderParams(kernelSize: 3, sharpness: 0)
        let params = ShaderLayerParams(style: .kuwahara, intensity: 1.0, params: .kuwahara(k))
        let cpu = try ShaderRenderer.applyKuwahara(to: img, params: k, intensity: 1.0)
        let gpu = try KuwaharaRenderer.render(to: img, params: params)
        let (mean, max) = compare(cpu, gpu)
        // Kuwahara picks the lowest-variance quadrant, so near-tied quadrants
        // can flip on tiny fp differences and produce visually equivalent but
        // pixel-different output. Wider tolerance.
        XCTAssertLessThan(mean, 12.0, "Kuwahara mean delta too high (\(mean))")
    }

    // MARK: - PixelSort

    func testPixelSortParityDefaultSpan() throws {
        try requireMetal()
        let img = makeTestImage()
        // Default span = 24 — matches the GPU shader's SAMPLE_COUNT cap, so
        // every pixel in every span is read by both paths and the rank lookup
        // is exact. Output should match closely modulo Float vs Double
        // rounding.
        let ps = PixelSortShaderParams()
        let params = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                       params: .pixelSort(ps))
        let cpu = try ShaderPixelSortRenderer.apply(to: img, params: params)
        let gpu = try PixelSortRenderer.render(to: img, params: params)
        let (mean, _) = compare(cpu, gpu)
        // PixelSort flips many bytes when the sort order changes by even one
        // sample — relax tolerance vs colour-grade tests but keep it tight
        // enough to catch broken rank logic.
        XCTAssertLessThan(mean, 12.0, "PixelSort mean delta too high (\(mean))")
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
    // Dither parity is structurally loose: GPU uses blue-noise threshold
    // approximation while CPU uses real error diffusion (Floyd-Steinberg etc).
    // The two are *visually* similar on natural images but per-pixel deltas
    // are large. These tests assert structure: output dimensions, output range
    // (binary for bw mode), Riemersma forced-fallback path, etc.

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
        // Riemersma has no GPU implementation; the public `apply` should silently
        // fall back to CPU. This test runs even without Metal because the GPU
        // call would throw and the fallback would handle it.
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
                             "Riemersma fallback didn't actually dither (got \(binary) binary pixels)")
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
}
