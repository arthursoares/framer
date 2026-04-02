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
        let levels = max(2, params.paletteDepth)
        let fade = ShaderPrimitives.clamp01(params.fade)
        let softness = ShaderPrimitives.clamp01(params.softness)
        let grain = ShaderPrimitives.clamp01(params.grain)

        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let originalR = pixels[idx]
                let originalG = pixels[idx + 1]
                let originalB = pixels[idx + 2]
                let originalA = pixels[idx + 3]

                let reducedR = ShaderPrimitives.reducePaletteComponent(originalR, levels: levels)
                let reducedG = ShaderPrimitives.reducePaletteComponent(originalG, levels: levels)
                let reducedB = ShaderPrimitives.reducePaletteComponent(originalB, levels: levels)

                let monochromeValue = 0.299 * Double(reducedR)
                    + 0.587 * Double(reducedG)
                    + 0.114 * Double(reducedB)
                let monochrome = UInt8(max(0, min(255, Int(monochromeValue.rounded()))))

                let softenedR = ShaderPrimitives.mix(reducedR, monochrome, intensity: fade * softness)
                let softenedG = ShaderPrimitives.mix(reducedG, monochrome, intensity: fade * softness)
                let softenedB = ShaderPrimitives.mix(reducedB, monochrome, intensity: fade * softness)

                let noiseSeed = ((x &* 31) &+ (y &* 17)) & 255
                let grainOffset = Int(Double(noiseSeed) / 255.0 * 18.0 * grain) - Int(9.0 * grain)
                let grainedR = UInt8(max(0, min(255, Int(softenedR) + grainOffset)))
                let grainedG = UInt8(max(0, min(255, Int(softenedG) + grainOffset)))
                let grainedB = UInt8(max(0, min(255, Int(softenedB) + grainOffset)))

                pixels[idx] = grainedR
                pixels[idx + 1] = grainedG
                pixels[idx + 2] = grainedB
                pixels[idx + 3] = originalA
            }
        }

        ShaderPrimitives.applyFadeTowardLuminance(
            pixels,
            width: width,
            height: height,
            amount: min(1.0, fade * 0.8 + softness * 0.2)
        )
        ShaderPrimitives.applyBoxBlur(
            pixels,
            width: width,
            height: height,
            radius: 3,
            mixAmount: min(1.0, 0.5 + softness * 0.95 + fade * 0.4)
        )
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
