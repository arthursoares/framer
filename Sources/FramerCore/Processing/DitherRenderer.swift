// Sources/FramerCore/Processing/DitherRenderer.swift
import Foundation
import CoreGraphics
import Accelerate

// MARK: - DitherRenderer

/// Applies dithering effects to images using various algorithms and color modes.
///
/// Supports nine dithering algorithms (Bayer, Floyd-Steinberg, Atkinson, Blue Noise,
/// Artistic Drip, Halftone, Stucki, White Noise, Riemersma) with three color modes
/// (black & white, two-tone, and quantized color).
///
/// All error diffusion algorithms use serpentine (boustrophedon) scanning to reduce
/// directional banding artifacts.
///
/// All luminance calculations use sRGB↔linear gamma conversion per IEC 61966-2-1.
public enum DitherRenderer {

    // MARK: - Pre-computed Lookup Tables

    /// sRGB byte (0-255) → linear light (0-1). Eliminates pow() per pixel.
    private static let sRGBToLinearLUT: [Double] = (0...255).map { i in
        let c = Double(i) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear light (0-65535 quantized) → sRGB byte (0-255). Eliminates pow() per pixel.
    private static let linearToSRGBLUT: [UInt8] = (0...65535).map { i in
        let c = Double(i) / 65535.0
        let srgb = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        return UInt8(max(0, min(255, round(srgb * 255.0))))
    }

    /// BT.709 luminance from sRGB byte values, using LUT.
    @inline(__always)
    private static func luminanceLUT(r: UInt8, g: UInt8, b: UInt8) -> Double {
        0.2126 * sRGBToLinearLUT[Int(r)] + 0.7152 * sRGBToLinearLUT[Int(g)] + 0.0722 * sRGBToLinearLUT[Int(b)]
    }

    /// Convert linear (0-1) to sRGB byte using LUT.
    @inline(__always)
    private static func linearToSRGBByte(_ v: Double) -> UInt8 {
        let clamped = max(0.0, min(1.0, v))
        return linearToSRGBLUT[Int(clamped * 65535.0)]
    }

    // MARK: - Cached Matrices (computed once)

    /// Cached Bayer matrices for levels 1-4. Flattened to 1D for cache-friendly access.
    private static let cachedBayerMatrices: [(data: [Double], size: Int)] = (1...4).map { level in
        let matrix = generateBayerMatrix(level: level)
        let size = matrix.count
        // Flatten 2D → 1D
        var flat = [Double](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                flat[y * size + x] = matrix[y][x]
            }
        }
        return (flat, size)
    }

    /// Cached 6×6 halftone matrix, flattened.
    private static let cachedHalftoneFlat: [Double] = {
        let raw: [[Double]] = [
            [34, 29, 17, 21, 30, 35],
            [28, 14,  9, 16, 20, 31],
            [13,  8,  4,  5, 15, 19],
            [12,  3,  0,  1, 10, 18],
            [27,  7,  2,  6, 11, 24],
            [33, 26, 22, 23, 25, 32]
        ]
        var flat = [Double](repeating: 0, count: 36)
        for y in 0..<6 {
            for x in 0..<6 {
                flat[y * 6 + x] = (raw[y][x] + 0.5) / 36.0
            }
        }
        return flat
    }()

    /// Cached 64×64 blue noise texture.
    private static let cachedBlueNoise: [Double] = {
        let size = 64
        let count = size * size
        var texture = [Double](repeating: 0, count: count)
        let g = 1.32471795724474602596
        let a1 = 1.0 / g
        let a2 = 1.0 / (g * g)
        for i in 0..<count {
            let x = (0.5 + a1 * Double(i + 1)).truncatingRemainder(dividingBy: 1.0)
            let y = (0.5 + a2 * Double(i + 1)).truncatingRemainder(dividingBy: 1.0)
            let px = Int(x * Double(size)) % size
            let py = Int(y * Double(size)) % size
            texture[py * size + px] = Double(i) / Double(count)
        }
        return texture
    }()

    /// Pre-computed Riemersma decay weights.
    private static let riemersmaHistorySize = 16
    private static let riemersmaWeights: (weights: [Double], totalWeight: Double) = {
        var w = [Double](repeating: 0, count: 16)
        var total = 0.0
        for i in 0..<16 {
            w[i] = exp(-Double(i) * 0.3)
            total += w[i]
        }
        return (w, total)
    }()

    /// Cache for Hilbert curve paths, keyed by (width, height).
    private static var hilbertCache = [UInt64: [UInt32]]()
    private static let hilbertCacheLock = NSLock()

    // MARK: - Public API

