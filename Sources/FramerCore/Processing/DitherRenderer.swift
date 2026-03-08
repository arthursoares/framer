// Sources/FramerCore/Processing/DitherRenderer.swift
import Foundation
import CoreGraphics

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

    // MARK: - Public API

    /// Apply dithering to an image using the specified parameters.
    public static func apply(to image: CGImage, params: DitherLayerParams) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

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

        // Pre-processing: sharpen and contrast
        if params.sharpen > 0 {
            applySharpen(pixels: pixels, width: workW, height: workH, amount: params.sharpen)
        }
        if params.contrast > 0 {
            applyContrast(pixels: pixels, count: workW * workH, amount: params.contrast)
        }

        // Apply dithering algorithm
        let threshold = max(0.1, min(0.9, params.threshold))
        switch params.colorMode {
        case .bw, .twoTone:
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

    // MARK: - Pre-Processing

    /// Apply unsharp mask sharpening to enhance edges before dithering.
    private static func applySharpen(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        amount: Double
    ) {
        let count = width * height
        // Copy original pixels for the blur reference
        let original = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
        original.update(from: pixels, count: count * 4)
        defer { original.deallocate() }

        // Simple 3x3 box blur as the "unsharp" reference
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                for c in 0..<3 {
                    var sum = 0.0
                    var samples = 0.0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let ny = y + dy
                            let nx = x + dx
                            if ny >= 0 && ny < height && nx >= 0 && nx < width {
                                sum += Double(original[(ny * width + nx) * 4 + c])
                                samples += 1
                            }
                        }
                    }
                    let blurred = sum / samples
                    let orig = Double(original[idx + c])
                    // Unsharp mask: original + amount * (original - blurred)
                    let sharpened = orig + amount * 2.0 * (orig - blurred)
                    pixels[idx + c] = UInt8(max(0, min(255, round(sharpened))))
                }
            }
        }
    }

    /// Apply S-curve contrast enhancement before dithering.
    private static func applyContrast(
        pixels: UnsafeMutablePointer<UInt8>,
        count: Int,
        amount: Double
    ) {
        // S-curve using sigmoid: steeper curve = more contrast
        // amount 0 = no change, 1 = maximum contrast
        let strength = amount * 5.0 // Scale to useful sigmoid range
        for i in 0..<count {
            let idx = i * 4
            for c in 0..<3 {
                let v = Double(pixels[idx + c]) / 255.0
                // Centered sigmoid: pushes values away from 0.5
                let centered = v - 0.5
                let curved = centered * (1.0 + strength * (1.0 - 4.0 * centered * centered))
                let result = max(0, min(1, curved + 0.5))
                pixels[idx + c] = UInt8(round(result * 255.0))
            }
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
        bayerLevel: Int,
        threshold: Double
    ) throws {
        // Apply threshold offset in sRGB (perceptual) space for uniform brightness adjustment,
        // then convert to linear space for dithering calculations.
        let offset = threshold - 0.5
        let count = width * height
        var lumBuf = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let idx = i * 4
            let rAdj = max(0, min(255, Double(pixels[idx]) + offset * 255.0))
            let gAdj = max(0, min(255, Double(pixels[idx + 1]) + offset * 255.0))
            let bAdj = max(0, min(255, Double(pixels[idx + 2]) + offset * 255.0))
            let lr = sRGBToLinear(rAdj / 255.0)
            let lg = sRGBToLinear(gAdj / 255.0)
            let lb = sRGBToLinear(bAdj / 255.0)
            lumBuf[i] = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
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
                    let mapValue = matrix[y % size][x % size]
                    output[i] = lumBuf[i] > mapValue ? 255 : 0
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
                    let mapValue = noise[(y % 64) * 64 + (x % 64)]
                    output[i] = lumBuf[i] > mapValue ? 255 : 0
                }
            }

        case .artisticDrip:
            output = artisticDripDither(lumBuf: &lumBuf, width: width, height: height)

        case .halftone:
            let matrix = halftoneMatrix()
            let size = 6
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let mapValue = matrix[y % size][x % size]
                    output[i] = lumBuf[i] > mapValue ? 255 : 0
                }
            }

        case .stucki:
            output = stuckiDither(lumBuf: &lumBuf, width: width, height: height)

        case .whiteNoise:
            output = whiteNoiseDither(lumBuf: &lumBuf, width: width, height: height)

        case .riemersma:
            output = riemersmaDither(lumBuf: &lumBuf, width: width, height: height)
        }

        // Write back to pixel buffer
        for i in 0..<count {
            let idx = i * 4
            pixels[idx] = output[i]
            pixels[idx + 1] = output[i]
            pixels[idx + 2] = output[i]
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

        // Apply threshold offset in sRGB (perceptual) space before converting to linear
        let offset = threshold - 0.5
        for i in 0..<count {
            let idx = i * 4
            let rAdj = max(0.0, min(1.0, Double(pixels[idx]) / 255.0 + offset))
            let gAdj = max(0.0, min(1.0, Double(pixels[idx + 1]) / 255.0 + offset))
            let bAdj = max(0.0, min(1.0, Double(pixels[idx + 2]) / 255.0 + offset))
            rBuf[i] = sRGBToLinear(rAdj)
            gBuf[i] = sRGBToLinear(gAdj)
            bBuf[i] = sRGBToLinear(bAdj)
        }

        // Dither each channel independently
        let rOut = ditherChannel(&rBuf, width: width, height: height,
                                 algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)
        let gOut = ditherChannel(&gBuf, width: width, height: height,
                                 algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)
        let bOut = ditherChannel(&bBuf, width: width, height: height,
                                 algorithm: algorithm, bayerLevel: bayerLevel, levels: levels)

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
            serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeFloydSteinberg
            )

        case .atkinson:
            serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeAtkinson
            )

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
            serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeArtisticDrip
            )

        case .halftone:
            let matrix = halftoneMatrix()
            let size = 6
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

        case .stucki:
            serpentineErrorDiffusion(
                errors: &buf, output: &output, width: width, height: height,
                maxLevel: maxLevel, distribute: distributeStucki
            )

        case .whiteNoise:
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    let noise = seededRandom(x: x, y: y) - 0.5
                    let adjusted = buf[i] + noise / maxLevel
                    let quantized = round(adjusted * maxLevel) / maxLevel
                    let clamped = max(0, min(1, quantized))
                    let srgb = linearToSRGB(clamped)
                    output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                }
            }

        case .riemersma:
            // Riemersma uses Hilbert curve traversal — handled by dedicated function
            riemersmaChannelDither(buf: &buf, output: &output, width: width, height: height, maxLevel: maxLevel)
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
    ) {
        for y in 0..<height {
            let leftToRight = (y % 2 == 0)
            let xRange = leftToRight ? stride(from: 0, to: width, by: 1) : stride(from: width - 1, to: -1, by: -1)
            for x in xRange {
                let i = y * width + x
                let oldVal = max(0, min(1, errors[i]))
                let quantized = round(oldVal * maxLevel) / maxLevel
                let err = oldVal - quantized
                let srgb = linearToSRGB(max(0, min(1, quantized)))
                output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))
                distribute(&errors, x, y, width, height, err, leftToRight)
            }
        }
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

    /// Generate a Bayer threshold matrix of the specified level.
    /// Level 1 = 4x4, level 2 = 8x8, level 3 = 16x16, level 4 = 32x32.
    /// Values are normalized to [0, 1).
    static func bayerMatrix(level: Int) -> [[Double]] {
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
    /// Dots grow outward from center, producing a classic newspaper print effect.
    static func halftoneMatrix() -> [[Double]] {
        // Spiral fill order from center outward — classic clustered dot
        let raw: [[Double]] = [
            [34, 29, 17, 21, 30, 35],
            [28, 14,  9, 16, 20, 31],
            [13,  8,  4,  5, 15, 19],
            [12,  3,  0,  1, 10, 18],
            [27,  7,  2,  6, 11, 24],
            [33, 26, 22, 23, 25, 32]
        ]
        // Normalize to [0, 1)
        var matrix = raw
        for y in 0..<6 {
            for x in 0..<6 {
                matrix[y][x] = (raw[y][x] + 0.5) / 36.0
            }
        }
        return matrix
    }

    // MARK: - Floyd-Steinberg Error Diffusion (with serpentine)

    /// Floyd-Steinberg error diffusion to 4 neighbors with weights (7, 3, 5, 1) / 16.
    /// Uses serpentine scanning to reduce directional artifacts.
    private static func floydSteinbergDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
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
        // Forward: 7/16
        if x + fwd >= 0 && x + fwd < width {
            errors[y * width + (x + fwd)] += error * 7.0 / 16.0
        }
        // Back-below: 3/16
        if x - fwd >= 0 && x - fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x - fwd)] += error * 3.0 / 16.0
        }
        // Below: 5/16
        if y + 1 < height {
            errors[(y + 1) * width + x] += error * 5.0 / 16.0
        }
        // Forward-below: 1/16
        if x + fwd >= 0 && x + fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x + fwd)] += error * 1.0 / 16.0
        }
    }

    // MARK: - Atkinson Error Diffusion (with serpentine)

    /// Atkinson error diffusion: 1/8 to 6 neighbors (only 75% of error propagated).
    private static func atkinsonDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
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
        // Forward
        if x + fwd >= 0 && x + fwd < width { errors[y * width + (x + fwd)] += fraction }
        // Two forward
        if x + 2 * fwd >= 0 && x + 2 * fwd < width { errors[y * width + (x + 2 * fwd)] += fraction }
        // Back-below
        if x - fwd >= 0 && x - fwd < width && y + 1 < height { errors[(y + 1) * width + (x - fwd)] += fraction }
        // Below
        if y + 1 < height { errors[(y + 1) * width + x] += fraction }
        // Forward-below
        if x + fwd >= 0 && x + fwd < width && y + 1 < height { errors[(y + 1) * width + (x + fwd)] += fraction }
        // Two below
        if y + 2 < height { errors[(y + 2) * width + x] += fraction }
    }

    // MARK: - Blue Noise Texture

    /// Generate a 64x64 blue noise threshold texture using R2 quasi-random sequence.
    static func blueNoiseTexture() -> [Double] {
        let size = 64
        let count = size * size
        var texture = [Double](repeating: 0, count: count)

        let g = 1.32471795724474602596
        let a1 = 1.0 / g
        let a2 = 1.0 / (g * g)

        var points = [(index: Int, value: Double)](repeating: (0, 0), count: count)
        for i in 0..<count {
            let x = (0.5 + a1 * Double(i + 1)).truncatingRemainder(dividingBy: 1.0)
            let y = (0.5 + a2 * Double(i + 1)).truncatingRemainder(dividingBy: 1.0)
            let px = Int(x * Double(size)) % size
            let py = Int(y * Double(size)) % size
            let idx = py * size + px
            points[i] = (idx, Double(i) / Double(count))
        }

        for point in points {
            texture[point.index] = point.value
        }

        return texture
    }

    // MARK: - Artistic Drip Error Diffusion (with serpentine)

    /// Custom error diffusion kernel that pushes error predominantly downward ("dripping ink").
    private static func artisticDripDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
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
        // Forward: 2/16
        if x + fwd >= 0 && x + fwd < width {
            errors[y * width + (x + fwd)] += error * 2.0 / 16.0
        }
        // Back-below: 1/16
        if x - fwd >= 0 && x - fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x - fwd)] += error * 1.0 / 16.0
        }
        // Below: 5/16
        if y + 1 < height {
            errors[(y + 1) * width + x] += error * 5.0 / 16.0
        }
        // Forward-below: 2/16
        if x + fwd >= 0 && x + fwd < width && y + 1 < height {
            errors[(y + 1) * width + (x + fwd)] += error * 2.0 / 16.0
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

    // MARK: - Stucki Error Diffusion (with serpentine)

    /// Stucki error diffusion: 12-neighbor kernel with weights summing to 42.
    /// Produces smoother gradients than Floyd-Steinberg due to the wider kernel.
    private static func stuckiDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
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
        // Row 0 (current row): fwd+1 = 8/42, fwd+2 = 4/42
        if x + fwd >= 0 && x + fwd < width {
            errors[y * width + (x + fwd)] += error * 8.0 / 42.0
        }
        if x + 2 * fwd >= 0 && x + 2 * fwd < width {
            errors[y * width + (x + 2 * fwd)] += error * 4.0 / 42.0
        }
        // Row 1: -2=2, -1=4, 0=8, +1=4, +2=2
        if y + 1 < height {
            if x - 2 * fwd >= 0 && x - 2 * fwd < width { errors[(y + 1) * width + (x - 2 * fwd)] += error * 2.0 / 42.0 }
            if x - fwd >= 0 && x - fwd < width { errors[(y + 1) * width + (x - fwd)] += error * 4.0 / 42.0 }
            errors[(y + 1) * width + x] += error * 8.0 / 42.0
            if x + fwd >= 0 && x + fwd < width { errors[(y + 1) * width + (x + fwd)] += error * 4.0 / 42.0 }
            if x + 2 * fwd >= 0 && x + 2 * fwd < width { errors[(y + 1) * width + (x + 2 * fwd)] += error * 2.0 / 42.0 }
        }
        // Row 2: -2=1, -1=2, 0=4, +1=2, +2=1
        if y + 2 < height {
            if x - 2 * fwd >= 0 && x - 2 * fwd < width { errors[(y + 2) * width + (x - 2 * fwd)] += error * 1.0 / 42.0 }
            if x - fwd >= 0 && x - fwd < width { errors[(y + 2) * width + (x - fwd)] += error * 2.0 / 42.0 }
            errors[(y + 2) * width + x] += error * 4.0 / 42.0
            if x + fwd >= 0 && x + fwd < width { errors[(y + 2) * width + (x + fwd)] += error * 2.0 / 42.0 }
            if x + 2 * fwd >= 0 && x + 2 * fwd < width { errors[(y + 2) * width + (x + 2 * fwd)] += error * 1.0 / 42.0 }
        }
    }

    // MARK: - White Noise Dithering

    /// White noise (random) dithering: each pixel gets an independent random threshold.
    /// Produces a grainy, lo-fi aesthetic.
    private static func whiteNoiseDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let threshold = seededRandom(x: x, y: y)
                output[i] = lumBuf[i] > threshold ? 255 : 0
            }
        }

        return output
    }

    /// Deterministic hash-based random for reproducible white noise.
    @inline(__always)
    private static func seededRandom(x: Int, y: Int) -> Double {
        // Simple hash combining x, y coordinates for reproducibility
        var h = UInt64(x) &* 0x517cc1b727220a95
        h ^= UInt64(y) &* 0x6c62272e07bb0142
        h = h ^ (h >> 33)
        h = h &* 0xff51afd7ed558ccd
        h = h ^ (h >> 33)
        return Double(h & 0x7FFFFFFFFFFFFFFF) / Double(Int64.max)
    }

    // MARK: - Riemersma (Hilbert Curve) Dithering

    /// Riemersma dithering: error diffusion along a Hilbert curve path.
    /// Produces non-directional, organic-looking dithering patterns because
    /// the space-filling curve distributes error in all directions.
    private static func riemersmaDither(
        lumBuf: inout [Double],
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var output = [UInt8](repeating: 0, count: count)

        // Generate Hilbert curve path covering the image
        let path = hilbertCurve(width: width, height: height)

        // Error diffusion along the curve with exponential decay
        let historySize = 16
        var errorHistory = [Double](repeating: 0, count: historySize)
        var historyIndex = 0

        // Decay weights: most recent error has most influence
        var weights = [Double](repeating: 0, count: historySize)
        var totalWeight = 0.0
        for i in 0..<historySize {
            weights[i] = exp(-Double(i) * 0.3)
            totalWeight += weights[i]
        }

        for pos in path {
            let x = pos.0
            let y = pos.1
            guard x < width && y < height else { continue }
            let i = y * width + x

            // Add weighted error from history
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
    ) {
        let path = hilbertCurve(width: width, height: height)

        let historySize = 16
        var errorHistory = [Double](repeating: 0, count: historySize)
        var historyIndex = 0

        var weights = [Double](repeating: 0, count: historySize)
        var totalWeight = 0.0
        for i in 0..<historySize {
            weights[i] = exp(-Double(i) * 0.3)
            totalWeight += weights[i]
        }

        for pos in path {
            let x = pos.0
            let y = pos.1
            guard x < width && y < height else { continue }
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
            let srgb = linearToSRGB(max(0, min(1, quantized)))
            output[i] = UInt8(max(0, min(255, round(srgb * 255.0))))

            errorHistory[historyIndex] = err
            historyIndex = (historyIndex + 1) % historySize
        }
    }

    /// Generate a Hilbert curve path that covers a width×height rectangle.
    /// Returns array of (x, y) coordinates in curve traversal order.
    private static func hilbertCurve(width: Int, height: Int) -> [(Int, Int)] {
        // Find smallest power of 2 that covers both dimensions
        let maxDim = max(width, height)
        var order = 1
        while (1 << order) < maxDim { order += 1 }
        let n = 1 << order

        let totalPoints = n * n
        var path = [(Int, Int)]()
        path.reserveCapacity(width * height)

        for d in 0..<totalPoints {
            let (x, y) = d2xy(n: n, d: d)
            if x < width && y < height {
                path.append((x, y))
            }
        }

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
            ry = ((dd ^ rx) & 1) ^ 1  // Note: ry inverted for standard orientation
            // Rotate
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
