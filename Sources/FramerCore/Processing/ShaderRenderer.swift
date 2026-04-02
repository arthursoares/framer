import Foundation
import CoreGraphics

public enum ShaderRenderer {
    public static func apply(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil
    ) throws -> CGImage {
        try Task.checkCancellation()

        switch params.params {
        case .ascii:
            return try ShaderASCIIRenderer.apply(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension
            )
        case .pixelSort:
            return try ShaderPixelSortRenderer.apply(to: image, params: params)
        case .distantPast(let shaderParams):
            return try applyDistantPast(to: image, params: shaderParams, intensity: params.intensity)
        case .crimewave, .narc, .shiba:
            return image
        }
    }

    private static func applyDistantPast(
        to image: CGImage,
        params: DistantPastShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

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
                let grainOffset = Int(Double(noiseSeed) / 255.0 * 32.0 * grain) - Int(16.0 * grain)
                let grainedR = UInt8(max(0, min(255, Int(softenedR) + grainOffset)))
                let grainedG = UInt8(max(0, min(255, Int(softenedG) + grainOffset)))
                let grainedB = UInt8(max(0, min(255, Int(softenedB) + grainOffset)))

                pixels[idx] = ShaderPrimitives.mix(originalR, grainedR, intensity: intensity)
                pixels[idx + 1] = ShaderPrimitives.mix(originalG, grainedG, intensity: intensity)
                pixels[idx + 2] = ShaderPrimitives.mix(originalB, grainedB, intensity: intensity)
                pixels[idx + 3] = originalA
            }
        }

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        return result
    }
}
