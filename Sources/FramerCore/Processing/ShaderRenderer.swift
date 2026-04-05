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
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Boost contrast strongly
        ShaderPrimitives.adjustContrastAndCrush(pixels, width: width, height: height, contrast: params.contrast * 1.3)

        // Push neon: saturate then heavy channel bias toward cyan/magenta
        ShaderPrimitives.adjustSaturation(pixels, width: width, height: height, amount: 1.0 + params.neon * 1.6)
        ShaderPrimitives.applyChannelBias(
            pixels, width: width, height: height,
            red: params.neon * 20.0,
            green: -params.neon * 15.0,
            blue: params.neon * 40.0
        )

        // Softness
        if params.softness > 0 {
            ShaderPrimitives.applyBoxBlur(
                pixels, width: width, height: height,
                radius: max(1, Int((params.softness * 3).rounded())),
                mixAmount: params.softness * 0.8
            )
        }

        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: params.grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func applyNarc(
        to image: CGImage,
        params: NarcShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Strong contrast and crush for gritty look
        ShaderPrimitives.adjustContrastAndCrush(
            pixels, width: width, height: height,
            contrast: params.contrast * 1.4,
            crush: min(1.0, params.crush * 1.5 + 0.15)
        )

        // Temperature shift
        ShaderPrimitives.adjustTemperature(pixels, width: width, height: height, amount: params.temperature * 1.5)

        // Slight desaturation for washed-out look
        ShaderPrimitives.adjustSaturation(pixels, width: width, height: height, amount: 0.85)

        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: params.grain * 1.5)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func applyShiba(
        to image: CGImage,
        params: ShibaShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Warm temperature shift — more pronounced
        ShaderPrimitives.adjustTemperature(pixels, width: width, height: height, amount: params.warmth * 1.8)

        // Strong saturation boost
        ShaderPrimitives.adjustSaturation(pixels, width: width, height: height, amount: 1.0 + params.saturation * 1.5)

        // Softness
        if params.softness > 0 {
            ShaderPrimitives.applyBoxBlur(
                pixels, width: width, height: height,
                radius: max(1, Int((params.softness * 3).rounded())),
                mixAmount: params.softness * 0.7
            )
        }

        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: params.grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)
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

        // Step 1: Gentle color grading — warm desaturation with slight exposure lift.
        // Keep values moderate so the palette snap produces visible tonal separation.
        let warmShift = fade * 0.04
        let desatAmount = 1.0 - fade * 0.35

        for i in 0..<(width * height) {
            let idx = i * 4
            var r = Double(pixels[idx]) / 255.0
            var g = Double(pixels[idx + 1]) / 255.0
            var b = Double(pixels[idx + 2]) / 255.0

            // Warm shift
            r += warmShift
            b -= warmShift * 0.6

            // Desaturate toward luminance
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            r = lum + (r - lum) * desatAmount
            g = lum + (g - lum) * desatAmount
            b = lum + (b - lum) * desatAmount

            pixels[idx] = ShaderPrimitives.clampByte(max(0, min(1, r)) * 255.0)
            pixels[idx + 1] = ShaderPrimitives.clampByte(max(0, min(1, g)) * 255.0)
            pixels[idx + 2] = ShaderPrimitives.clampByte(max(0, min(1, b)) * 255.0)
        }

        // Step 2: Palette snap — map each pixel to the nearest palette color
        // using Euclidean distance in RGB (not just luminance). This preserves
        // the hue variation between palette entries instead of collapsing to bands.
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = Double(pixels[idx]) / 255.0
                let g = Double(pixels[idx + 1]) / 255.0
                let b = Double(pixels[idx + 2]) / 255.0

                // Add dither noise before snapping to reduce banding
                let noiseSeed = ((x &* 31) &+ (y &* 17) &+ ((x ^ y) &* 13)) & 255
                let noise = (Double(noiseSeed) / 255.0 - 0.5) * 0.06
                let nr = r + noise
                let ng = g + noise
                let nb = b + noise

                var bestIdx = 0
                var bestDist = Double.greatestFiniteMagnitude
                for pi in 0..<palette.count {
                    let pc = palette[pi]
                    let dr = nr - pc.r
                    let dg = ng - pc.g
                    let db = nb - pc.b
                    let dist = dr * dr + dg * dg + db * db
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = pi
                    }
                }

                let pc = palette[bestIdx]
                pixels[idx] = ShaderPrimitives.clampByte(pc.r * 255.0)
                pixels[idx + 1] = ShaderPrimitives.clampByte(pc.g * 255.0)
                pixels[idx + 2] = ShaderPrimitives.clampByte(pc.b * 255.0)
            }
        }

        // Step 3: Vignette
        if fade > 0.05 {
            let cx = Double(width) / 2.0
            let cy = Double(height) / 2.0
            let vigStr = fade * 0.8
            for y in 0..<height {
                for x in 0..<width {
                    let dx = (Double(x) - cx) / cx
                    let dy = (Double(y) - cy) / cy
                    let dist = dx * dx + dy * dy
                    let vignette = max(0, 1.0 - dist * vigStr * 0.4)
                    let idx = (y * width + x) * 4
                    pixels[idx] = ShaderPrimitives.clampByte(Double(pixels[idx]) * vignette)
                    pixels[idx + 1] = ShaderPrimitives.clampByte(Double(pixels[idx + 1]) * vignette)
                    pixels[idx + 2] = ShaderPrimitives.clampByte(Double(pixels[idx + 2]) * vignette)
                }
            }
        }

        // Step 4: Softness (blur)
        if softness > 0 {
            ShaderPrimitives.applyBoxBlur(
                pixels,
                width: width,
                height: height,
                radius: max(1, Int((softness * 3).rounded())),
                mixAmount: softness * 0.7
            )
        }

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