    /// Apply dithering to an image using the specified parameters.
    ///
    /// - Parameters:
    ///   - image: The input image to dither.
    ///   - params: Dithering parameters.
    ///   - previewBaseDimension: When set (export path), the max dimension that the preview
    ///     downscaled to. The effective pixel scale is adjusted so the dither cell count
    ///     matches what the preview produced, ensuring consistent visual output.
    /// Public entry point. Tries the GPU path first
    /// (`DitherGPURenderer.apply`); falls back to `applyCPU` on
    /// `MetalEffectError` (Metal unavailable, Riemersma which has no GPU
    /// implementation, or pipeline build failure).
    ///
    /// Same signature as the legacy CPU entry — callers (BorderRenderer,
    /// tests) need no changes.
    public static func apply(
        to image: CGImage,
        params: DitherLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        do {
            return try DitherGPURenderer.apply(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension,
                sourceImage: sourceImage
            )
        } catch is MetalEffectError {
            return try applyCPU(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension,
                sourceImage: sourceImage
            )
        }
    }

    /// CPU implementation. Reachable from tests and from the GPU fallback in
    /// `apply(...)`. The body is unchanged from the original CPU dither
    /// renderer; only the entry-point name changed.
    public static func applyCPU(to image: CGImage, params: DitherLayerParams, previewBaseDimension: Int? = nil, sourceImage: CGImage? = nil) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        try Task.checkCancellation()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // Pixel scale: downscale with bilinear interpolation before dithering.
        // When previewBaseDimension is provided, scale up the pixel scale so the
        // dither cell count matches what the preview produced at its resolution.
        let scale: Int
        if params.pixelScale > 1, let previewBase = previewBaseDimension {
            let currentMax = max(width, height)
            scale = max(1, min(32, Int(round(Double(currentMax) * Double(params.pixelScale) / Double(previewBase)))))
        } else {
            scale = max(1, min(8, params.pixelScale))
        }
        // Create working context — when scaling, draw directly into the work context
        // (avoids a second CGContext allocation and redundant blit)
        let workW: Int
        let workH: Int
        if scale > 1 {
            workW = max(1, width / scale)
            workH = max(1, height / scale)
        } else {
            workW = width
            workH = height
        }

