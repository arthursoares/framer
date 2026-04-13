import Foundation
import CoreGraphics

public enum GlitchRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .glitch(common, geometry, color, payload) = parameters else {
            return input
        }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        let bytesPerRow = width * 4
        guard let sourcePixels = EffectBitmapSupport.rasterize(input, width: width, height: height) else { return input }

        var outputPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let span = max(1, Int((geometry.scale * 8.0 + geometry.spacing * 2.0).rounded()))

        if payload.variant == .pixelSort {
            if payload.direction == .horizontal {
                for y in 0..<height {
                    applyPixelSortRow(
                        y: y,
                        width: width,
                        sourcePixels: sourcePixels,
                        outputPixels: &outputPixels,
                        span: span,
                        payload: payload
                    )
                }
            } else {
                for x in 0..<width {
                    applyPixelSortColumn(
                        x: x,
                        width: width,
                        height: height,
                        sourcePixels: sourcePixels,
                        outputPixels: &outputPixels,
                        span: span,
                        payload: payload
                    )
                }
            }
        } else {
            for y in 0..<height {
                let rowShift = rowOffset(y: y, span: span, amount: payload.amount + payload.distortion, threshold: payload.threshold + payload.trackingError, variant: payload.variant)
                for x in 0..<width {
                    let sourceX = min(width - 1, max(0, x + rowShift))
                    let sourceIndex = (y * width + sourceX) * 4
                    let outputIndex = (y * width + x) * 4

                    switch payload.variant {
                    case .pixelSort:
                        break
                    case .vhs:
                        let bleedOffset = max(1, Int((payload.colorBleed * 4.0).rounded()))
                        let redX = min(width - 1, max(0, sourceX + bleedOffset))
                        let blueX = min(width - 1, max(0, sourceX - bleedOffset))
                        let redIndex = (y * width + redX) * 4
                        let blueIndex = (y * width + blueX) * 4
                        outputPixels[outputIndex] = sourcePixels[redIndex]
                        outputPixels[outputIndex + 1] = sourcePixels[sourceIndex + 1]
                        outputPixels[outputIndex + 2] = sourcePixels[blueIndex + 2]
                    }

                    let alpha = sourcePixels[sourceIndex + 3]
                    outputPixels[outputIndex + 3] = alpha
                }
                if payload.variant == .vhs && y % max(2, Int(max(1.0, payload.scanlines * Double(span)))) == 0 {
                    applyScanline(to: &outputPixels, row: y, width: width, colorMode: color.mode, backgroundIntensity: color.backgroundIntensity, common: common, effect: effect)
                }
            }
        }

        return EffectBitmapSupport.makeImage(from: &outputPixels, width: width, height: height) ?? input
    }

    private static func rowOffset(y: Int, span: Int, amount: Double, threshold: Double, variant: GlitchVariant) -> Int {
        let wave = sin(Double(y) / Double(max(1, span)))
        let magnitude = Int((wave * amount * Double(span) * (1.0 + threshold)).rounded())
        switch variant {
        case .pixelSort:
            return magnitude
        case .vhs:
            return magnitude / 2
        }
    }

    private static func applyPixelSortColumn(
        x: Int,
        width: Int,
        height: Int,
        sourcePixels: [UInt8],
        outputPixels: inout [UInt8],
        span: Int,
        payload: GlitchParameters
    ) {
        let step = max(1, Int((payload.streakLength * Double(span)).rounded()))
        for start in stride(from: 0, to: height, by: step) {
            let end = min(height, start + step)
            applyPixelSortSegment(
                positions: Array(start..<end),
                sourcePixels: sourcePixels,
                outputPixels: &outputPixels,
                offsetForPosition: { position in (position * width + x) * 4 },
                payload: payload,
                seedBase: x * 37 + start
            )
        }
    }

    private static func applyPixelSortRow(
        y: Int,
        width: Int,
        sourcePixels: [UInt8],
        outputPixels: inout [UInt8],
        span: Int,
        payload: GlitchParameters
    ) {
        let rowStart = y * width * 4
        let step = max(1, Int((payload.streakLength * Double(span)).rounded()))
        for start in stride(from: 0, to: width, by: step) {
            let end = min(width, start + step)
            applyPixelSortSegment(
                positions: Array(start..<end),
                sourcePixels: sourcePixels,
                outputPixels: &outputPixels,
                offsetForPosition: { position in rowStart + position * 4 },
                payload: payload,
                seedBase: y * 31 + start
            )
        }
    }

    private static func applyPixelSortSegment(
        positions: [Int],
        sourcePixels: [UInt8],
        outputPixels: inout [UInt8],
        offsetForPosition: (Int) -> Int,
        payload: GlitchParameters,
        seedBase: Int
    ) {
        let scored = positions.map { position -> (position: Int, score: Double) in
            let offset = offsetForPosition(position)
            return (position, pixelScore(at: offset, in: sourcePixels, mode: payload.sortMode))
        }

        let active = scored.filter { $0.score >= payload.threshold }
        let inactive = Set(scored.filter { $0.score < payload.threshold }.map(\.position))
        let sortedActive = active.sorted { lhs, rhs in
            payload.reverse ? lhs.score > rhs.score : lhs.score < rhs.score
        }.map(\.position)

        for (index, position) in positions.enumerated() {
            let outputIndex = offsetForPosition(position)
            let sourcePosition: Int

            if inactive.contains(position) || sortedActive.isEmpty {
                sourcePosition = position
            } else {
                let normalized = Double(index) / Double(max(1, positions.count - 1))
                let baseIndex = Int((normalized * Double(sortedActive.count - 1) * max(0.2, payload.amount)).rounded())
                let jitter = Int((sin(Double(seedBase + index * 17)) * payload.randomness * Double(sortedActive.count)).rounded())
                let clamped = min(sortedActive.count - 1, max(0, baseIndex + jitter))
                sourcePosition = sortedActive[clamped]
            }

            let sourceIndex = offsetForPosition(sourcePosition)
            outputPixels[outputIndex] = sourcePixels[sourceIndex]
            outputPixels[outputIndex + 1] = sourcePixels[sourceIndex + 1]
            outputPixels[outputIndex + 2] = sourcePixels[sourceIndex + 2]
            outputPixels[outputIndex + 3] = sourcePixels[sourceIndex + 3]
        }
    }

    private static func pixelScore(at index: Int, in pixels: [UInt8], mode: PixelSortMode) -> Double {
        let r = Double(pixels[index]) / 255.0
        let g = Double(pixels[index + 1]) / 255.0
        let b = Double(pixels[index + 2]) / 255.0
        switch mode {
        case .brightness, .luminance:
            return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        case .hue:
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let delta = maxValue - minValue
            guard delta > 0 else { return 0 }
            if maxValue == r { return ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            if maxValue == g { return ((b - r) / delta) + 2 }
            return ((r - g) / delta) + 4
        }
    }

    private static func applyScanline(
        to outputPixels: inout [UInt8],
        row: Int,
        width: Int,
        colorMode: GPUEffectColorMode,
        backgroundIntensity: Double,
        common: GPUEffectCommonParameters,
        effect: GPUEffectKind
    ) {
        let attenuation = max(0.4, min(0.95, 0.75 - common.brightness * 0.2))
        let tint = UInt8(max(0, min(255, Int((backgroundIntensity * 255.0).rounded()))))
        for x in 0..<width {
            let idx = (row * width + x) * 4
            outputPixels[idx] = UInt8(Double(outputPixels[idx]) * attenuation)
            outputPixels[idx + 1] = UInt8(Double(outputPixels[idx + 1]) * attenuation)
            switch (colorMode, effect) {
            case (.foregroundBackground, .vhs):
                outputPixels[idx + 2] = max(tint, UInt8(Double(outputPixels[idx + 2]) * attenuation))
            default:
                outputPixels[idx + 2] = UInt8(Double(outputPixels[idx + 2]) * attenuation)
            }
        }
    }
}
