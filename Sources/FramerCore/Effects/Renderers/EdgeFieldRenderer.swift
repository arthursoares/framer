import Foundation
import CoreGraphics

public enum EdgeFieldRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .edgeField(common, geometry, color, payload) = parameters else {
            return input
        }

        // GPU fast path — see Effects/Metal/EdgeField.metal. Falls back to
        // the CPU pixel loop below on any MetalEffectError.
        switch effect {
        case .edgeDetection:
            do {
                return try EdgeFieldGPURenderer.renderEdgeDetection(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        case .contour:
            do {
                return try EdgeFieldGPURenderer.renderContour(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        case .waveLines:
            do {
                return try EdgeFieldGPURenderer.renderWaveLines(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        case .voronoi:
            do {
                return try EdgeFieldGPURenderer.renderVoronoi(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        case .noiseField:
            do {
                return try EdgeFieldGPURenderer.renderNoiseField(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        default:
            break
        }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        let bytesPerRow = width * 4
        guard let sourcePixels = EffectBitmapSupport.rasterize(input, width: width, height: height) else { return input }

        var outputPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let spacing = max(1, Int((geometry.spacing + geometry.scale * 2.0).rounded()))

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let intensity = luminance(atX: x, y: y, width: width, sourcePixels: sourcePixels)
                let edge = edgeMagnitude(atX: x, y: y, width: width, height: height, sourcePixels: sourcePixels)
                let v = variantValue(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    intensity: intensity,
                    edge: edge,
                    spacing: spacing,
                    variant: payload.variant,
                    common: common,
                    fieldIntensity: payload.fieldIntensity,
                    lineStrength: payload.lineStrength,
                    lineCount: payload.lineCount,
                    amplitude: payload.amplitude,
                    frequency: payload.frequency,
                    thickness: payload.thickness,
                    direction: payload.direction,
                    animate: payload.animate,
                    noiseType: payload.noiseType,
                    octaves: payload.octaves,
                    speed: payload.speed,
                    distortOnly: payload.distortOnly,
                    edgeAlgorithm: payload.edgeAlgorithm,
                    edgeThreshold: payload.edgeThreshold,
                    invert: payload.invert,
                    contourFillMode: payload.contourFillMode,
                    contourLevels: payload.contourLevels,
                    cellSize: payload.cellSize,
                    edgeWidth: payload.edgeWidth,
                    randomize: payload.randomize,
                    effect: effect
                )
                let rgb = colorize(v, colorMode: color.mode, backgroundIntensity: color.backgroundIntensity, variant: payload.variant)
                outputPixels[idx] = rgb.0
                outputPixels[idx + 1] = rgb.1
                outputPixels[idx + 2] = rgb.2
                outputPixels[idx + 3] = 255
            }
        }

        return EffectBitmapSupport.makeImage(from: &outputPixels, width: width, height: height) ?? input
    }

    private static func luminance(atX x: Int, y: Int, width: Int, sourcePixels: [UInt8]) -> Double {
        let idx = (y * width + x) * 4
        let r = Double(sourcePixels[idx]) / 255.0
        let g = Double(sourcePixels[idx + 1]) / 255.0
        let b = Double(sourcePixels[idx + 2]) / 255.0
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }

    private static func edgeMagnitude(atX x: Int, y: Int, width: Int, height: Int, sourcePixels: [UInt8]) -> Double {
        let left = luminance(atX: max(0, x - 1), y: y, width: width, sourcePixels: sourcePixels)
        let right = luminance(atX: min(width - 1, x + 1), y: y, width: width, sourcePixels: sourcePixels)
        let up = luminance(atX: x, y: max(0, y - 1), width: width, sourcePixels: sourcePixels)
        let down = luminance(atX: x, y: min(height - 1, y + 1), width: width, sourcePixels: sourcePixels)
        return min(1.0, abs(right - left) + abs(down - up))
    }

    private static func variantValue(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        intensity: Double,
        edge: Double,
        spacing: Int,
        variant: EdgeFieldVariant,
        common: GPUEffectCommonParameters,
        fieldIntensity: Double,
        lineStrength: Double,
        lineCount: Double,
        amplitude: Double,
        frequency: Double,
        thickness: Double,
        direction: EdgeFieldDirection,
        animate: Bool,
        noiseType: NoiseFieldType,
        octaves: Int,
        speed: Double,
        distortOnly: Bool,
        edgeAlgorithm: EdgeAlgorithm,
        edgeThreshold: Double,
        invert: Bool,
        contourFillMode: ContourFillMode,
        contourLevels: Int,
        cellSize: Double,
        edgeWidth: Double,
        randomize: Bool,
        effect: GPUEffectKind
    ) -> Double {
        let field = fieldIntensity * (1.0 + common.contrast * 0.25)
        switch variant {
        case .contour:
            let levels = max(2, contourLevels)
            let quantized = floor(intensity * Double(levels)) / Double(levels)
            let band = fmod(quantized * field * Double(levels), 1.0)
            switch contourFillMode {
            case .linesOnly:
                let line = band < max(0.04, lineStrength * thickness * 0.4)
                let value = line ? 1.0 : (invert ? 1.0 - intensity : intensity * 0.15)
                return max(0.0, min(1.0, value))
            case .filledBands:
                let line = band < max(0.04, lineStrength * thickness * 0.25)
                let bandValue = invert ? (1.0 - quantized) : quantized
                let lineValue = min(1.0, bandValue + lineStrength * 0.18)
                return max(0.0, min(1.0, line ? lineValue : bandValue))
            }
        case .edgeDetection:
            let algorithmMultiplier: Double
            switch edgeAlgorithm {
            case .sobel: algorithmMultiplier = 1.0
            case .laplacian: algorithmMultiplier = 1.35
            }
            let thresholded = max(0.0, edge * algorithmMultiplier - edgeThreshold)
            let shaped = thresholded * max(0.5, lineStrength / max(0.05, thickness))
            let final = invert ? (1.0 - min(1.0, shaped)) : min(1.0, shaped)
            return final
        case .waveLines:
            let lineFrequency = max(0.1, variant == .waveLines ? payloadFrequencyBoost(field: field, spacing: spacing, common: common, lineCount: lineCount, frequency: frequency) : 1.0)
            let axis = direction == .vertical ? Double(x) : Double(y)
            let phase = (axis / Double(max(1, spacing))) * lineFrequency
            let wave = sin(phase + intensity * .pi * max(0.1, amplitude))
            let threshold = max(0.03, thickness * max(0.1, lineStrength))
            return abs(wave) < threshold ? 1.0 : intensity * 0.15
        case .voronoi:
            let cellSpacing = max(2, Int(cellSize.rounded()))
            let jitter = randomize ? Int((sin(Double((x + y) * 17)) * Double(cellSpacing) * 0.35).rounded()) : 0
            let cellX = ((x + jitter) / max(1, cellSpacing)) * max(1, cellSpacing)
            let cellY = ((y - jitter) / max(1, cellSpacing)) * max(1, cellSpacing)
            let dx = Double(x - cellX)
            let dy = Double(y - cellY)
            let dist = sqrt(dx * dx + dy * dy) / Double(max(1, cellSpacing))
            let edgeMask = max(0.0, 1.0 - abs(dist - 0.5) / max(0.05, edgeWidth))
            return max(0.0, min(1.0, edgeMask * lineStrength + (1.0 - dist) * field * 0.6))
        case .noiseField:
            let baseScale = max(1.0, amplitude * 120.0)
            let axis = direction == .vertical ? Double(x) : Double(y)
            let position = axis / baseScale
            let animatedOffset = animate ? frequency * speed * 10.0 : 0.0

            let accumulated = (0..<max(1, octaves)).reduce(0.0) { partial, octave in
                let octaveScale = pow(2.0, Double(octave))
                let sample = noiseValue(
                    x: x,
                    y: y,
                    axisPosition: position,
                    octaveScale: octaveScale,
                    frequency: frequency,
                    animatedOffset: animatedOffset,
                    noiseType: noiseType
                )
                return partial + sample / octaveScale
            }

            if distortOnly {
                return max(0.0, min(1.0, edge * lineStrength + accumulated * 0.35))
            }

            return max(0.0, min(1.0, accumulated * field + edge * lineStrength * 0.5))
        }
    }

    private static func colorize(_ value: Double, colorMode: GPUEffectColorMode, backgroundIntensity: Double, variant: EdgeFieldVariant) -> (UInt8, UInt8, UInt8) {
        let base = UInt8(max(0, min(255, Int((backgroundIntensity * 255.0).rounded()))))
        let ink = UInt8(max(0, min(255, Int((value * 255.0).rounded()))))
        switch (colorMode, variant) {
        case (.palette, .waveLines):
            return (ink, UInt8(Double(ink) * 0.7), 255)
        case (.foregroundBackground, .edgeDetection):
            return (ink, ink, base)
        case (.source, .voronoi):
            return (UInt8(Double(ink) * 0.6), ink, UInt8(Double(ink) * 0.85))
        default:
            return (max(base, ink), max(base, ink), max(base, ink))
        }
    }

    private static func payloadFrequencyBoost(
        field: Double,
        spacing: Int,
        common: GPUEffectCommonParameters,
        lineCount: Double,
        frequency: Double
    ) -> Double {
        let countFactor = max(1.0, lineCount / Double(max(1, spacing)))
        return max(0.2, frequency * countFactor * (1.0 + common.contrast * 0.2) * max(0.2, field))
    }

    private static func noiseValue(
        x: Int,
        y: Int,
        axisPosition: Double,
        octaveScale: Double,
        frequency: Double,
        animatedOffset: Double,
        noiseType: NoiseFieldType
    ) -> Double {
        switch noiseType {
        case .value:
            return abs(sin((Double(x) + animatedOffset) / octaveScale * frequency) * cos((Double(y) + animatedOffset) / octaveScale * frequency))
        case .simplex:
            return abs(sin((axisPosition + animatedOffset) * frequency * octaveScale + Double(x ^ y) * 0.01))
        case .cellular:
            let cell = floor((Double(x) + animatedOffset) / max(1.0, octaveScale * 8.0)) + floor((Double(y) + animatedOffset) / max(1.0, octaveScale * 8.0))
            return abs(sin(cell * frequency))
        }
    }
}
