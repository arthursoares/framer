// EffectGPUGoldenTests.swift
// Golden-reference regression checks for the GPU effect renderers.
//
// These tests replace the CPU-vs-GPU comparisons from EffectGPUParityTests
// after the CPU effect path was retired (see
// docs/adr/2026-07-09-retire-cpu-effect-path.md). Each GPU render is compared
// against a frozen PNG in Tests/FramerCoreTests/Resources/GoldenReferences/
// using the same per-effect mean/max byte-delta tolerances the parity tests
// used. On the machine that generated the goldens the expected delta is
// exactly 0; the inherited tolerances are headroom for cross-machine GPU
// float/rounding drift.
//
// Regenerate the goldens (ONLY together with a deliberate, explained look
// change — same discipline as snapshot hashes, never blind-refresh):
//
//   FRAMER_REGENERATE_GOLDENS=1 swift test --filter EffectGPUGoldenTests
//
// The regenerated PNGs land in the source tree (located via #filePath) and
// must be committed in the same commit as the shader change that caused the
// shift, with an explanation of WHY the pixels moved.
//
// All tests skip when Metal is unavailable — without the GPU path there is
// nothing to check.

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FramerCore

final class EffectGPUGoldenTests: XCTestCase {

    // MARK: - Shared test image (identical fixture to EffectGPUParityTests)

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

    private enum ASCIIStripeDirection: String {
        case vertical, horizontal, diagonalRightDown, diagonalLeftDown
    }

