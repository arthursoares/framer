// Sources/FramerCore/Processing/Kernels/DitherCIFilter.swift
//
// CIFilter-based Bayer dithering using built-in Core Image filters.
// Avoids Metal kernel compilation issues with Swift Package Manager by
// constructing a CIFilter chain that approximates ordered (Bayer) dithering.

import CoreImage
import CoreGraphics

/// A CIFilter subclass that applies Bayer-style ordered dithering to an input image.
///
/// Supports multiple color modes:
/// - B&W: Pure black and white output
/// - Two-tone: Map to two custom colors
/// - Color quantization: Reduce each channel to N levels
///
/// The filter chain:
/// 1. Convert to grayscale (for B&W/two-tone) or keep color (for color mode)
/// 2. Generate a tiled Bayer threshold pattern as a CIImage
/// 3. Compare against the threshold pattern to produce dithered output
public class DitherCIFilter: CIFilter {

    /// The input image to dither.
    @objc public var inputImage: CIImage?

    /// Threshold bias (0.1 to 0.9, default 0.5). Higher = brighter output.
    @objc public var threshold: Float = 0.5

    /// Bayer matrix level (1-4). Level 1 = 4x4, level 2 = 8x8, etc.
    @objc public var bayerLevel: Int = 2

    /// Color mode for the dither output.
    public var colorMode: DitherColorMode = .bw

    /// Source image for dominant color extraction (optional, used for dominantTwoTone).
    public var sourceImage: CIImage?

    /// CIContext for dominant color extraction (rendering to CGImage).
    public var ciContext: CIContext?

    /// Cached dominant colors to avoid re-extracting per frame in video processing.
    private static var cachedDominantColors: (primary: CodableColor, secondary: CodableColor)?

