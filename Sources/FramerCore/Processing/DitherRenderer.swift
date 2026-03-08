// Sources/FramerCore/Processing/DitherRenderer.swift
import Foundation
import CoreGraphics

// MARK: - DitherRenderer

/// Applies dithering effects to images using various algorithms and color modes.
///
/// Supports five dithering algorithms (Bayer ordered, Floyd-Steinberg, Atkinson,
/// Blue Noise threshold, and Artistic Drip) with three color modes (black & white,
/// two-tone, and quantized color).
///
/// All luminance calculations use sRGB↔linear gamma conversion per IEC 61966-2-1.
public enum DitherRenderer {

    // MARK: - Public API

    /// Apply dithering to an image using the specified parameters.
    ///
    /// - Parameters:
    ///   - image: The source CGImage to dither.
    ///   - params: Dithering parameters (algorithm, color mode, Bayer level, pixel scale).
    /// - Returns: A new CGImage with dithering applied.
    public static func apply(to image: CGImage, params: DitherLayerParams) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Rasterize into RGBA8 buffer
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // Pixel scale: downscale with bilinear interpolation before dithering
        let scale = max(1, min(8, params.pixelScale))
        let workW: Int
        let workH: Int
        let workImage: CGImage
        if scale > 1 {
            workW = max(1, width / scale)
            workH = max(1, height / scale)
            guard let ctx = CGContext(
                data: nil, width: workW, height: workH,
                bitsPerComponent: 8, bytesPerRow: workW * 4,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: workW, height: workH))
            guard let downscaled = ctx.makeImage() else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            workImage = downscaled
        } else {
            workW = width
            workH = height
            workImage = image
        }

        // Create working context and extract pixel data
        guard let ctx = CGContext(
            data: nil, width: workW, height: workH,
            bitsPerComponent: 8, bytesPerRow: workW * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        ctx.draw(workImage, in: CGRect(x: 0, y: 0, width: workW, height: workH))

        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: workW * workH * 4)

        // Apply dithering algorithm
        switch params.colorMode {
        case .bw, .twoTone:
            try applyMonochromeDither(
                pixels: pixels, width: workW, height: workH,
                algorithm: params.algorithm, bayerLevel: params.bayerLevel
            )
        case .color(let levels):
            try applyColorDither(
                pixels: pixels, width: workW, height: workH,
                algorithm: params.algorithm, bayerLevel: params.bayerLevel,
                levels: max(2, min(8, levels))
            )
        }

        // Apply color mapping for two-tone mode
        if case .twoTone(let fg, let bg) = params.colorMode {
            applyTwoToneMapping(pixels: pixels, count: workW * workH, foreground: fg, background: bg)
        }

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
        let lr = sRGBToLinear(Double(r) / 255.0)
        let lg = sRGBToLinear(Double(g) / 255.0)
        let lb = sRGBToLinear(Double(b) / 255.0)
        return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
    }

    // MARK: - Monochrome Dithering (B&W and Two-Tone)

    /// Apply monochrome dithering: each pixel becomes 0 or 255 based on luminance.
    private static func applyMonochromeDither(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        algorithm: DitherAlgorithm,
        bayerLevel: Int
    ) throws {
        // Convert to luminance buffer in linear space
        let count = width * height
        var lumBuf = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let idx = i * 4
            lumBuf[i] = luminance(r: pixels[idx], g: pixels[idx + 1], b: pixels[idx + 2])
        }

        // Apply dithering algorithm to produce 0/1 decisions
        var output = [UInt8](repeating: 0, count: count)

        switch algorithm {
        case .bayer:
            let matrix = bayerMatrix(level: bayerLevel)
            let size = matrix.count
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let threshold = matrix[y % size][x % size]
                    output[i] = lumBuf[i] > threshold ? 255 : 0
                }
            }

        case .floydSteinberg:
            output = floydSteinbergDither(lumBuf: &lumBuf, width: width, height: height)

        case .atkinson:
            output = atkinsonDither(lumBuf: &lumBuf, width: width, height: height)

        case .blueNoise:
            let noise = blueNoiseTexture()
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let threshold = noise[(y % 64) * 64 + (x % 64)]
                    output[i] = lumBuf[i] > threshold ? 255 : 0
                }
            }

        case .artisticDrip:
            output = artisticDripDither(lumBuf: &lumBuf, width: width, height: height)
        }

        // Write back to pixel buffer
        for i in 0..<count {
            let idx = i * 4
            pixels[idx] = output[i]
            pixels[idx + 1] = output[i]
            pixels[idx + 2] = output[i]
            // Alpha unchanged
        }
    }

    // MARK: - Color Dithering

    /// Apply color dithering: each R/G/B channel is independently quantized to N levels.
    private static func applyColorDither(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        algorithm: DitherAlgorithm,
        bayerLevel: Int,
        levels: Int
    ) throws {
        let count = width * height

        // Convert each channel to linear space
        var rBuf = [Double](repeating: 0, count: count)
        var gBuf = [Double](repeating: 0, count: count)
        var bBuf = [Double](repeating: 0, count: count)

        for i in 0..<count {
            let idx = i * 4
            rBuf[i] = sRGBToLinear(Double(pixels[idx]) / 255.0)
            gBuf[i] = sRGBToLinear(Double(pixels[idx + 1]) / 255.0)
            bBuf[i] = sRGBToLinear(Double(pixels[idx + 2]) / 255.0)
        }

        // Dither each channel independently
        let rOut = ditherChannel(&rBuf, width: width, height: height,
                                 algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)
        let gOut = ditherChannel(&gBuf, width: width, height: height,
                                 algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)
        let bOut = ditherChannel(&bBuf, width: width, height: height,
                                 algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)

        // Write back to pixel buffer
        for i in 0..<count {
            let idx = i * 4
            pixels[idx] = rOut[i]
            pixels[idx + 1] = gOut[i]
            pixels[idx + 2] = bOut[i]
        }
    }

    /// Dither a single channel to the specified number of levels.
    private static func ditherChannel(
        _ buf: inout [Double],
        width: Int, height: Int,
        algorithm: DitherAlgorithm,
        bayerLevel: Int,
        levels: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)
        let maxLevel = Double(levels - 1)

        switch algorithm {
        case .bayer:
            let matrix = bayerMatrix(level: bayerLevel)
            let size = matrix.count
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let threshold = matrix[y % size][x % size] - 0.5
                    let adjusted = buf[i] + threshold / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    let clamped = max(0, min(1, quantized))
                    let srgb = linearToSRGB(clamped)
                    output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                }
            }

        case .floydSteinberg:
            var errors = buf
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let oldVal = max(0, min(1, errors[i]))
                    let quantized = round(oldVal * maxLevel) / maxLevel
                    let err = oldVal - quantized
                    let srgb = linearToSRGB(max(0, min(1, quantized)))
                    output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                    distributeFloydSteinberg(errors: &errors, x: x, y: y, width: width, height: height, error: err)
                }
            }

        case .atkinson:
            var errors = buf
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let oldVal = max(0, min(1, errors[i]))
                    let quantized = round(oldVal * maxLevel) / maxLevel
                    let err = oldVal - quantized
                    let srgb = linearToSRGB(max(0, min(1, quantized)))
                    output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                    distributeAtkinson(errors: &errors, x: x, y: y, width: width, height: height, error: err)
                }
            }

        case .blueNoise:
            let noise = blueNoiseTexture()
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let threshold = noise[(y % 64) * 64 + (x % 64)] - 0.5
                    let adjusted = buf[i] + threshold / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    let clamped = max(0, min(1, quantized))
                    let srgb = linearToSRGB(clamped)
                    output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                }
            }

        case .artisticDrip:
            var errors = buf
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let oldVal = max(0, min(1, errors[i]))
                    let quantized = round(oldVal * maxLevel) / maxLevel
                    let err = oldVal - quantized
                    let srgb = linearToSRGB(max(0, min(1, quantized)))
                    output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                    distributeArtisticDrip(errors: &errors, x: x, y: y, width: width, height: height, error: err)
                }
            }
        }

        return output
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
                // White → foreground
                pixels[idx] = fgR
                pixels[idx + 1] = fgG
                pixels[idx + 2] = fgB
            } else {
                // Black → background
                pixels[idx] = bgR
                pixels[idx + 1] = bgG
                pixels[idx + 2] = bgB
            }
        }
    }

    // MARK: - Bayer Matrix

    /// Generate a Bayer threshold matrix of the specified level.
    /// Level 1 = 4x4, level 2 = 8x8, level 3 = 16x16, level 4 = 32x32.
    /// Values are normalized to [0, 1).
    static func bayerMatrix(level: Int) -> [[Double]] {
        let clampedLevel = max(1, min(4, level))

        // Start with 2x2 base
        var matrix: [[Double]] = [
            [0, 2],
            [3, 1]
        ]

        // Recursively expand to desired level
        // Level 1 = one expansion (4x4), level 2 = two (8x8), etc.
        for _ in 0..<clampedLevel {
            let n = matrix.count
            let newSize = n * 2
            var expanded = [[Double]](repeating: [Double](repeating: 0, count: newSize), count: newSize)
            for y in 0..<newSize {
                for x in 0..<newSize {
                    let baseVal = matrix[y % n][x % n]
                    let quadrant: Double
                    if y < n && x < n { quadrant = 0 }      // top-left
                    else if y < n { quadrant = 2 }            // top-right
                    else if x < n { quadrant = 3 }            // bottom-left
                    else { quadrant = 1 }                     // bottom-right
                    expanded[y][x] = 4.0 * baseVal + quadrant
                }
            }
            matrix = expanded
        }

        // Normalize to [0, 1)
        let size = matrix.count
        let total = Double(size * size)
        for y in 0..<size {
            for x in 0..<size {
                matrix[y][x] = (matrix[y][x] + 0.5) / total
            }
        }

        return matrix
    }

    // MARK: - Floyd-Steinberg Error Diffusion

    /// Floyd-Steinberg error diffusion to 4 neighbors with weights (7, 3, 5, 1) / 16.
    private static func floydSteinbergDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeFloydSteinberg(errors: &lumBuf, x: x, y: y, width: width, height: height, error: err)
            }
        }

        return output
    }

    @inline(__always)
    private static func distributeFloydSteinberg(
        errors: inout [Double],
        x: Int, y: Int, width: Int, height: Int,
        error: Double
    ) {
        // Right: 7/16
        if x + 1 < width {
            errors[y * width + (x + 1)] += error * 7.0 / 16.0
        }
        // Bottom-left: 3/16
        if x - 1 >= 0 && y + 1 < height {
            errors[(y + 1) * width + (x - 1)] += error * 3.0 / 16.0
        }
        // Bottom: 5/16
        if y + 1 < height {
            errors[(y + 1) * width + x] += error * 5.0 / 16.0
        }
        // Bottom-right: 1/16
        if x + 1 < width && y + 1 < height {
            errors[(y + 1) * width + (x + 1)] += error * 1.0 / 16.0
        }
    }

    // MARK: - Atkinson Error Diffusion

    /// Atkinson error diffusion: 1/8 to 6 neighbors (only 75% of error propagated).
    private static func atkinsonDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeAtkinson(errors: &lumBuf, x: x, y: y, width: width, height: height, error: err)
            }
        }

        return output
    }

    @inline(__always)
    private static func distributeAtkinson(
        errors: inout [Double],
        x: Int, y: Int, width: Int, height: Int,
        error: Double
    ) {
        let fraction = error / 8.0
        // Right
        if x + 1 < width { errors[y * width + (x + 1)] += fraction }
        // Two right
        if x + 2 < width { errors[y * width + (x + 2)] += fraction }
        // Bottom-left
        if x - 1 >= 0 && y + 1 < height { errors[(y + 1) * width + (x - 1)] += fraction }
        // Bottom
        if y + 1 < height { errors[(y + 1) * width + x] += fraction }
        // Bottom-right
        if x + 1 < width && y + 1 < height { errors[(y + 1) * width + (x + 1)] += fraction }
        // Two below
        if y + 2 < height { errors[(y + 2) * width + x] += fraction }
    }

    // MARK: - Blue Noise Texture

    /// Generate a 64x64 blue noise threshold texture using R2 quasi-random sequence.
    /// Values are normalized to [0, 1).
    static func blueNoiseTexture() -> [Double] {
        let size = 64
        let count = size * size
        var texture = [Double](repeating: 0, count: count)

        // R2 quasi-random sequence (generalized golden ratio in 2D)
        // g = 1.32471795724... (plastic constant)
        let g = 1.32471795724474602596
        let a1 = 1.0 / g
        let a2 = 1.0 / (g * g)

        // Generate R2 sequence and rank pixels
        var points = [(index: Int, value: Double)](repeating: (0, 0), count: count)
        for i in 0..<count {
            let x = (0.5 + a1 * Double(i + 1)).truncatingRemainder(dividingBy: 1.0)
            let y = (0.5 + a2 * Double(i + 1)).truncatingRemainder(dividingBy: 1.0)
            let px = Int(x * Double(size)) % size
            let py = Int(y * Double(size)) % size
            let idx = py * size + px
            points[i] = (idx, Double(i) / Double(count))
        }

        // Fill texture: later points overwrite earlier ones at same position
        for point in points {
            texture[point.index] = point.value
        }

        return texture
    }

    // MARK: - Artistic Drip Error Diffusion

    /// Custom error diffusion kernel that pushes error predominantly downward,
    /// creating a "dripping ink" effect.
    ///
    /// Kernel (fractions of error):
    ///   [x+1, y]: 2/16, [x-1, y+1]: 1/16, [x, y+1]: 5/16,
    ///   [x+1, y+1]: 2/16, [x, y+2]: 4/16, [x, y+3]: 2/16
    private static func artisticDripDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let oldVal = max(0, min(1, lumBuf[i]))
                let newVal: Double = oldVal > 0.5 ? 1.0 : 0.0
                let err = oldVal - newVal
                output[i] = newVal > 0.5 ? 255 : 0
                distributeArtisticDrip(errors: &lumBuf, x: x, y: y, width: width, height: height, error: err)
            }
        }

        return output
    }

    @inline(__always)
    private static func distributeArtisticDrip(
        errors: inout [Double],
        x: Int, y: Int, width: Int, height: Int,
        error: Double
    ) {
        // Right: 2/16
        if x + 1 < width {
            errors[y * width + (x + 1)] += error * 2.0 / 16.0
        }
        // Bottom-left: 1/16
        if x - 1 >= 0 && y + 1 < height {
            errors[(y + 1) * width + (x - 1)] += error * 1.0 / 16.0
        }
        // Bottom: 5/16
        if y + 1 < height {
            errors[(y + 1) * width + x] += error * 5.0 / 16.0
        }
        // Bottom-right: 2/16
        if x + 1 < width && y + 1 < height {
            errors[(y + 1) * width + (x + 1)] += error * 2.0 / 16.0
        }
        // Two below: 4/16
        if y + 2 < height {
            errors[(y + 2) * width + x] += error * 4.0 / 16.0
        }
        // Three below: 2/16
        if y + 3 < height {
            errors[(y + 3) * width + x] += error * 2.0 / 16.0
        }
    }
}
