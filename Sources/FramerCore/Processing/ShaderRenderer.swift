import Foundation
import CoreGraphics

public enum ShaderRenderer {
    public static func apply(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        try Task.checkCancellation()

        switch params.params {
        case .ascii:
            return try ShaderASCIIRenderer.apply(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension,
                sourceImage: sourceImage
            )
        case .pixelSort:
            return try ShaderPixelSortRenderer.apply(to: image, params: params)
        case .crimewave(let shaderParams):
            return try applyCrimewave(to: image, params: shaderParams, intensity: params.intensity)
        case .narc(let shaderParams):
            return try applyNarc(to: image, params: shaderParams, intensity: params.intensity)
        case .shiba(let shaderParams):
            return try applyShiba(to: image, params: shaderParams, intensity: params.intensity)
        case .distantPast(let shaderParams):
            return try applyDistantPast(to: image, params: shaderParams, intensity: params.intensity)
        }
    }

    private static func applyCrimewave(
        to image: CGImage,
        params: CrimewaveShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)

        ShaderPrimitives.adjustContrastAndCrush(pixels, width: image.width, height: image.height, contrast: params.contrast)
        ShaderPrimitives.adjustSaturation(pixels, width: image.width, height: image.height, amount: 1.0 + params.neon * 0.8)
        ShaderPrimitives.applyChannelBias(
            pixels,
            width: image.width,
            height: image.height,
            red: params.neon * 10.0,
            green: -params.neon * 8.0,
            blue: params.neon * 22.0
        )
        ShaderPrimitives.applyBoxBlur(
            pixels,
            width: image.width,
            height: image.height,
            radius: 2,
            mixAmount: params.softness * 0.65
        )
        ShaderPrimitives.addDeterministicGrain(pixels, width: image.width, height: image.height, amount: params.grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: image.width, height: image.height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func applyNarc(
        to image: CGImage,
        params: NarcShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)

        ShaderPrimitives.adjustContrastAndCrush(
            pixels,
            width: image.width,
            height: image.height,
            contrast: params.contrast * 1.08,
            crush: min(1.0, params.crush + 0.1)
        )
        ShaderPrimitives.adjustTemperature(pixels, width: image.width, height: image.height, amount: params.temperature)
        ShaderPrimitives.adjustSaturation(pixels, width: image.width, height: image.height, amount: 1.02)
        ShaderPrimitives.addDeterministicGrain(pixels, width: image.width, height: image.height, amount: params.grain * 1.1)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: image.width, height: image.height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func applyShiba(
        to image: CGImage,
        params: ShibaShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)

        ShaderPrimitives.adjustTemperature(pixels, width: image.width, height: image.height, amount: params.warmth)
        ShaderPrimitives.adjustSaturation(pixels, width: image.width, height: image.height, amount: 1.0 + params.saturation)
        ShaderPrimitives.applyBoxBlur(
            pixels,
            width: image.width,
            height: image.height,
            radius: 1,
            mixAmount: params.softness * 0.55
        )
        ShaderPrimitives.addDeterministicGrain(pixels, width: image.width, height: image.height, amount: params.grain * 0.6)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: image.width, height: image.height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    // Reference palette from AcerolaFX_DistantPast.ini PaletteSwap colors,
    // ordered by luminance (dark → light). These are the muted watercolor
    // tones that define the "distant past" look.
    private static let distantPastPalette: [(r: Double, g: Double, b: Double)] = [
        (0.411765, 0.414072, 0.490196),  // muted lavender
        (0.537255, 0.466667, 0.466667),  // dusty mauve
        (0.582237, 0.690196, 0.407843),  // olive green
        (0.668166, 0.752941, 0.560784),  // sage green
        (0.815917, 0.835294, 0.725490),  // pale cream
        (0.921569, 0.912534, 0.912534),  // pearl white
    ]

    private static func applyDistantPast(
        to image: CGImage,
        params: DistantPastShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let paletteCount = max(2, min(distantPastPalette.count, params.paletteDepth))
        let fade = ShaderPrimitives.clamp01(params.fade)
        let softness = ShaderPrimitives.clamp01(params.softness)
        let grain = ShaderPrimitives.clamp01(params.grain)

        // Build the active palette (evenly spaced subset of the full 6 colors)
        var palette: [(r: Double, g: Double, b: Double)] = []
        if paletteCount >= distantPastPalette.count {
            palette = distantPastPalette
        } else {
            for i in 0..<paletteCount {
                let t = Double(i) / Double(paletteCount - 1)
                let idx = min(distantPastPalette.count - 1, Int((t * Double(distantPastPalette.count - 1)).rounded()))
                palette.append(distantPastPalette[idx])
            }
        }

        // Pre-compute palette luminances for nearest-match
        let paletteLum = palette.map { 0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b }

        // Step 1: Color grading (approximates the 3 ColorCorrection passes + Blend)
        // Reference CC1: exposure 4.0, contrast ~1.3, brightness ~+0.2, saturation ~0.85, temp -0.05
        // Reference CC2: heavy desaturation (sat 0.498 red channel)
        // Reference CC3: contrast ~1.17, exposure 1.156, temp +0.2
        // Net effect: boosted exposure, warm tone, reduced saturation, higher contrast

        // Exposure + contrast + brightness (controlled by fade)
        let exposureMul = 1.0 + fade * 1.5       // 1.0 → 2.5 (reference net is ~4.6)
        let contrastMul = 1.0 + fade * 0.35       // 1.0 → 1.35
        let brightnessAdd = fade * 0.12            // warm brightness offset
        let desatAmount = 1.0 - fade * 0.45        // 1.0 → 0.55

        for i in 0..<(width * height) {
            let idx = i * 4
            var r = Double(pixels[idx]) / 255.0
            var g = Double(pixels[idx + 1]) / 255.0
            var b = Double(pixels[idx + 2]) / 255.0

            // Exposure
            r *= exposureMul
            g *= exposureMul
            b *= exposureMul

            // Contrast around midpoint (reference uses 0.5 linear midpoint)
            r = contrastMul * (r - 0.5) + 0.5 + brightnessAdd * 1.2
            g = contrastMul * (g - 0.5) + 0.5 + brightnessAdd
            b = contrastMul * (b - 0.5) + 0.5 + brightnessAdd * 0.85

            // Warm temperature shift (reference: -0.05 then +0.2 net = +0.15)
            let tempShift = fade * 0.06
            r += tempShift
            b -= tempShift * 0.7

            // Desaturate (reference: selective, we approximate uniformly)
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            r = lum + (r - lum) * desatAmount
            g = lum + (g - lum) * desatAmount
            b = lum + (b - lum) * desatAmount

            // Acerola Light self-blend approximation (mode 10, strength 0.2)
            // AcerolaLight: luminance < 0.5 → 1 - (1-a)/(4*(a+0.001)) - 0.25
            //               luminance >= 0.5 → a/(4*(1-(a-0.001))) + 0.25
            // At 0.2 blend strength this gently lifts shadows and compresses highlights
            let blendStr = fade * 0.2
            func acerolaLight(_ a: Double) -> Double {
                let s = max(0.001, min(0.999, a))
                return s < 0.5
                    ? max(0, 1.0 - (1.0 - s) / (4.0 * (s + 0.001)) - 0.25)
                    : min(1, s / (4.0 * (1.0 - (s - 0.001))) + 0.25)
            }
            r = r + (acerolaLight(max(0, min(1, r))) - r) * blendStr
            g = g + (acerolaLight(max(0, min(1, g))) - g) * blendStr
            b = b + (acerolaLight(max(0, min(1, b))) - b) * blendStr

            // Filmic tonemap approximation (Hable curve)
            func hable(_ x: Double) -> Double {
                let a = 0.1, b = 0.5, c = 0.075, d = 0.2, e = 0.014, f = 0.3
                return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f
            }
            let whiteScale = 1.0 / hable(8.0)
            r = hable(max(0, r)) * whiteScale
            g = hable(max(0, g)) * whiteScale
            b = hable(max(0, b)) * whiteScale

            // Gamma (reference: 1.201)
            let gamma = 1.0 / (1.0 + fade * 0.2)
            r = pow(max(0, min(1, r)), gamma)
            g = pow(max(0, min(1, g)), gamma)
            b = pow(max(0, min(1, b)), gamma)

            pixels[idx] = ShaderPrimitives.clampByte(r * 255.0)
            pixels[idx + 1] = ShaderPrimitives.clampByte(g * 255.0)
            pixels[idx + 2] = ShaderPrimitives.clampByte(b * 255.0)
        }

        // Step 2: Palette snap — map each pixel to nearest palette color by luminance
        // (Reference maps red channel to palette index; after grading, R ≈ luminance)
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = Double(pixels[idx]) / 255.0
                let g = Double(pixels[idx + 1]) / 255.0
                let b = Double(pixels[idx + 2]) / 255.0
                let pixelLum = 0.299 * r + 0.587 * g + 0.114 * b

                // Find nearest palette entry by luminance distance
                var bestIdx = 0
                var bestDist = abs(pixelLum - paletteLum[0])
                for pi in 1..<palette.count {
                    let dist = abs(pixelLum - paletteLum[pi])
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = pi
                    }
                }

                let pc = palette[bestIdx]

                // Dither: add small noise before snapping to reduce banding
                // (Reference uses blue noise at spread 0.062)
                let noiseSeed = ((x &* 31) &+ (y &* 17) &+ ((x ^ y) &* 13)) & 255
                let noise = (Double(noiseSeed) / 255.0 - 0.5) * grain * 0.15
                let grainedR = ShaderPrimitives.clampByte((pc.r + noise) * 255.0)
                let grainedG = ShaderPrimitives.clampByte((pc.g + noise) * 255.0)
                let grainedB = ShaderPrimitives.clampByte((pc.b + noise) * 255.0)

                pixels[idx] = grainedR
                pixels[idx + 1] = grainedG
                pixels[idx + 2] = grainedB
            }
        }

        // Step 3: Vignette (reference: intensity 1.563, large roundness)
        if fade > 0 {
            let cx = Double(width) / 2.0
            let cy = Double(height) / 2.0
            let vignetteStrength = fade * 1.2
            for y in 0..<height {
                for x in 0..<width {
                    let dx = (Double(x) - cx) / cx
                    let dy = (Double(y) - cy) / cy
                    let dist = sqrt(dx * dx + dy * dy)
                    let vignette = max(0, 1.0 - dist * dist * vignetteStrength * 0.5)
                    let idx = (y * width + x) * 4
                    pixels[idx] = ShaderPrimitives.clampByte(Double(pixels[idx]) * vignette)
                    pixels[idx + 1] = ShaderPrimitives.clampByte(Double(pixels[idx + 1]) * vignette)
                    pixels[idx + 2] = ShaderPrimitives.clampByte(Double(pixels[idx + 2]) * vignette)
                }
            }
        }

        // Step 4: Softness (blur)
        ShaderPrimitives.applyBoxBlur(
            pixels,
            width: width,
            height: height,
            radius: max(1, Int((softness * 3).rounded())),
            mixAmount: softness
        )

        // Step 5: Film grain
        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)

        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func mixStylizedContext(
        _ stylizedContext: CGContext,
        with originalImage: CGImage,
        intensity: Double
    ) throws -> CGImage {
        guard let stylized = stylizedContext.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let width = originalImage.width
        let height = originalImage.height
        let originalCtx = try ShaderPrimitives.renderToRGBAContext(originalImage)
        let stylizedCtx = try ShaderPrimitives.renderToRGBAContext(stylized)
        let mixedCtx = try ShaderPrimitives.renderToRGBAContext(originalImage)
        guard
            let originalData = originalCtx.data,
            let stylizedData = stylizedCtx.data,
            let mixedData = mixedCtx.data
        else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let originalPixels = originalData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let stylizedPixels = stylizedData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let mixedPixels = mixedData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for i in 0..<(width * height) {
            let idx = i * 4
            mixedPixels[idx] = ShaderPrimitives.mix(originalPixels[idx], stylizedPixels[idx], intensity: intensity)
            mixedPixels[idx + 1] = ShaderPrimitives.mix(originalPixels[idx + 1], stylizedPixels[idx + 1], intensity: intensity)
            mixedPixels[idx + 2] = ShaderPrimitives.mix(originalPixels[idx + 2], stylizedPixels[idx + 2], intensity: intensity)
            mixedPixels[idx + 3] = originalPixels[idx + 3]
        }

        guard let result = mixedCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }
}