        guard let ctx = CGContext(
            data: nil, width: workW, height: workH,
            bitsPerComponent: 8, bytesPerRow: workW * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        ctx.interpolationQuality = scale > 1 ? .high : .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: workW, height: workH))

        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: workW * workH * 4)

        // Pre-processing: sharpen and contrast
        if params.sharpen > 0 {
            applySharpen(pixels: pixels, width: workW, height: workH, amount: params.sharpen)
        }
        if params.contrast > 0 {
            applyContrast(pixels: pixels, count: workW * workH, amount: params.contrast)
        }
        try Task.checkCancellation()

        // Apply dithering algorithm
        let threshold = max(0.1, min(0.9, params.threshold))
        switch params.colorMode {
        case .bw, .twoTone, .dominantTwoTone:
            try applyMonochromeDither(
                pixels: pixels, width: workW, height: workH,
                algorithm: params.algorithm, bayerLevel: params.bayerLevel,
                threshold: threshold
            )
        case .color(let levels):
            try applyColorDither(
                pixels: pixels, width: workW, height: workH,
                algorithm: params.algorithm, bayerLevel: params.bayerLevel,
                levels: max(2, min(8, levels)), threshold: threshold
            )
        }
        try Task.checkCancellation()

        // Apply color mapping for two-tone modes
        switch params.colorMode {
        case .twoTone(let fg, let bg):
            applyTwoToneMapping(pixels: pixels, count: workW * workH, foreground: fg, background: bg)
        case .dominantTwoTone(let flipped, let satShift, let lightShift):
            let colorSource = sourceImage ?? image
            var (primary, secondary) = ColorExtractor.extractTwoDominantColors(from: colorSource)
            if satShift != 0 || lightShift != 0 {
                primary = Self.adjustColor(primary, saturationShift: satShift, lightnessShift: lightShift)
                secondary = Self.adjustColor(secondary, saturationShift: satShift, lightnessShift: lightShift)
            }
            let fg = flipped ? secondary : primary
            let bg = flipped ? primary : secondary
            applyTwoToneMapping(pixels: pixels, count: workW * workH, foreground: fg, background: bg)
        default:
            break
        }

        try Task.checkCancellation()

        guard let dithered = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Pixel scale: upscale with nearest-neighbor to original dimensions
        if scale > 1 {
            guard let outCtx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            outCtx.interpolationQuality = .none // nearest-neighbor
            outCtx.draw(dithered, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let result = outCtx.makeImage() else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            return result
        }

        return dithered
    }

    // MARK: - Pre-Processing

    /// Apply unsharp mask sharpening using Accelerate vImage for performance.
    /// Uses 3×3 box convolution (equivalent to radius-1 blur) then unsharp mask.
    private static func applySharpen(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        amount: Double
    ) {
        let bytesPerRow = width * 4
        var src = vImage_Buffer(data: pixels, height: vImagePixelCount(height),
                                width: vImagePixelCount(width), rowBytes: bytesPerRow)

        // Allocate destination buffer for the blurred version
        let blurData = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        defer { blurData.deallocate() }
        var dst = vImage_Buffer(data: blurData, height: vImagePixelCount(height),
                                width: vImagePixelCount(width), rowBytes: bytesPerRow)

        // 3×3 box blur via vImage (operates on all 4 channels at once)
        vImageBoxConvolve_ARGB8888(&src, &dst, nil, 0, 0, 3, 3, nil, vImage_Flags(kvImageEdgeExtend))

        // Unsharp mask: result = original + amount * (original - blurred)
        let amount2 = Float(amount * 2.0)
        let count = width * height * 4
        for i in stride(from: 0, to: count, by: 4) {
            for c in 0..<3 {
                let orig = Float(pixels[i + c])
                let blur = Float(blurData[i + c])
                let sharpened = orig + amount2 * (orig - blur)
                pixels[i + c] = UInt8(max(0, min(255, Int(sharpened + 0.5))))
            }
        }
    }

    /// Apply S-curve contrast enhancement using a pre-computed 256-entry LUT.
    private static func applyContrast(
        pixels: UnsafeMutablePointer<UInt8>,
        count: Int,
        amount: Double
    ) {
        // Build LUT for this contrast amount
        let strength = amount * 5.0
        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            let v = Double(i) / 255.0
            let centered = v - 0.5
            let curved = centered * (1.0 + strength * (1.0 - 4.0 * centered * centered))
            let result = max(0.0, min(1.0, curved + 0.5))
            lut[i] = UInt8(round(result * 255.0))
        }
        // Apply LUT
        let total = count * 4
        var idx = 0
        while idx < total {
            pixels[idx] = lut[Int(pixels[idx])]
            pixels[idx + 1] = lut[Int(pixels[idx + 1])]
            pixels[idx + 2] = lut[Int(pixels[idx + 2])]
            idx += 4
        }
    }

    // MARK: - Gamma Conversion (IEC 61966-2-1 sRGB)

    /// Convert sRGB component (0-1) to linear light.
    @inline(__always)
    static func sRGBToLinear(_ c: Double) -> Double {
        if c <= 0.04045 {
            return c / 12.92
        }
        return pow((c + 0.055) / 1.055, 2.4)
    }

    /// Convert linear light to sRGB component (0-1).
    @inline(__always)
    static func linearToSRGB(_ c: Double) -> Double {
        if c <= 0.0031308 {
            return c * 12.92
        }
        return 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    /// Compute perceptual luminance from sRGB pixel values (0-255).
    /// Uses BT.709 coefficients in linear space.
    @inline(__always)
    static func luminance(r: UInt8, g: UInt8, b: UInt8) -> Double {
        luminanceLUT(r: r, g: g, b: b)
    }

    // MARK: - Monochrome Dithering (B&W and Two-Tone)

    /// Apply monochrome dithering: each pixel becomes 0 or 255 based on luminance.
    private static func applyMonochromeDither(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        algorithm: DitherAlgorithm,
        bayerLevel: Int,
        threshold: Double
    ) throws {
        let offset = threshold - 0.5
        let count = width * height
        var lumBuf = [Double](repeating: 0, count: count)

        // Use LUT for gamma conversion — the hot path
        if abs(offset) < 0.001 {
            // No threshold offset: direct LUT lookup
            for i in 0..<count {
                if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
                let idx = i * 4
                lumBuf[i] = luminanceLUT(r: pixels[idx], g: pixels[idx + 1], b: pixels[idx + 2])
            }
        } else {
            // With threshold offset in sRGB space
            let offsetScaled = offset * 255.0
            for i in 0..<count {
                if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
                let idx = i * 4
                let rAdj = max(0, min(255, Int(Double(pixels[idx]) + offsetScaled)))
                let gAdj = max(0, min(255, Int(Double(pixels[idx + 1]) + offsetScaled)))
                let bAdj = max(0, min(255, Int(Double(pixels[idx + 2]) + offsetScaled)))
                lumBuf[i] = 0.2126 * sRGBToLinearLUT[rAdj] + 0.7152 * sRGBToLinearLUT[gAdj] + 0.0722 * sRGBToLinearLUT[bAdj]
            }
        }

        // Apply dithering algorithm to produce 0/1 decisions
        var output = [UInt8](repeating: 0, count: count)

        switch algorithm {
        case .bayer:
            let cached = cachedBayerMatrices[max(0, min(3, bayerLevel - 1))]
            let matData = cached.data
            let size = cached.size
            let mask = size - 1  // size is always power of 2
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let yOff = (y & mask) * size
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    output[i] = lumBuf[i] > matData[yOff + (x & mask)] ? 255 : 0
                }
            }

        case .floydSteinberg:
            output = try floydSteinbergDither(lumBuf: &lumBuf, width: width, height: height)

        case .atkinson:
            output = try atkinsonDither(lumBuf: &lumBuf, width: width, height: height)

        case .blueNoise:
            let noise = cachedBlueNoise
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let yOff = (y & 63) * 64  // 64 = blue noise size, & 63 = % 64
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    output[i] = lumBuf[i] > noise[yOff + (x & 63)] ? 255 : 0
                }
            }

        case .artisticDrip:
            output = try artisticDripDither(lumBuf: &lumBuf, width: width, height: height)

        case .halftone:
            let matData = cachedHalftoneFlat
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let yOff = (y % 6) * 6
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    output[i] = lumBuf[i] > matData[yOff + (x % 6)] ? 255 : 0
                }
            }

        case .stucki:
            output = try stuckiDither(lumBuf: &lumBuf, width: width, height: height)

        case .whiteNoise:
            output = try whiteNoiseDither(lumBuf: &lumBuf, width: width, height: height)

        case .riemersma:
            output = try riemersmaDither(lumBuf: &lumBuf, width: width, height: height)
        }

        // Write back to pixel buffer
        for i in 0..<count {
            if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
            let idx = i * 4
            let v = output[i]
            pixels[idx] = v
            pixels[idx + 1] = v
            pixels[idx + 2] = v
        }
    }

    // MARK: - Color Dithering

    /// Apply color dithering: each R/G/B channel is independently quantized to N levels.
    private static func applyColorDither(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        algorithm: DitherAlgorithm,
        bayerLevel: Int,
        levels: Int,
        threshold: Double
    ) throws {
        let count = width * height

        var rBuf = [Double](repeating: 0, count: count)
        var gBuf = [Double](repeating: 0, count: count)
        var bBuf = [Double](repeating: 0, count: count)

        let offset = threshold - 0.5
        if abs(offset) < 0.001 {
            // No offset: direct LUT
            for i in 0..<count {
                if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
                let idx = i * 4
                rBuf[i] = sRGBToLinearLUT[Int(pixels[idx])]
                gBuf[i] = sRGBToLinearLUT[Int(pixels[idx + 1])]
                bBuf[i] = sRGBToLinearLUT[Int(pixels[idx + 2])]
            }
        } else {
            for i in 0..<count {
                if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
                let idx = i * 4
                let rAdj = max(0, min(255, Int(Double(pixels[idx]) + offset * 255.0)))
                let gAdj = max(0, min(255, Int(Double(pixels[idx + 1]) + offset * 255.0)))
                let bAdj = max(0, min(255, Int(Double(pixels[idx + 2]) + offset * 255.0)))
                rBuf[i] = sRGBToLinearLUT[rAdj]
                gBuf[i] = sRGBToLinearLUT[gAdj]
                bBuf[i] = sRGBToLinearLUT[bAdj]
            }
        }

        // Fast path: for ordered algorithms, fuse all 3 channels in a single pass
        // (the threshold value is the same for R, G, B at each pixel)
        let isOrdered = algorithm == .bayer || algorithm == .blueNoise ||
                        algorithm == .halftone || algorithm == .whiteNoise
        if isOrdered {
            try applyOrderedColorDitherFused(
                pixels: pixels, rBuf: &rBuf, gBuf: &gBuf, bBuf: &bBuf,
                width: width, height: height, algorithm: algorithm,
                bayerLevel: bayerLevel, levels: levels
            )
        } else {
            // Error diffusion: must process each channel independently
            let rOut = try ditherChannel(&rBuf, width: width, height: height,
                                         algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)
            let gOut = try ditherChannel(&gBuf, width: width, height: height,
                                         algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)
            let bOut = try ditherChannel(&bBuf, width: width, height: height,
                                         algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)

            for i in 0..<count {
                if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
                let idx = i * 4
                pixels[idx] = rOut[i]
                pixels[idx + 1] = gOut[i]
                pixels[idx + 2] = bOut[i]
            }
        }
    }

    /// Fused ordered dither for all 3 color channels in a single pass.
    /// The threshold at (x,y) is identical for R/G/B, so we compute it once
    /// and apply to all three channels, cutting cache traversals by 3×.
    private static func applyOrderedColorDitherFused(
        pixels: UnsafeMutablePointer<UInt8>,
        rBuf: inout [Double], gBuf: inout [Double], bBuf: inout [Double],
        width: Int, height: Int,
        algorithm: DitherAlgorithm, bayerLevel: Int, levels: Int
    ) throws {
        let maxLevel = Double(levels - 1)

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let rowOff = y * width
            for x in 0..<width {
                let i = rowOff + x

                // Compute threshold once for this pixel
                let threshold: Double
                switch algorithm {
                case .bayer:
                    let cached = cachedBayerMatrices[max(0, min(3, bayerLevel - 1))]
                    let mask = cached.size - 1
                    threshold = cached.data[(y & mask) * cached.size + (x & mask)] - 0.5
                case .blueNoise:
                    threshold = cachedBlueNoise[(y & 63) * 64 + (x & 63)] - 0.5
                case .halftone:
                    threshold = cachedHalftoneFlat[(y % 6) * 6 + (x % 6)] - 0.5
                case .whiteNoise:
                    threshold = seededRandom(x: x, y: y) - 0.5
                default:
                    threshold = 0 // should not reach here
                }

                // Apply to all 3 channels
                let idx = i * 4
                let rQ = round((rBuf[i] + threshold / maxLevel) * maxLevel) / maxLevel
                let gQ = round((gBuf[i] + threshold / maxLevel) * maxLevel) / maxLevel
                let bQ = round((bBuf[i] + threshold / maxLevel) * maxLevel) / maxLevel
                pixels[idx] = linearToSRGBByte(rQ)
                pixels[idx + 1] = linearToSRGBByte(gQ)
                pixels[idx + 2] = linearToSRGBByte(bQ)
            }
        }
    }

    /// Dither a single channel to the specified number of levels.
    private static func ditherChannel(
        _ buf: inout [Double],
        width: Int, height: Int,
        algorithm: DitherAlgorithm,
        bayerLevel: Int,
        levels: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)
        let maxLevel = Double(levels - 1)

        switch algorithm {
        case .bayer:
            let cached = cachedBayerMatrices[max(0, min(3, bayerLevel - 1))]
            let matData = cached.data
            let size = cached.size
            let mask = size - 1
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let yOff = (y & mask) * size
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    let threshold = matData[yOff + (x & mask)] - 0.5
                    let adjusted = buf[i] + threshold / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    output[i] = linearToSRGBByte(quantized)
                }
            }

        case .floydSteinberg:
            try serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeFloydSteinberg
            )

        case .atkinson:
            try serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeAtkinson
            )

        case .blueNoise:
            let noise = cachedBlueNoise
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let yOff = (y & 63) * 64
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    let threshold = noise[yOff + (x & 63)] - 0.5
                    let adjusted = buf[i] + threshold / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    output[i] = linearToSRGBByte(quantized)
                }
            }

        case .artisticDrip:
            try serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeArtisticDrip
            )

        case .halftone:
            let matData = cachedHalftoneFlat
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let yOff = (y % 6) * 6
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    let threshold = matData[yOff + (x % 6)] - 0.5
                    let adjusted = buf[i] + threshold / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    output[i] = linearToSRGBByte(quantized)
                }
            }

        case .stucki:
            try serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeStucki
            )

        case .whiteNoise:
            for y in 0..<height {
                if (y & 31) == 0 { try Task.checkCancellation() }
                let rowOff = y * width
                for x in 0..<width {
                    let i = rowOff + x
                    let noise = seededRandom(x: x, y: y) - 0.5
                    let adjusted = buf[i] + noise / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    output[i] = linearToSRGBByte(quantized)
                }
            }

        case .riemersma:
            try riemersmaChannelDither(buf: &buf, output: &output, width: width, height: height, maxLevel: maxLevel)
        }

        return output
    }

    /// Generic serpentine error diffusion for color channel dithering.
    private static func serpentineErrorDiffusion(
        errors: inout [Double],
        output: inout [UInt8],
        width: Int, height: Int,
        maxLevel: Double,
        distribute: (inout [Double], Int, Int, Int, Int, Double, Bool) -> Void
    ) throws {
        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let leftToRight = (y % 2 == 0)
            let xRange = leftToRight ? stride(from: 0, to: width, by: 1) : stride(from: width - 1, to: -1, by: -1)
            for x in xRange {
                let i = y * width + x
                let oldVal = max(0, min(1, errors[i]))
                let quantized = round(oldVal * maxLevel) / maxLevel
                let err = oldVal - quantized
                output[i] = linearToSRGBByte(quantized)
                distribute(&errors, x, y, width, height, err, leftToRight)
            }
        }
    }

    /// Adjust a CodableColor's saturation and lightness via HSL round-trip.
    private static func adjustColor(_ color: CodableColor, saturationShift: Double, lightnessShift: Double) -> CodableColor {
        let r = color.red, g = color.green, b = color.blue
        let maxC = max(r, g, b), minC = min(r, g, b)
        var h = 0.0, s = 0.0, l = (maxC + minC) / 2
        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
            if maxC == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if maxC == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        s = max(0, min(1, s + saturationShift / 100))
        l = max(0, min(1, l + lightnessShift / 100))
        // HSL to RGB
        func hue2rgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let nr = s == 0 ? l : hue2rgb(p, q, h + 1/3)
        let ng = s == 0 ? l : hue2rgb(p, q, h)
        let nb = s == 0 ? l : hue2rgb(p, q, h - 1/3)
        let hex = String(format: "#%02X%02X%02X", Int(nr * 255), Int(ng * 255), Int(nb * 255))
        return (try? CodableColor(hex: hex)) ?? color
    }

    // MARK: - Two-Tone Color Mapping

    /// Map B&W output (0 or 255) to two specified colors.
    private static func applyTwoToneMapping(
        pixels: UnsafeMutablePointer<UInt8>,
        count: Int,
        foreground: CodableColor,
        background: CodableColor
    ) {
        let fgColor = foreground.cgColor
        let bgColor = background.cgColor

        let fgComponents = fgColor.components ?? [0, 0, 0, 1]
        let bgComponents = bgColor.components ?? [1, 1, 1, 1]

        let fgR = UInt8(max(0, min(255, round((fgComponents.count > 0 ? fgComponents[0] : 0) * 255))))
        let fgG = UInt8(max(0, min(255, round((fgComponents.count > 1 ? fgComponents[1] : 0) * 255))))
        let fgB = UInt8(max(0, min(255, round((fgComponents.count > 2 ? fgComponents[2] : 0) * 255))))

        let bgR = UInt8(max(0, min(255, round((bgComponents.count > 0 ? bgComponents[0] : 1) * 255))))
        let bgG = UInt8(max(0, min(255, round((bgComponents.count > 1 ? bgComponents[1] : 1) * 255))))
        let bgB = UInt8(max(0, min(255, round((bgComponents.count > 2 ? bgComponents[2] : 1) * 255))))

        for i in 0..<count {
            let idx = i * 4
            if pixels[idx] > 127 {
                pixels[idx] = fgR
                pixels[idx + 1] = fgG
                pixels[idx + 2] = fgB
            } else {
                pixels[idx] = bgR
                pixels[idx + 1] = bgG
                pixels[idx + 2] = bgB
            }
        }
    }

    // MARK: - Bayer Matrix

    /// Generate a Bayer threshold matrix of the specified level (used for cache init).
    /// Level 1 = 4x4, level 2 = 8x8, level 3 = 16x16, level 4 = 32x32.
    /// Values are normalized to [0, 1).
    static func bayerMatrix(level: Int) -> [[Double]] {
        generateBayerMatrix(level: level)
    }

    private static func generateBayerMatrix(level: Int) -> [[Double]] {
        let clampedLevel = max(1, min(4, level))

        var matrix: [[Double]] = [
            [0, 2],
            [3, 1]
        ]

        for _ in 0..<clampedLevel {
            let n = matrix.count
            let newSize = n * 2
            var expanded = [[Double]](repeating: [Double](repeating: 0, count: newSize), count: newSize)
            for y in 0..<newSize {
                for x in 0..<newSize {
                    let baseVal = matrix[y % n][x % n]
                    let quadrant: Double
                    if y < n && x < n { quadrant = 0 }
                    else if y < n { quadrant = 2 }
                    else if x < n { quadrant = 3 }
                    else { quadrant = 1 }
                    expanded[y][x] = 4.0 * baseVal + quadrant
                }
            }
            matrix = expanded
        }

        let size = matrix.count
        let total = Double(size * size)
        for y in 0..<size {
            for x in 0..<size {
                matrix[y][x] = (matrix[y][x] + 0.5) / total
            }
        }

        return matrix
    }

    // MARK: - Halftone (Clustered Dot) Matrix

    /// Generate a 6x6 clustered dot threshold matrix.
    static func halftoneMatrix() -> [[Double]] {
        let raw: [[Double]] = [
            [34, 29, 17, 21, 30, 35],
            [28, 14,  9, 16, 20, 31],
            [13,  8,  4,  5, 15, 19],
            [12,  3,  0,  1, 10, 18],
            [27,  7,  2,  6, 11, 24],
            [33, 26, 22, 23, 25, 32]
        ]
        var matrix = raw
        for y in 0..<6 {
            for x in 0..<6 {
                matrix[y][x] = (raw[y][x] + 0.5) / 36.0
            }
        }
        return matrix
    }

    // MARK: - Blue Noise Texture

    /// Generate a 64x64 blue noise threshold texture using R2 quasi-random sequence.
    static func blueNoiseTexture() -> [Double] {
        cachedBlueNoise
    }

    // MARK: - Floyd-Steinberg Error Diffusion (with serpentine)

    private static func floydSteinbergDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let leftToRight = (y % 2 == 0)
            let xRange = leftToRight
                ? stride(from: 0, to: width, by: 1)
                : stride(from: width - 1, to: -1, by: -1)
            for x in xRange {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeFloydSteinberg(&lumBuf, x, y, width, height, err, leftToRight)
            }
        }

        return output
    }

    private static func distributeFloydSteinberg(
        _ errors: inout [Double],
        _ x: Int, _ y: Int, _ width: Int, _ height: Int,
        _ error: Double, _ leftToRight: Bool
    ) {
        let fwd = leftToRight ? 1 : -1
        if x + fwd >= 0 && x + fwd < width {
            errors[y * width + (x + fwd)] += error * 7.0 / 16.0
        }
        if x - fwd >= 0 && x - fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x - fwd)] += error * 3.0 / 16.0
        }
        if y + 1 < height {
            errors[(y + 1) * width + x] += error * 5.0 / 16.0
        }
        if x + fwd >= 0 && x + fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x + fwd)] += error * 1.0 / 16.0
        }
    }

    // MARK: - Atkinson Error Diffusion (with serpentine)

    private static func atkinsonDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let leftToRight = (y % 2 == 0)
            let xRange = leftToRight
                ? stride(from: 0, to: width, by: 1)
                : stride(from: width - 1, to: -1, by: -1)
            for x in xRange {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeAtkinson(&lumBuf, x, y, width, height, err, leftToRight)
            }
        }

        return output
    }

    private static func distributeAtkinson(
        _ errors: inout [Double],
        _ x: Int, _ y: Int, _ width: Int, _ height: Int,
        _ error: Double, _ leftToRight: Bool
    ) {
        let fraction = error / 8.0
        let fwd = leftToRight ? 1 : -1
        if x + fwd >= 0 && x + fwd < width { errors[y * width + (x + fwd)] += fraction }
        if x + 2 * fwd >= 0 && x + 2 * fwd < width { errors[y * width + (x + 2 * fwd)] += fraction }
        if x - fwd >= 0 && x - fwd < width && y + 1 < height { errors[(y + 1) * width + (x - fwd)] += fraction }
        if y + 1 < height { errors[(y + 1) * width + x] += fraction }
        if x + fwd >= 0 && x + fwd < width && y + 1 < height { errors[(y + 1) * width + (x + fwd)] += fraction }
        if y + 2 < height { errors[(y + 2) * width + x] += fraction }
    }

    // MARK: - Artistic Drip Error Diffusion (with serpentine)

    private static func artisticDripDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let leftToRight = (y % 2 == 0)
            let xRange = leftToRight
                ? stride(from: 0, to: width, by: 1)
                : stride(from: width - 1, to: -1, by: -1)
            for x in xRange {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeArtisticDrip(&lumBuf, x, y, width, height, err, leftToRight)
            }
        }

        return output
    }

    private static func distributeArtisticDrip(
        _ errors: inout [Double],
        _ x: Int, _ y: Int, _ width: Int, _ height: Int,
        _ error: Double, _ leftToRight: Bool
    ) {
        let fwd = leftToRight ? 1 : -1
        if x + fwd >= 0 && x + fwd < width {
            errors[y * width + (x + fwd)] += error * 2.0 / 16.0
        }
        if x - fwd >= 0 && x - fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x - fwd)] += error * 1.0 / 16.0
        }
        if y + 1 < height {
            errors[(y + 1) * width + x] += error * 5.0 / 16.0
        }
        if x + fwd >= 0 && x + fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x + fwd)] += error * 2.0 / 16.0
        }
        if y + 2 < height {
            errors[(y + 2) * width + x] += error * 4.0 / 16.0
        }
        if y + 3 < height {
            errors[(y + 3) * width + x] += error * 2.0 / 16.0
        }
    }

    // MARK: - Stucki Error Diffusion (with serpentine)

    private static func stuckiDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let leftToRight = (y % 2 == 0)
            let xRange = leftToRight
                ? stride(from: 0, to: width, by: 1)
                : stride(from: width - 1, to: -1, by: -1)
            for x in xRange {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeStucki(&lumBuf, x, y, width, height, err, leftToRight)
            }
        }

        return output
    }

    private static func distributeStucki(
        _ errors: inout [Double],
        _ x: Int, _ y: Int, _ width: Int, _ height: Int,
        _ error: Double, _ leftToRight: Bool
    ) {
        let fwd = leftToRight ? 1 : -1
        if x + fwd >= 0 && x + fwd < width {
            errors[y * width + (x + fwd)] += error * 8.0 / 42.0
        }
        if x + 2 * fwd >= 0 && x + 2 * fwd < width {
            errors[y * width + (x + 2 * fwd)] += error * 4.0 / 42.0
        }
        if y + 1 < height {
            if x - 2 * fwd >= 0 && x - 2 * fwd < width { errors[(y + 1) * width + (x - 2 * fwd)] += error * 2.0 / 42.0 }
            if x - fwd >= 0 && x - fwd < width { errors[(y + 1) * width + (x - fwd)] += error * 4.0 / 42.0 }
            errors[(y + 1) * width + x] += error * 8.0 / 42.0
            if x + fwd >= 0 && x + fwd < width { errors[(y + 1) * width + (x + fwd)] += error * 4.0 / 42.0 }
            if x + 2 * fwd >= 0 && x + 2 * fwd < width { errors[(y + 1) * width + (x + 2 * fwd)] += error * 2.0 / 42.0 }
        }
        if y + 2 < height {
            if x - 2 * fwd >= 0 && x - 2 * fwd < width { errors[(y + 2) * width + (x - 2 * fwd)] += error * 1.0 / 42.0 }
            if x - fwd >= 0 && x - fwd < width { errors[(y + 2) * width + (x - fwd)] += error * 2.0 / 42.0 }
            errors[(y + 2) * width + x] += error * 4.0 / 42.0
            if x + fwd >= 0 && x + fwd < width { errors[(y + 2) * width + (x + fwd)] += error * 2.0 / 42.0 }
            if x + 2 * fwd >= 0 && x + 2 * fwd < width { errors[(y + 2) * width + (x + 2 * fwd)] += error * 1.0 / 42.0 }
        }
    }

    // MARK: - White Noise Dithering

    private static func whiteNoiseDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            let rowOff = y * width
            for x in 0..<width {
                let i = rowOff + x
                output[i] = lumBuf[i] > seededRandom(x: x, y: y) ? 255 : 0
            }
        }

        return output
    }

    /// Deterministic hash-based random for reproducible white noise.
    @inline(__always)
    private static func seededRandom(x: Int, y: Int) -> Double {
        var h = UInt64(x) &* 0x517cc1b727220a95
        h ^= UInt64(y) &* 0x6c62272e07bb0142
        h = h ^ (h >> 33)
        h = h &* 0xff51afd7ed558ccd
        h = h ^ (h >> 33)
        return Double(h & 0x7FFFFFFFFFFFFFFF) / Double(Int64.max)
    }

    // MARK: - Riemersma (Hilbert Curve) Dithering

    private static func riemersmaDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) throws -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        let path = cachedHilbertPath(width: width, height: height)

        let historySize = riemersmaHistorySize
        var errorHistory = [Double](repeating: 0, count: historySize)
        var historyIndex = 0
        let weights = riemersmaWeights.weights
        let totalWeight = riemersmaWeights.totalWeight

        for (step, packed) in path.enumerated() {
            if (step & 0x1FFF) == 0 { try Task.checkCancellation() }
            let x = Int(packed & 0xFFFF)
            let y = Int(packed >> 16)
            let i = y * width + x

            var accumulatedError = 0.0
            for j in 0..<historySize {
                let idx = (historyIndex - j - 1 + historySize * 2) % historySize
                accumulatedError += errorHistory[idx] * weights[j]
            }
            accumulatedError /= totalWeight

            let adjusted = max(0, min(1, lumBuf[i] + accumulatedError))
            let newVal: Double = adjusted > 0.5 ? 1.0 : 0.0
            let err = adjusted - newVal
            output[i] = newVal > 0.5 ? 255 : 0

            errorHistory[historyIndex] = err
            historyIndex = (historyIndex + 1) % historySize
        }

        return output
    }

    /// Riemersma channel dithering for color mode.
    private static func riemersmaChannelDither(
        buf: inout [Double],
        output: inout [UInt8],
        width: Int, height: Int,
        maxLevel: Double
    ) throws {
        let path = cachedHilbertPath(width: width, height: height)

        let historySize = riemersmaHistorySize
        var errorHistory = [Double](repeating: 0, count: historySize)
        var historyIndex = 0
        let weights = riemersmaWeights.weights
        let totalWeight = riemersmaWeights.totalWeight

        for (step, packed) in path.enumerated() {
            if (step & 0x1FFF) == 0 { try Task.checkCancellation() }
            let x = Int(packed & 0xFFFF)
            let y = Int(packed >> 16)
            let i = y * width + x

            var accumulatedError = 0.0
            for j in 0..<historySize {
                let idx = (historyIndex - j - 1 + historySize * 2) % historySize
                accumulatedError += errorHistory[idx] * weights[j]
            }
            accumulatedError /= totalWeight

            let adjusted = max(0, min(1, buf[i] + accumulatedError))
            let quantized = round(adjusted * maxLevel) / maxLevel
            let err = adjusted - quantized
            output[i] = linearToSRGBByte(quantized)

            errorHistory[historyIndex] = err
            historyIndex = (historyIndex + 1) % historySize
        }
    }

    /// Get or generate a cached Hilbert curve path. Packed as UInt32 (y << 16 | x).
    private static func cachedHilbertPath(width: Int, height: Int) -> [UInt32] {
        let key = UInt64(width) << 32 | UInt64(height)
        hilbertCacheLock.lock()
        if let cached = hilbertCache[key] {
            hilbertCacheLock.unlock()
            return cached
        }
        hilbertCacheLock.unlock()

        // Generate
        let maxDim = max(width, height)
        var order = 1
        while (1 << order) < maxDim { order += 1 }
        let n = 1 << order
        let totalPoints = n * n

        var path = [UInt32]()
        path.reserveCapacity(width * height)

        for d in 0..<totalPoints {
            let (x, y) = d2xy(n: n, d: d)
            if x < width && y < height {
                path.append(UInt32(y << 16 | x))
            }
        }

        hilbertCacheLock.lock()
        // Only cache reasonable sizes (< 64MB)
        if path.count < 16_000_000 {
            hilbertCache[key] = path
        }
        hilbertCacheLock.unlock()

        return path
    }

    /// Convert Hilbert curve distance d to (x, y) coordinates in an n×n grid.
    private static func d2xy(n: Int, d: Int) -> (Int, Int) {
        var rx: Int, ry: Int, s: Int
        var x = 0, y = 0
        var dd = d
        s = 1
        while s < n {
            rx = (dd / 2) & 1
            ry = ((dd ^ rx) & 1) ^ 1
            if ry == 0 {
                if rx == 1 {
                    x = s - 1 - x
                    y = s - 1 - y
                }
                let temp = x
                x = y
                y = temp
            }
            x += s * rx
            y += s * ry
            dd /= 4
            s *= 2
        }
        return (x, y)
    }
}
