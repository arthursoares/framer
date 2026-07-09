// Sources/FramerCore/Processing/DitherRenderer.swift
import Foundation
import CoreGraphics
import Accelerate

// MARK: - DitherRenderer

/// Entry point for the dither layer. GPU-only since the CPU dither
/// implementations were retired (docs/adr/2026-07-09-retire-cpu-effect-path.md),
/// with one deliberate exception: Riemersma dithering walks a Hilbert curve
/// with serial error history — it has no GPU port and is dispatched to the
/// CPU implementation kept in this file. Every other algorithm renders
/// through `DitherGPURenderer`; `MetalEffectError` propagates to the caller
/// instead of triggering a silently different CPU render.
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
    ///
    /// Dispatches by algorithm: `.riemersma` runs the kept CPU implementation
    /// (inherently serial Hilbert-curve walk, no GPU port); everything else
    /// runs `DitherGPURenderer.apply`, and any thrown error — including
    /// `MetalEffectError` on Metal-less hosts — propagates to the caller.
    public static func apply(
        to image: CGImage,
        params: DitherLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        if params.algorithm == .riemersma {
            return try applyRiemersma(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension,
                sourceImage: sourceImage
            )
        }
        return try DitherGPURenderer.apply(
            to: image,
            params: params,
            previewBaseDimension: previewBaseDimension,
            sourceImage: sourceImage
        )
    }

    /// CPU implementation for the Riemersma algorithm only. The shell
    /// (pixel-scale handling, sharpen/contrast pre-passes, color-mode
    /// mapping, nearest-neighbor upscale) is unchanged from the original CPU
    /// renderer; the non-Riemersma algorithm bodies were retired.
    private static func applyRiemersma(to image: CGImage, params: DitherLayerParams, previewBaseDimension: Int? = nil, sourceImage: CGImage? = nil) throws -> CGImage {
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

        // Apply dithering
        let threshold = max(0.1, min(0.9, params.threshold))
        switch params.colorMode {
        case .bw, .twoTone, .dominantTwoTone:
            try applyMonochromeRiemersma(
                pixels: pixels, width: workW, height: workH,
                threshold: threshold
            )
        case .color(let levels):
            try applyColorRiemersma(
                pixels: pixels, width: workW, height: workH,
                levels: max(2, min(8, levels)), threshold: threshold
            )
        case .palette(let colors):
            try applyPaletteRiemersma(
                pixels: pixels, width: workW, height: workH,
                threshold: threshold, palette: colors
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

    // MARK: - Monochrome Riemersma (B&W and Two-Tone)

    /// Riemersma monochrome dithering: each pixel becomes 0 or 255 based on luminance.
    private static func applyMonochromeRiemersma(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
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

        let output = try riemersmaDither(lumBuf: &lumBuf, width: width, height: height)

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

    // MARK: - Color Riemersma

    /// Riemersma color dithering: each R/G/B channel is independently quantized
    /// to N levels along the Hilbert curve (error diffusion is serial per channel).
    private static func applyColorRiemersma(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
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

        let maxLevel = Double(max(2, levels) - 1)
        var rOut = [UInt8](repeating: 0, count: count)
        var gOut = [UInt8](repeating: 0, count: count)
        var bOut = [UInt8](repeating: 0, count: count)
        try riemersmaChannelDither(buf: &rBuf, output: &rOut, width: width, height: height, maxLevel: maxLevel)
        try riemersmaChannelDither(buf: &gBuf, output: &gOut, width: width, height: height, maxLevel: maxLevel)
        try riemersmaChannelDither(buf: &bBuf, output: &bOut, width: width, height: height, maxLevel: maxLevel)

        for i in 0..<count {
            if (i & 0x3FFF) == 0 { try Task.checkCancellation() }
            let idx = i * 4
            pixels[idx] = rOut[i]
            pixels[idx + 1] = gOut[i]
            pixels[idx + 2] = bOut[i]
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

    // MARK: - Palette Riemersma
    //
    // Maps each pixel to the nearest colour in the palette (Euclidean
    // distance in linear RGB), with a hash-based threshold jitter to nudge
    // pixels across palette boundaries — the trick that makes vintage
    // palettes (GameBoy, NES, C64) look painterly instead of posterised.
    // True error diffusion on a palette is an open problem (the colour error
    // is multidimensional), so the Riemersma palette path uses the same
    // per-pixel hash jitter the retired CPU error-diffusion algorithms used.

    private static func applyPaletteRiemersma(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        threshold: Double,
        palette: [CodableColor]
    ) throws {
        guard !palette.isEmpty else { return }

        // Pre-convert palette to linear RGB once.
        let paletteLinear: [(Double, Double, Double)] = palette.map { c in
            (sRGBToLinearLUT[Int(c.red * 255.0)],
             sRGBToLinearLUT[Int(c.green * 255.0)],
             sRGBToLinearLUT[Int(c.blue * 255.0)])
        }
        // Final sRGB representations for write-back.
        let paletteSRGB: [(UInt8, UInt8, UInt8)] = palette.map { c in
            (UInt8(round(c.red * 255.0)),
             UInt8(round(c.green * 255.0)),
             UInt8(round(c.blue * 255.0)))
        }

        for y in 0..<height {
            if (y & 31) == 0 { try Task.checkCancellation() }
            for x in 0..<width {
                let idx = (y * width + x) * 4
                var r = sRGBToLinearLUT[Int(pixels[idx])]
                var g = sRGBToLinearLUT[Int(pixels[idx + 1])]
                var b = sRGBToLinearLUT[Int(pixels[idx + 2])]

                // Per-pixel hash jitter (Riemersma coefficient 1.0).
                let seed = (UInt64(x) &* 31 &+ UInt64(y) &* 17 &+ UInt64(x ^ y) &* 13) & 0xFFFF
                let jitter = (Double(seed) / 65535.0 - 0.5) * 0.1
                r = max(0.0, min(1.0, r + jitter))
                g = max(0.0, min(1.0, g + jitter))
                b = max(0.0, min(1.0, b + jitter))

                // Apply user threshold as a global brightness offset on the
                // jittered linear RGB.
                let brightnessShift = threshold - 0.5
                r = max(0.0, min(1.0, r + brightnessShift))
                g = max(0.0, min(1.0, g + brightnessShift))
                b = max(0.0, min(1.0, b + brightnessShift))

                // Nearest palette colour (squared Euclidean distance).
                var bestDist = Double.greatestFiniteMagnitude
                var bestIdx = 0
                for (i, p) in paletteLinear.enumerated() {
                    let dr = p.0 - r, dg = p.1 - g, db = p.2 - b
                    let d = dr * dr + dg * dg + db * db
                    if d < bestDist { bestDist = d; bestIdx = i }
                }
                let chosen = paletteSRGB[bestIdx]
                pixels[idx]     = chosen.0
                pixels[idx + 1] = chosen.1
                pixels[idx + 2] = chosen.2
            }
        }
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
