// Sources/FramerCore/Processing/Kernels/DitherCIFilter.swift
//
// CIFilter-based Bayer dithering using built-in Core Image filters.
// Avoids Metal kernel compilation issues with Swift Package Manager by
// constructing a CIFilter chain that approximates ordered (Bayer) dithering.

import CoreImage
import CoreGraphics

/// A CIFilter subclass that applies Bayer-style ordered dithering to an input image.
///
/// The filter chain:
/// 1. Convert to grayscale using CIColorMatrix (BT.709 luminance weights)
/// 2. Generate a tiled Bayer threshold pattern as a CIImage
/// 3. Compare grayscale luminance against the threshold pattern to produce B&W output
///
/// For color mode "bw", output is pure black and white.
/// For other color modes, the caller should handle color mapping after this filter.
public class DitherCIFilter: CIFilter {

    /// The input image to dither.
    @objc public var inputImage: CIImage?

    /// Threshold bias (0.1 to 0.9, default 0.5). Higher = brighter output.
    @objc public var threshold: Float = 0.5

    /// Bayer matrix level (1-4). Level 1 = 4x4, level 2 = 8x8, etc.
    @objc public var bayerLevel: Int = 2

    public override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }

        // Step 1: Convert to grayscale using BT.709 luminance
        let grayscale = applyGrayscale(to: input)

        // Step 2: Generate the Bayer threshold pattern tiled across the image extent
        let extent = input.extent
        let bayerPattern = generateBayerPatternImage(level: bayerLevel, tileOver: extent)

        // Step 3: Apply threshold comparison
        // We want: output = grayscale > (bayerPattern + thresholdBias) ? white : black
        // Remap threshold: 0.5 means no bias, <0.5 darkens, >0.5 brightens
        let bias = threshold - 0.5  // range -0.4 to 0.4

        // Adjust the Bayer pattern by subtracting the bias
        // So effectively: grayscale > bayerPattern - bias
        // Which means higher threshold -> pattern shifted down -> more white
        let adjustedPattern = applyBrightnessShift(to: bayerPattern, shift: -bias)

        // Step 4: Subtract pattern from grayscale and threshold at 0
        // difference = grayscale - adjustedPattern
        // output = difference > 0 ? white : black
        let dithered = applyThresholdComparison(grayscale: grayscale, pattern: adjustedPattern, extent: extent)

        return dithered
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
