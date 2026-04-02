import Foundation
import CoreGraphics

enum ShaderPrimitives {
    @inline(__always)
    static func clamp01(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    @inline(__always)
    static func mix(_ original: UInt8, _ effect: UInt8, intensity: Double) -> UInt8 {
        let t = clamp01(intensity)
        let blended = Double(original) * (1.0 - t) + Double(effect) * t
        return UInt8(max(0, min(255, blended.rounded())))
    }

    @inline(__always)
    static func reducePaletteComponent(_ value: UInt8, levels: Int) -> UInt8 {
        let clampedLevels = max(2, min(32, levels))
        let stepCount = Double(clampedLevels - 1)
        let normalized = Double(value) / 255.0
        let bucket = (normalized * stepCount).rounded()
        let reduced = bucket / stepCount
        return UInt8(max(0, min(255, (reduced * 255.0).rounded())))
    }

    @inline(__always)
    static func clampByte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, Int(value.rounded()))))
    }

    @inline(__always)
    static func luminance(r: UInt8, g: UInt8, b: UInt8) -> Double {
        (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0
    }

    static func makeRGBAContext(width: Int, height: Int) throws -> CGContext {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return ctx
    }

    static func renderToRGBAContext(_ image: CGImage) throws -> CGContext {
        let ctx = try makeRGBAContext(width: image.width, height: image.height)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx
    }

    static func applyBoxBlur(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        radius: Int,
        mixAmount: Double
    ) {
        let amount = clamp01(mixAmount)
        let blurRadius = max(0, min(3, radius))
        guard amount > 0, blurRadius > 0 else { return }

        let count = width * height * 4
        let source = Array(UnsafeBufferPointer(start: pixels, count: count))

        for y in 0..<height {
            for x in 0..<width {
                var sumR = 0.0
                var sumG = 0.0
                var sumB = 0.0
                var samples = 0.0
                for ky in max(0, y - blurRadius)...min(height - 1, y + blurRadius) {
                    for kx in max(0, x - blurRadius)...min(width - 1, x + blurRadius) {
                        let idx = (ky * width + kx) * 4
                        sumR += Double(source[idx])
                        sumG += Double(source[idx + 1])
                        sumB += Double(source[idx + 2])
                        samples += 1.0
                    }
                }

                let idx = (y * width + x) * 4
                let blurredR = clampByte(sumR / samples)
                let blurredG = clampByte(sumG / samples)
                let blurredB = clampByte(sumB / samples)
                pixels[idx] = mix(pixels[idx], blurredR, intensity: amount)
                pixels[idx + 1] = mix(pixels[idx + 1], blurredG, intensity: amount)
                pixels[idx + 2] = mix(pixels[idx + 2], blurredB, intensity: amount)
            }
        }
    }

    static func addDeterministicGrain(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        amount: Double
    ) {
        let grain = clamp01(amount)
        guard grain > 0 else { return }

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let seed = ((x &* 29) &+ (y &* 31) &+ ((x ^ y) &* 17)) & 255
                let centered = (Double(seed) / 255.0) - 0.5
                let delta = centered * 42.0 * grain
                pixels[idx] = clampByte(Double(pixels[idx]) + delta)
                pixels[idx + 1] = clampByte(Double(pixels[idx + 1]) + delta)
                pixels[idx + 2] = clampByte(Double(pixels[idx + 2]) + delta)
            }
        }
    }

    static func adjustContrastAndCrush(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        contrast: Double,
        crush: Double = 0
    ) {
        let contrastAmount = max(0.0, contrast)
        let crushAmount = clamp01(crush)

        for i in 0..<(width * height) {
            let idx = i * 4
            for channel in 0...2 {
                var value = Double(pixels[idx + channel]) / 255.0
                value = ((value - 0.5) * contrastAmount) + 0.5
                if crushAmount > 0 {
                    value = pow(max(0.0, value), 1.0 + crushAmount * 1.8)
                }
                pixels[idx + channel] = clampByte(clamp01(value) * 255.0)
            }
        }
    }

    static func adjustSaturation(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        amount: Double
    ) {
        for i in 0..<(width * height) {
            let idx = i * 4
            let r = Double(pixels[idx])
            let g = Double(pixels[idx + 1])
            let b = Double(pixels[idx + 2])
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            pixels[idx] = clampByte(luma + (r - luma) * amount)
            pixels[idx + 1] = clampByte(luma + (g - luma) * amount)
            pixels[idx + 2] = clampByte(luma + (b - luma) * amount)
        }
    }

    static func adjustTemperature(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        amount: Double
    ) {
        for i in 0..<(width * height) {
            let idx = i * 4
            let shift = amount * 48.0
            pixels[idx] = clampByte(Double(pixels[idx]) + shift)
            pixels[idx + 1] = clampByte(Double(pixels[idx + 1]) + shift * 0.12)
            pixels[idx + 2] = clampByte(Double(pixels[idx + 2]) - shift * 0.85)
        }
    }

    static func applyChannelBias(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        red: Double,
        green: Double,
        blue: Double
    ) {
        for i in 0..<(width * height) {
            let idx = i * 4
            pixels[idx] = clampByte(Double(pixels[idx]) + red)
            pixels[idx + 1] = clampByte(Double(pixels[idx + 1]) + green)
            pixels[idx + 2] = clampByte(Double(pixels[idx + 2]) + blue)
        }
    }

    static func applyFadeTowardLuminance(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        amount: Double
    ) {
        let fade = clamp01(amount)
        guard fade > 0 else { return }

        for i in 0..<(width * height) {
            let idx = i * 4
            let r = pixels[idx]
            let g = pixels[idx + 1]
            let b = pixels[idx + 2]
            let lum = clampByte((luminance(r: r, g: g, b: b)) * 255.0)
            pixels[idx] = mix(r, lum, intensity: fade)
            pixels[idx + 1] = mix(g, lum, intensity: fade)
            pixels[idx + 2] = mix(b, lum, intensity: fade)
        }
    }

    static func adjustColor(_ color: CodableColor, saturationShift: Double, lightnessShift: Double) -> CodableColor {
        let r = color.red
        let g = color.green
        let b = color.blue
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        var h = 0.0
        var s = 0.0
        var l = (maxC + minC) / 2

        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
            if maxC == r {
                h = (g - b) / d + (g < b ? 6 : 0)
            } else if maxC == g {
                h = (b - r) / d + 2
            } else {
                h = (r - g) / d + 4
            }
            h /= 6
        }

        s = max(0, min(1, s + saturationShift / 100))
        l = max(0, min(1, l + lightnessShift / 100))

        func hue2rgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let nr = s == 0 ? l : hue2rgb(p, q, h + 1 / 3)
        let ng = s == 0 ? l : hue2rgb(p, q, h)
        let nb = s == 0 ? l : hue2rgb(p, q, h - 1 / 3)
        let hex = String(format: "#%02X%02X%02X", Int(nr * 255), Int(ng * 255), Int(nb * 255))
        return (try? CodableColor(hex: hex)) ?? color
    }

    static func enforcePremultipliedAlpha(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int
    ) {
        for i in 0..<(width * height) {
            let idx = i * 4
            let alpha = pixels[idx + 3]
            pixels[idx] = min(pixels[idx], alpha)
            pixels[idx + 1] = min(pixels[idx + 1], alpha)
            pixels[idx + 2] = min(pixels[idx + 2], alpha)
        }
    }
}