    private func makeStripeImage(width: Int = 64, height: Int = 64, direction: ASCIIStripeDirection) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let halfThickness = 1
        for y in 0..<height {
            for x in 0..<width {
                let onStripe: Bool
                switch direction {
                case .vertical:          onStripe = abs(x - width / 2) <= halfThickness
                case .horizontal:        onStripe = abs(y - height / 2) <= halfThickness
                case .diagonalRightDown: onStripe = abs(x - y) <= halfThickness
                case .diagonalLeftDown:  onStripe = abs((width - 1 - x) - y) <= halfThickness
                }
                let value: UInt8 = onStripe ? 255 : 0
                let idx = (y * width + x) * 4
                pixels[idx] = value
                pixels[idx + 1] = value
                pixels[idx + 2] = value
                pixels[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    // MARK: - Pixel comparison (same semantics as EffectGPUParityTests)

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

    // MARK: - Golden storage

    private static let regenerate =
        ProcessInfo.processInfo.environment["FRAMER_REGENERATE_GOLDENS"] == "1"

    /// Source-tree location of the goldens, so regeneration writes where git
    /// can see it. Reads also go through this path (the bundle copy is the
    /// same file; #filePath keeps read/write symmetric).
    private func goldenDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()                     // Tests/FramerCoreTests/
            .appendingPathComponent("Resources/GoldenReferences", isDirectory: true)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw XCTSkip("Could not create PNG destination at \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw XCTSkip("Could not finalize PNG at \(url.path)")
        }
    }

    private func loadPNG(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Compare a GPU render against its committed golden (or regenerate it
    /// when FRAMER_REGENERATE_GOLDENS=1).
    private func assertMatchesGolden(
        _ output: CGImage,
        golden name: String,
        meanTolerance: Double,
        maxTolerance: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = goldenDirectory().appendingPathComponent("\(name).png")

        if Self.regenerate {
            try writePNG(output, to: url)
            print("[EffectGPUGoldenTests] regenerated golden: \(url.path)")
            return
        }

        guard let golden = loadPNG(at: url) else {
            XCTFail(
                """
                Missing golden reference '\(name).png'. Generate it with:
                  FRAMER_REGENERATE_GOLDENS=1 swift test --filter EffectGPUGoldenTests
                and commit the PNG together with the change that introduced it.
                """,
                file: file, line: line
            )
            return
        }

        let (mean, max) = compare(golden, output)
        XCTAssertLessThan(
            mean, meanTolerance,
            "\(name): mean delta vs golden too high (\(mean)). If this is a " +
            "deliberate look change, regenerate the golden in the same commit " +
            "and explain the pixel shift.",
            file: file, line: line
        )
        if let maxTolerance {
            XCTAssertLessThan(
                max, maxTolerance,
                "\(name): max delta vs golden too high (\(max)).",
                file: file, line: line
            )
        }
    }

    // MARK: - Skip helpers

    private func requireMetal() throws {
        guard MetalEffectLibrary.shared != nil else {
            throw XCTSkip("Metal device unavailable on this host (likely CI sandbox).")
        }
    }

    private func requireASCIIAtlas() throws {
        guard let _ = try MetalTextureSupport.loadLUTTexture(
            named: "edgesASCII.png",
            device: MetalEffectLibrary.shared!.device
        ) else {
            throw XCTSkip("ASCII LUT atlases not present in TextureFrameProvider.searchPaths.")
        }
    }

    // MARK: - ASCII

    func testASCIIMatchesGolden() throws {
        try requireMetal()
        try requireASCIIAtlas()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .ascii, intensity: 1.0,
                                       params: .ascii(ASCIIShaderParams(cellSize: 8)))
        let gpu = try TextCellRenderer.renderASCII(to: img, params: params)
        // Tolerance inherited from the ASCII parity test (loosest in the
        // suite: stratified sub-cell sampling makes threshold pixels tippy).
        try assertMatchesGolden(gpu, golden: "ascii-main", meanTolerance: 25.0, maxTolerance: 255)
    }

    func testASCIIEdgeDirectionStripesMatchGoldens() throws {
        try requireMetal()
        try requireASCIIAtlas()
        let params = ShaderLayerParams(style: .ascii, intensity: 1.0,
                                       params: .ascii(ASCIIShaderParams(cellSize: 8)))
        for direction in [
            ASCIIStripeDirection.vertical,
            .horizontal,
            .diagonalRightDown,
            .diagonalLeftDown
        ] {
            let img = makeStripeImage(direction: direction)
            let gpu = try TextCellRenderer.renderASCII(to: img, params: params)
            // A bucket-direction swap flips whole 8-pixel-wide glyph rows and
            // pushes the mean far above tolerance; single threshold-tipped
            // pixels only move it by ~4/255, so mean (not max) is the guard —
            // same reasoning as the original per-direction parity test.
            try assertMatchesGolden(
                gpu,
                golden: "ascii-stripe-\(direction.rawValue)",
                meanTolerance: 30.0
            )
        }
    }

    // MARK: - Color grade trio

    func testCrimewaveMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .crimewave, intensity: 1.0,
                                       params: .crimewave(CrimewaveShaderParams(softness: 0)))
        let gpu = try ColorGradeRenderer.renderCrimewave(to: img, params: params)
        try assertMatchesGolden(gpu, golden: "crimewave", meanTolerance: 6.0, maxTolerance: 40)
    }

    func testCrimewaveSoftnessMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .crimewave, intensity: 1.0,
                                       params: .crimewave(CrimewaveShaderParams(softness: 0.6)))
        let gpu = try ColorGradeRenderer.renderCrimewave(to: img, params: params)
        // Covers the softness/blur-ordering path (blur AFTER grading) that a
        // softness=0 golden cannot see.
        try assertMatchesGolden(gpu, golden: "crimewave-softness", meanTolerance: 6.0, maxTolerance: 40)
    }

    func testNarcMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .narc, intensity: 1.0,
                                       params: .narc(NarcShaderParams()))
        let gpu = try ColorGradeRenderer.renderNarc(to: img, params: params)
        try assertMatchesGolden(gpu, golden: "narc", meanTolerance: 6.0, maxTolerance: 40)
    }

    func testShibaMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .shiba, intensity: 1.0,
                                       params: .shiba(ShibaShaderParams(softness: 0)))
        let gpu = try ColorGradeRenderer.renderShiba(to: img, params: params)
        try assertMatchesGolden(gpu, golden: "shiba", meanTolerance: 6.0, maxTolerance: 40)
    }

    func testShibaSoftnessMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .shiba, intensity: 1.0,
                                       params: .shiba(ShibaShaderParams(softness: 0.6)))
        let gpu = try ColorGradeRenderer.renderShiba(to: img, params: params)
        try assertMatchesGolden(gpu, golden: "shiba-softness", meanTolerance: 6.0, maxTolerance: 40)
    }

    // MARK: - DistantPast

    func testDistantPastMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .distantPast, intensity: 1.0,
                                       params: .distantPast(DistantPastShaderParams(softness: 0)))
        let gpu = try DistantPastRenderer.render(to: img, params: params)
        // Palette snap is brittle near boundaries — looser mean, no max
        // assert (single snapped pixels saturate max legitimately).
        try assertMatchesGolden(gpu, golden: "distantpast", meanTolerance: 12.0)
    }

    func testDistantPastSoftnessMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .distantPast, intensity: 1.0,
                                       params: .distantPast(DistantPastShaderParams(softness: 0.6)))
        let gpu = try DistantPastRenderer.render(to: img, params: params)
        // Guards the blur-the-processed-intermediate ordering (not the raw
        // source) that the softness=0 golden cannot see.
        try assertMatchesGolden(gpu, golden: "distantpast-softness", meanTolerance: 12.0)
    }

    // MARK: - CRT

    func testCRTMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .crt, intensity: 1.0,
                                       params: .crt(CRTShaderParams()))
        let gpu = try CRTRenderer.render(to: img, params: params)
        try assertMatchesGolden(gpu, golden: "crt", meanTolerance: 8.0)
    }

    // MARK: - Halftone

    func testHalftoneMonoMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .halftone, intensity: 1.0,
                                       params: .halftone(HalftoneShaderParams(monochrome: true)))
        let gpu = try HalftoneRenderer.render(to: img, params: params)
        // Binary-per-channel output — threshold-edge pixels can cascade.
        try assertMatchesGolden(gpu, golden: "halftone-mono", meanTolerance: 15.0)
    }

    // MARK: - Kuwahara

    func testKuwaharaMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage(width: 128, height: 128)  // smaller — Kuwahara is slow
        let params = ShaderLayerParams(style: .kuwahara, intensity: 1.0,
                                       params: .kuwahara(KuwaharaShaderParams(kernelSize: 3, softness: 1.0)))
        let gpu = try KuwaharaRenderer.render(to: img, params: params)
        // Near-tied quadrant variances can flip on fp drift — wider tolerance.
        try assertMatchesGolden(gpu, golden: "kuwahara", meanTolerance: 12.0)
    }

    // MARK: - PixelSort

    func testPixelSortDefaultSpanMatchesGolden() throws {
        try requireMetal()
        let img = makeTestImage()
        let params = ShaderLayerParams(style: .pixelSort, intensity: 1.0,
                                       params: .pixelSort(PixelSortShaderParams()))
        let gpu = try PixelSortRenderer.render(to: img, params: params)
        // A one-sample rank change flips many bytes — same tolerance the
        // parity test used to catch broken rank logic without noise failures.
        try assertMatchesGolden(gpu, golden: "pixelsort-default", meanTolerance: 12.0)
    }
}
