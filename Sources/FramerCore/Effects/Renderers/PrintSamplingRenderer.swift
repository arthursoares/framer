import Foundation
import CoreGraphics

public enum PrintSamplingRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .printSampling(common, geometry, color, payload) = parameters else {
            return input
        }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        let bytesPerRow = width * 4
        guard let sourcePixels = EffectBitmapSupport.rasterize(input, width: width, height: height) else { return input }

        var outputPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let cellSize = max(2, Int((geometry.scale * 5.0).rounded()) + Int(geometry.spacing.rounded()))

        for y in stride(from: 0, to: height, by: cellSize) {
            for x in stride(from: 0, to: width, by: cellSize) {
                let rectWidth = min(cellSize, width - x)
                let rectHeight = min(cellSize, height - y)
                let luminance = averageLuminance(x: x, y: y, width: rectWidth, height: rectHeight, canvasWidth: width, sourcePixels: sourcePixels)
                let threshold = adjustedThreshold(base: payload.threshold, sampleDensity: payload.sampleDensity, common: common, variant: payload.variant)
                paintCell(
                    x: x,
                    y: y,
                    width: rectWidth,
                    height: rectHeight,
                    canvasWidth: width,
                    outputPixels: &outputPixels,
                    luminance: luminance,
                    threshold: threshold,
                    variant: payload.variant,
                    payload: payload,
                    colorMode: color.mode,
                    backgroundIntensity: color.backgroundIntensity,
                    effect: effect
                )
            }
        }

        return EffectBitmapSupport.makeImage(from: &outputPixels, width: width, height: height) ?? input
    }

    private static func averageLuminance(x: Int, y: Int, width: Int, height: Int, canvasWidth: Int, sourcePixels: [UInt8]) -> Double {
        var total = 0.0
        var count = 0.0
        for yy in y..<(y + height) {
            for xx in x..<(x + width) {
                let idx = (yy * canvasWidth + xx) * 4
                let r = Double(sourcePixels[idx]) / 255.0
                let g = Double(sourcePixels[idx + 1]) / 255.0
                let b = Double(sourcePixels[idx + 2]) / 255.0
                total += (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
                count += 1.0
            }
        }
        return total / max(1.0, count)
    }

    private static func adjustedThreshold(base: Double, sampleDensity: Double, common: GPUEffectCommonParameters, variant: PrintSamplingVariant) -> Double {
        let densityBias = (sampleDensity - 0.5) * 0.2
        let contrastBias = (common.contrast - 1.0) * 0.15
        let variantBias: Double
        switch variant {
        case .halftone: variantBias = -0.05
        case .crosshatch: variantBias = 0.03
        case .threshold: variantBias = 0.08
        case .dithering: variantBias = 0.0
        }
        return max(0.1, min(0.9, base + densityBias - contrastBias + variantBias))
    }

    private static func paintCell(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        canvasWidth: Int,
        outputPixels: inout [UInt8],
        luminance: Double,
        threshold: Double,
        variant: PrintSamplingVariant,
        payload: PrintSamplingParameters,
        colorMode: GPUEffectColorMode,
        backgroundIntensity: Double,
        effect: GPUEffectKind
    ) {
        let dark = luminance < threshold
        for yy in y..<(y + height) {
            for xx in x..<(x + width) {
                let idx = (yy * canvasWidth + xx) * 4
                let localX = xx - x
                let localY = yy - y
                let shouldInk: Bool
                switch variant {
                case .dithering:
                    let posX = Double(xx) + payload.modulation * 10.0
                    let posY = Double(yy) + payload.modulation * 6.0
                    let noise = ign(x: posX, y: posY)
                    let algorithmScale: Double
                    switch payload.algorithm {
                    case .bayer4x4:
                        algorithmScale = 0.65
                    case .bayer8x8:
                        algorithmScale = 0.85
                    case .floydSteinberg:
                        algorithmScale = 0.9
                    }
                    let intensityScale = max(0.15, min(2.0, payload.sampleDensity))
                    let approxThreshold = 0.5 + (noise - 0.5) * algorithmScale * intensityScale
                    shouldInk = luminance >= approxThreshold
                case .halftone:
                    let cx = Double(width) / 2.0
                    let cy = Double(height) / 2.0
                    let angle = payload.halftoneAngle * .pi / 180.0
                    let dx = Double(localX) - cx
                    let dy = Double(localY) - cy
                    let rotatedX = (dx * cos(angle)) - (dy * sin(angle))
                    let rotatedY = (dx * sin(angle)) + (dy * cos(angle))
                    let radius = sqrt(rotatedX * rotatedX + rotatedY * rotatedY)
                    let dotFactor = max(0.15, 1.0 - luminance)
                    switch payload.halftoneShape {
                    case .circle:
                        shouldInk = radius <= (Double(min(width, height)) * dotFactor) * 0.5
                    case .square:
                        shouldInk = abs(rotatedX) <= (Double(width) * dotFactor) * 0.25 && abs(rotatedY) <= (Double(height) * dotFactor) * 0.25
                    case .diamond:
                        shouldInk = (abs(rotatedX) + abs(rotatedY)) <= (Double(min(width, height)) * dotFactor) * 0.4
                    }
                case .threshold:
                    let levelCount = max(2, payload.thresholdLevels)
                    let quantized = round(luminance * Double(levelCount - 1)) / Double(levelCount - 1)
                    let ditherPhase = payload.thresholdDither ? (((localX + localY) % 2 == 0) ? -0.08 : 0.08) : 0
                    shouldInk = quantized + ditherPhase < threshold
                case .crosshatch:
                    let angle = payload.hatchAngle * .pi / 180.0
                    let density = max(1.0, payload.hatchDensity * 10.0)
                    let rotatedX = Double(localX) * cos(angle) - Double(localY) * sin(angle)
                    let rotatedY = Double(localX) * sin(angle) + Double(localY) * cos(angle)
                    let baseStep = max(1.0, Double(max(width, height)) / density)
                    let lineA = abs((rotatedX / baseStep).truncatingRemainder(dividingBy: 1.0) - 0.5) < max(0.03, payload.hatchLineWidth * 0.5)
                    let lineB = abs((rotatedY / baseStep).truncatingRemainder(dividingBy: 1.0) - 0.5) < max(0.03, payload.hatchLineWidth * 0.5)
                    let lineC = payload.hatchLayers >= 3 && abs(((rotatedX + rotatedY) / baseStep).truncatingRemainder(dividingBy: 1.0) - 0.5) < max(0.03, payload.hatchLineWidth * 0.5)
                    let noiseToggle = payload.hatchRandomness > 0 && sin(Double((localX + localY) * 13)) > (1.0 - payload.hatchRandomness)
                    shouldInk = dark && (lineA || lineB || lineC || noiseToggle)
                }

                let finalInk = payload.invert ? !shouldInk : shouldInk

                let base = pixelColor(
                    shouldInk: finalInk,
                    colorMode: colorMode,
                    backgroundIntensity: backgroundIntensity,
                    effect: effect,
                    foreground: payload.foreground,
                    background: payload.background
                )
                outputPixels[idx] = base.0
                outputPixels[idx + 1] = base.1
                outputPixels[idx + 2] = base.2
                outputPixels[idx + 3] = 255
            }
        }
    }

    private static func ign(x: Double, y: Double) -> Double {
        let dot = x * 0.06711056 + y * 0.00583715
        let fract1 = dot - floor(dot)
        let value = 52.9829189 * fract1
        return value - floor(value)
    }

    private static func pixelColor(
        shouldInk: Bool,
        colorMode: GPUEffectColorMode,
        backgroundIntensity: Double,
        effect: GPUEffectKind,
        foreground: CodableColor?,
        background: CodableColor?
    ) -> (UInt8, UInt8, UInt8) {
        let backgroundRGB: (UInt8, UInt8, UInt8) = {
            if let background {
                let c = background.cgColor.components ?? [0, 0, 0, 1]
                return (UInt8((c[0] * 255).rounded()), UInt8((c[1] * 255).rounded()), UInt8((c[2] * 255).rounded()))
            }
            let value = UInt8(max(0, min(255, Int((backgroundIntensity * 255.0).rounded()))))
            return (value, value, value)
        }()
        guard shouldInk else { return backgroundRGB }

        if let foreground {
            let c = foreground.cgColor.components ?? [1, 1, 1, 1]
            return (UInt8((c[0] * 255).rounded()), UInt8((c[1] * 255).rounded()), UInt8((c[2] * 255).rounded()))
        }

        switch (colorMode, effect) {
        case (.source, .halftone):
            return (255, 210, 140)
        case (.foregroundBackground, .crosshatch):
            return (210, 210, 210)
        default:
            return (255, 255, 255)
        }
    }
}
