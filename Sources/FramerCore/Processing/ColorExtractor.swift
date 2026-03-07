// Sources/FramerCore/Processing/ColorExtractor.swift
import Foundation
import CoreGraphics

// MARK: - HSLColor

public struct HSLColor: Codable, Equatable, Sendable {
    /// Hue: 0-360
    public var h: Double
    /// Saturation: 0-100
    public var s: Double
    /// Lightness: 0-100
    public var l: Double

    public init(h: Double, s: Double, l: Double) {
        self.h = h
        self.s = s
        self.l = l
    }

    /// Convert HSL to RGB components (each 0-1).
    public var rgbComponents: (r: Double, g: Double, b: Double) {
        let hNorm = h / 360.0
        let sNorm = s / 100.0
        let lNorm = l / 100.0

        guard sNorm > 0 else {
            return (lNorm, lNorm, lNorm)
        }

        let q = lNorm < 0.5 ? lNorm * (1 + sNorm) : lNorm + sNorm - lNorm * sNorm
        let p = 2 * lNorm - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
            return p
        }

        let r = hueToRGB(p, q, hNorm + 1.0 / 3.0)
        let g = hueToRGB(p, q, hNorm)
        let b = hueToRGB(p, q, hNorm - 1.0 / 3.0)
        return (r, g, b)
    }

    public var cgColor: CGColor {
        let (r, g, b) = rgbComponents
        return CGColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Convert RGB (each 0-255) to HSL.
    public static func fromRGB(r: Double, g: Double, b: Double) -> HSLColor {
        let rNorm = r / 255.0
        let gNorm = g / 255.0
        let bNorm = b / 255.0

        let maxC = max(rNorm, gNorm, bNorm)
        let minC = min(rNorm, gNorm, bNorm)
        let delta = maxC - minC

        let l = (maxC + minC) / 2.0

        guard delta > 0 else {
            return HSLColor(h: 0, s: 0, l: l * 100)
        }

        let s = l > 0.5 ? delta / (2.0 - maxC - minC) : delta / (maxC + minC)

        var h: Double
        if maxC == rNorm {
            h = ((gNorm - bNorm) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == gNorm {
            h = (bNorm - rNorm) / delta + 2
        } else {
            h = (rNorm - gNorm) / delta + 4
        }
        h *= 60
        if h < 0 { h += 360 }

        return HSLColor(h: h, s: s * 100, l: l * 100)
    }
}

// MARK: - ColorExtractor

public enum ColorExtractor {
    private static let sampleSize = 50
    private static let bucketCount = 12
    private static let degreesPerBucket = 30.0
    private static let grayscaleThreshold = 15.0

    /// Extract the dominant color from an image using hue-bucket analysis.
    public static func extractDominantColor(from image: CGImage) -> HSLColor {
        let pixels = samplePixels(from: image)
        guard !pixels.isEmpty else {
            return HSLColor(h: 220, s: 5, l: 50)
        }

        // Convert to HSL
        let hslPixels = pixels.map { HSLColor.fromRGB(r: $0.r, g: $0.g, b: $0.b) }

        // Check if image is mostly grayscale
        let avgSaturation = hslPixels.reduce(0.0) { $0 + $1.s } / Double(hslPixels.count)
        let avgLightness = hslPixels.reduce(0.0) { $0 + $1.l } / Double(hslPixels.count)

        if avgSaturation < grayscaleThreshold {
            return HSLColor(h: 220, s: 5, l: avgLightness)
        }

        // Group by hue into buckets
        var buckets = [[HSLColor]](repeating: [], count: bucketCount)
        for pixel in hslPixels {
            let idx = min(Int(pixel.h / degreesPerBucket), bucketCount - 1)
            buckets[idx].append(pixel)
        }

        // Score buckets: count × (avgSaturation / 100)
        var bestIdx = 0
        var bestScore = -1.0
        for (i, bucket) in buckets.enumerated() {
            guard !bucket.isEmpty else { continue }
            let avgSat = bucket.reduce(0.0) { $0 + $1.s } / Double(bucket.count)
            let score = Double(bucket.count) * (avgSat / 100.0)
            if score > bestScore {
                bestScore = score
                bestIdx = i
            }
        }

        let bestBucket = buckets[bestIdx]
        guard !bestBucket.isEmpty else {
            return HSLColor(h: 220, s: 5, l: avgLightness)
        }

        // Weighted average using saturation as weight
        var totalWeight = 0.0
        var weightedH = 0.0
        var weightedS = 0.0
        var weightedL = 0.0

        for pixel in bestBucket {
            let w = max(pixel.s, 0.1) // avoid zero weight
            totalWeight += w
            weightedH += pixel.h * w
            weightedS += pixel.s * w
            weightedL += pixel.l * w
        }

        return HSLColor(
            h: weightedH / totalWeight,
            s: weightedS / totalWeight,
            l: weightedL / totalWeight
        )
    }

    /// Generate gradient colors from a dominant color.
    /// Returns (center, edge) CGColors for gradient stops.
    /// `saturationShift` and `lightnessShift` adjust the generated values (-50...+50).
    public static func generateGradientColors(
        dominant: HSLColor,
        saturationShift: Double = 0,
        lightnessShift: Double = 0
    ) -> (center: CGColor, edge: CGColor) {
        let isDark = dominant.l < 50

        let centerS = clamp(max(dominant.s * 0.85, 50) + saturationShift, 0, 100)
        let centerL = clamp(
            (isDark
                ? max(25, min(40, dominant.l * 0.8))
                : min(75, max(60, dominant.l * 0.9))
            ) + lightnessShift,
            0, 100
        )

        let edgeS = clamp(centerS + 15, 0, 100)
        let edgeL = clamp(
            isDark ? centerL - 20 : centerL - 25,
            0, 100
        )

        let centerColor = HSLColor(h: dominant.h, s: centerS, l: centerL)
        let edgeColor = HSLColor(h: dominant.h, s: edgeS, l: edgeL)

        return (centerColor.cgColor, edgeColor.cgColor)
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, value))
    }

    // MARK: - Pixel Sampling

    private struct RGBPixel {
        let r: Double
        let g: Double
        let b: Double
    }

    private static func samplePixels(from image: CGImage) -> [RGBPixel] {
        let w = sampleSize
        let h = sampleSize

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
            return []
        }

        // Draw image downscaled to sample size
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = ctx.data else { return [] }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(w * h)

        for i in 0..<(w * h) {
            let offset = i * 4
            let r = Double(ptr[offset])
            let g = Double(ptr[offset + 1])
            let b = Double(ptr[offset + 2])
            // Skip near-black and near-white pixels (likely background)
            if r + g + b < 30 || r + g + b > 735 { continue }
            pixels.append(RGBPixel(r: r, g: g, b: b))
        }

        return pixels
    }
}