    public override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }

        switch colorMode {
        case .bw:
            return applyBWDither(to: input)
        case .twoTone(let fg, let bg):
            return applyTwoToneDither(to: input, foreground: fg, background: bg)
        case .dominantTwoTone(let flipped):
            let colors = extractDominantColors(from: sourceImage ?? input)
            let fg = flipped ? colors.secondary : colors.primary
            let bg = flipped ? colors.primary : colors.secondary
            return applyTwoToneDither(to: input, foreground: fg, background: bg)
        case .color(let levels):
            return applyColorDither(to: input, levels: max(2, min(8, levels)))
        }
    }

    // MARK: - B&W Dithering

    private func applyBWDither(to input: CIImage) -> CIImage {
        let extent = input.extent

        // Convert to grayscale
        let grayscale = applyGrayscale(to: input)

        // Generate Bayer pattern
        let bayerPattern = generateBayerPatternImage(level: bayerLevel, tileOver: extent)

        // Apply threshold
        let bias = threshold - 0.5
        let adjustedPattern = applyBrightnessShift(to: bayerPattern, shift: -bias)

        return applyThresholdComparison(grayscale: grayscale, pattern: adjustedPattern, extent: extent)
    }

    // MARK: - Two-Tone Dithering

    private func applyTwoToneDither(to input: CIImage, foreground: CodableColor, background: CodableColor) -> CIImage {
        // First get B&W dither mask
        let bwMask = applyBWDither(to: input)

        // Use the B&W mask to blend between background and foreground colors
        // Where mask is white → foreground, where mask is black → background
        let extent = input.extent

        let fgColor = CIColor(
            red: CGFloat(foreground.red),
            green: CGFloat(foreground.green),
            blue: CGFloat(foreground.blue),
            alpha: 1.0
        )
        let bgColor = CIColor(
            red: CGFloat(background.red),
            green: CGFloat(background.green),
            blue: CGFloat(background.blue),
            alpha: 1.0
        )

        let fgImage = CIImage(color: fgColor).cropped(to: extent)
        let bgImage = CIImage(color: bgColor).cropped(to: extent)

        // Use CIBlendWithMask: where mask is white → foreground, black → background
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return bwMask
        }
        blendFilter.setValue(fgImage, forKey: kCIInputImageKey)
        blendFilter.setValue(bgImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(bwMask, forKey: "inputMaskImage")

        return blendFilter.outputImage?.cropped(to: extent) ?? bwMask
    }

    // MARK: - Color Dithering

    private func applyColorDither(to input: CIImage, levels: Int) -> CIImage {
        let extent = input.extent

        // Generate Bayer pattern
        let bayerPattern = generateBayerPatternImage(level: bayerLevel, tileOver: extent)

        // Color quantization with ordered dithering:
        // For each channel: quantized = round((color * (levels-1) + bayer - 0.5) * threshold_adjust) / (levels-1)
        //
        // We approximate this with CIFilter chain:
        // 1. Scale color values by (levels-1)
        // 2. Add shifted Bayer pattern (centered around 0)
        // 3. Round to integers (via extreme contrast trick)
        // 4. Scale back by 1/(levels-1)

        let levelsF = CGFloat(levels)
        let scale = levelsF - 1.0

        // Step 1: Multiply input by (levels-1) to spread values across integer range
        let scaled = applyColorScale(to: input, scale: Float(scale))

        // Step 2: Add Bayer pattern shifted to [-0.5, 0.5] range, adjusted by threshold
        let bias = threshold - 0.5
        let shiftedBayer = applyBrightnessShift(to: bayerPattern, shift: -(0.5 + bias))

        // Add Bayer to scaled image
        guard let addFilter = CIFilter(name: "CIAdditionCompositing") else { return input }
        addFilter.setValue(shiftedBayer, forKey: kCIInputImageKey)
        addFilter.setValue(scaled, forKey: kCIInputBackgroundImageKey)
        guard let added = addFilter.outputImage?.cropped(to: extent) else { return input }

        // Step 3: Quantize by scaling to [0,1], applying extreme contrast per-level,
        // then scaling back. We use the posterize approach: divide by scale, clamp, multiply.
        // CIColorPosterize does exactly this.
        guard let posterize = CIFilter(name: "CIColorPosterize") else { return input }
        posterize.setValue(added, forKey: kCIInputImageKey)
        posterize.setValue(Float(levels), forKey: "inputLevels")
        guard let posterized = posterize.outputImage else { return input }

        // Scale back to [0,1] range
        let result = applyColorScale(to: posterized, scale: Float(1.0 / scale))

        // Clamp to valid range
        guard let clamp = CIFilter(name: "CIColorClamp") else { return result }
        clamp.setValue(result, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")

        return clamp.outputImage?.cropped(to: extent) ?? result.cropped(to: extent)
    }

    // MARK: - Dominant Color Extraction

    /// Clear cached dominant colors (call when switching to a new image/video).
    public static func clearColorCache() {
        cachedDominantColors = nil
    }

    private func extractDominantColors(from image: CIImage) -> (primary: CodableColor, secondary: CodableColor) {
        // Return cached colors if available (avoids per-frame GPU→CPU round-trip in video)
        if let cached = Self.cachedDominantColors {
            return cached
        }

        // Try to render to CGImage for color extraction
        let ctx = ciContext ?? CIContext()
        if let cgImage = ctx.createCGImage(image, from: image.extent) {
            let (primary, secondary) = ColorExtractor.extractTwoDominantColors(from: cgImage)
            let result = (primary, secondary)
            Self.cachedDominantColors = result
            return result
        }
        // Fallback: black and white
        return (.black, .white)
    }

    // MARK: - Filter Chain Components

    /// Convert image to grayscale using BT.709 luminance coefficients.
    private func applyGrayscale(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        // BT.709: Y = 0.2126R + 0.7152G + 0.0722B
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0.2126, y: 0.2126, z: 0.2126, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0.7152, y: 0.7152, z: 0.7152, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0.0722, y: 0.0722, z: 0.0722, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        return filter.outputImage ?? image
    }

    /// Scale all color channels by a factor.
    private func applyColorScale(to image: CIImage, scale: Float) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        let s = CGFloat(scale)
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: s, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: s, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: s, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        return filter.outputImage ?? image
    }

    /// Generate a CIImage of the Bayer threshold matrix, tiled to cover the given extent.
    private func generateBayerPatternImage(level: Int, tileOver extent: CGRect) -> CIImage {
        let matrix = DitherRenderer.bayerMatrix(level: max(1, min(4, level)))
        let size = matrix.count

        // Create a CGImage from the Bayer matrix values (grayscale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ), let data = ctx.data else {
            return CIImage(color: .gray).cropped(to: extent)
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 4
                let val = UInt8(max(0, min(255, round(matrix[y][x] * 255.0))))
                pixels[idx] = val
                pixels[idx + 1] = val
                pixels[idx + 2] = val
                pixels[idx + 3] = 255
            }
        }

        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .gray).cropped(to: extent)
        }

        // Create CIImage from the small Bayer tile and tile it
        let tile = CIImage(cgImage: cgImage)

        // Use CIAffineTile to repeat the pattern
        guard let tileFilter = CIFilter(name: "CIAffineTile") else {
            return CIImage(color: .gray).cropped(to: extent)
        }
        tileFilter.setValue(tile, forKey: kCIInputImageKey)
        tileFilter.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)

        guard let tiled = tileFilter.outputImage else {
            return CIImage(color: .gray).cropped(to: extent)
        }

        return tiled.cropped(to: extent)
    }

    /// Shift brightness of an image by a constant.
    private func applyBrightnessShift(to image: CIImage, shift: Float) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        let s = CGFloat(shift)
        filter.setValue(CIVector(x: s, y: s, z: s, w: 0), forKey: "inputBiasVector")
        return filter.outputImage ?? image
    }

    /// Compare grayscale image against pattern: output white where grayscale > pattern, black otherwise.
    /// Uses CIColorClamp + CISubtractBlendMode + high-contrast color controls.
    private func applyThresholdComparison(grayscale: CIImage, pattern: CIImage, extent: CGRect) -> CIImage {
        // Subtract pattern from grayscale using CISubtractBlendMode
        // Result: positive where grayscale > pattern, negative (clamped to 0) otherwise
        guard let subtractFilter = CIFilter(name: "CISubtractBlendMode") else { return grayscale }
        subtractFilter.setValue(grayscale, forKey: kCIInputImageKey)
        subtractFilter.setValue(pattern, forKey: kCIInputBackgroundImageKey)
        guard let difference = subtractFilter.outputImage else { return grayscale }

        // Now we need to threshold: anything > 0 becomes white, 0 stays black
        // Use extreme contrast via CIColorControls
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return difference }
        contrastFilter.setValue(difference, forKey: kCIInputImageKey)
        contrastFilter.setValue(Float(0.5), forKey: kCIInputBrightnessKey)
        contrastFilter.setValue(Float(100.0), forKey: kCIInputContrastKey)
        contrastFilter.setValue(Float(0.0), forKey: kCIInputSaturationKey)
        guard let thresholded = contrastFilter.outputImage else { return difference }

        // Clamp values to [0,1]
        guard let clampFilter = CIFilter(name: "CIColorClamp") else { return thresholded }
        clampFilter.setValue(thresholded, forKey: kCIInputImageKey)
        clampFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputMinComponents")
        clampFilter.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")

        return clampFilter.outputImage?.cropped(to: extent) ?? thresholded.cropped(to: extent)
    }
}
