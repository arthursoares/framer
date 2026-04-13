// Bucket-system CPU dispatcher for the TextCell family.
// The cloud agent's TextCellRenderer (in this same directory) handles the GPU
// ASCII path via `.shader` layers. This enum handles the 4-variant bucket
// dispatch from GPUEffectsPlatform for `.gpuEffect` layers. Coexists under a
// distinct name to avoid the symbol collision.

import Foundation
import CoreGraphics

public enum TextCellBucketRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .textCell(common, geometry, color, textCell) = parameters else {
            return input
        }

        // GPU fast path for variants whose Metal shader is fully implemented
        // in TextCell.metal. Falls back to the CPU pixel loop below if Metal
        // is unavailable (CI, no default device) or the pipeline fails.
        switch effect {
        case .dots:
            do {
                return try TextCellRenderer.renderDotsFromBucket(
                    input: input, common: common, geometry: geometry,
                    color: color, params: textCell, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        case .blockify:
            do {
                return try TextCellRenderer.renderBlockifyFromBucket(
                    input: input, common: common, geometry: geometry,
                    color: color, params: textCell, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        default:
            break
        }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        guard let sourcePixels = EffectBitmapSupport.rasterize(input, width: width, height: height) else {
            return input
        }

        var outputPixels = [UInt8](repeating: 0, count: height * width * 4)
        let background = backgroundColor(for: color, variant: textCell.variant, params: textCell)
        let bgComponents = rgbComponents(from: background)
        for index in stride(from: 0, to: outputPixels.count, by: 4) {
            outputPixels[index] = UInt8(bgComponents[0] * 255)
            outputPixels[index + 1] = UInt8(bgComponents[1] * 255)
            outputPixels[index + 2] = UInt8(bgComponents[2] * 255)
            outputPixels[index + 3] = 255
        }

        let cellSize = max(3, Int((geometry.scale * 6.0).rounded()) + Int(geometry.spacing.rounded()))
        let alpha = max(0.1, min(1.0, textCell.intensity * common.contrast / 1.5))

        for y in stride(from: 0, to: height, by: cellSize) {
            for x in stride(from: 0, to: width, by: cellSize) {
                let rect = CGRect(x: x, y: y, width: min(cellSize, width - x), height: min(cellSize, height - y))
                let sample = averageColor(in: rect, width: width, sourcePixels: sourcePixels)
                let styled = styledColor(sample: sample, variant: textCell.variant, colorMode: color.mode, common: common, params: textCell)
                let components = rgbComponents(from: styled.copy(alpha: alpha) ?? styled)
                let fill = (
                    UInt8(max(0, min(255, Int((components[0] * 255).rounded())))),
                    UInt8(max(0, min(255, Int((components[1] * 255).rounded())))),
                    UInt8(max(0, min(255, Int((components[2] * 255).rounded()))))
                )

                switch effect {
                case .dots:
                    let baseRect = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.2)
                    let dotRect = textCell.gridType == .hex && Int(rect.origin.y / CGFloat(cellSize)) % 2 == 1
                        ? baseRect.offsetBy(dx: rect.width * 0.15, dy: 0)
                        : baseRect
                    switch textCell.dotShape {
                    case .circle:
                        paintEllipse(in: dotRect, canvasWidth: width, pixels: &outputPixels, fill: fill)
                    case .square:
                        paintRect(dotRect, canvasWidth: width, pixels: &outputPixels, fill: fill)
                    case .diamond:
                        paintDiamond(in: dotRect, canvasWidth: width, pixels: &outputPixels, fill: fill)
                    }
                case .blockify:
                    switch textCell.blockStyle {
                    case .solid:
                        paintRect(rect, canvasWidth: width, pixels: &outputPixels, fill: fill)
                    case .outlined:
                        let borderFill = rgbComponents(from: textCell.borderColor?.cgColor ?? styled)
                        let border = (
                            UInt8(max(0, min(255, Int((borderFill[0] * 255).rounded())))),
                            UInt8(max(0, min(255, Int((borderFill[1] * 255).rounded())))),
                            UInt8(max(0, min(255, Int((borderFill[2] * 255).rounded()))))
                        )
                        paintRect(rect, canvasWidth: width, pixels: &outputPixels, fill: border)
                        let inset = max(1.0, rect.width * textCell.borderWidth * 0.4)
                        paintRect(rect.insetBy(dx: inset, dy: inset), canvasWidth: width, pixels: &outputPixels, fill: fill)
                    }
                case .matrixRain:
                    paintMatrixRain(rect: rect, canvasWidth: width, canvasHeight: height, cellSize: cellSize, pixels: &outputPixels, fill: fill, sample: sample, params: textCell)
                default:
                    paintASCII(rect: rect, canvasWidth: width, pixels: &outputPixels, fill: fill, params: textCell)
                }
            }
        }

        return EffectBitmapSupport.makeImage(from: &outputPixels, width: width, height: height) ?? input
    }

    private static func averageColor(in rect: CGRect, width: Int, sourcePixels: [UInt8]) -> CGColor {
        var totalR = 0.0
        var totalG = 0.0
        var totalB = 0.0
        var count = 0.0

        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)

        for y in minY..<maxY {
            for x in minX..<maxX {
                let idx = (y * width + x) * 4
                totalR += Double(sourcePixels[idx]) / 255.0
                totalG += Double(sourcePixels[idx + 1]) / 255.0
                totalB += Double(sourcePixels[idx + 2]) / 255.0
                count += 1.0
            }
        }

        let divisor = max(1.0, count)
        return CGColor(red: totalR / divisor, green: totalG / divisor, blue: totalB / divisor, alpha: 1.0)
    }

    private static func styledColor(
        sample: CGColor,
        variant: TextCellVariant,
        colorMode: GPUEffectColorMode,
        common: GPUEffectCommonParameters,
        params: TextCellParameters
    ) -> CGColor {
        let components = sample.components ?? [1, 1, 1, 1]
        let r = components[0]
        let g = components[1]
        let b = components[2]
        let brightness = max(0, min(1, ((r + g + b) / 3.0) + common.brightness))

        if let foreground = params.foreground {
            let fg = rgbComponents(from: foreground.cgColor)
            return CGColor(
                red: min(1, fg[0] * max(0.2, params.intensity)),
                green: min(1, fg[1] * max(0.2, params.intensity)),
                blue: min(1, fg[2] * max(0.2, params.intensity)),
                alpha: 1.0
            )
        }

        switch (variant, colorMode) {
        case (.matrixRain, _):
            return CGColor(red: brightness * 0.15, green: brightness, blue: brightness * 0.2, alpha: 1.0)
        case (.dots, .monochrome), (.ascii, .monochrome):
            return CGColor(red: brightness, green: brightness, blue: brightness, alpha: 1.0)
        case (.blockify, _):
            return CGColor(red: r, green: g, blue: b, alpha: 1.0)
        default:
            let setBias = characterSetBias(params.characterSet)
            return CGColor(
                red: min(1, (r * common.saturation + setBias.r) * max(0.2, params.intensity)),
                green: min(1, (g * common.saturation + setBias.g) * max(0.2, params.intensity)),
                blue: min(1, (b * common.saturation + setBias.b) * max(0.2, params.intensity)),
                alpha: 1.0
            )
        }
    }

    private static func backgroundColor(for color: GPUEffectColorParameters, variant: TextCellVariant, params: TextCellParameters) -> CGColor {
        if let background = params.background {
            return background.cgColor
        }

        switch (color.mode, variant) {
        case (.foregroundBackground, .matrixRain):
            return CGColor(red: 0.02, green: 0.06, blue: 0.02, alpha: 1.0)
        case (.foregroundBackground, _):
            let intensity = max(0, min(1, color.backgroundIntensity))
            return CGColor(red: intensity, green: intensity, blue: intensity, alpha: 1.0)
        case (.monochrome, _):
            return CGColor(gray: color.backgroundIntensity, alpha: 1.0)
        case (.palette, _):
            return CGColor(red: color.backgroundIntensity * 0.3, green: color.backgroundIntensity * 0.2, blue: color.backgroundIntensity * 0.4, alpha: 1.0)
        case (.source, _):
            return CGColor(gray: 0, alpha: 1.0)
        }
    }

    private static func characterSetBias(_ set: GPUEffectCharacterSet) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch set {
        case .classicASCII: return (0, 0, 0)
        case .blocks: return (0.05, 0.05, 0.05)
        case .binary: return (0.0, 0.08, 0.0)
        case .dense: return (0.04, 0.02, 0.06)
        }
    }

    private static func rgbComponents(from color: CGColor) -> [CGFloat] {
        guard let comps = color.components else { return [0, 0, 0, 1] }
        if comps.count >= 3 { return comps }
        if comps.count == 2 { return [comps[0], comps[0], comps[0], comps[1]] }
        if comps.count == 1 { return [comps[0], comps[0], comps[0], 1] }
        return [0, 0, 0, 1]
    }

    private static func paintRect(_ rect: CGRect, canvasWidth: Int, pixels: inout [UInt8], fill: (UInt8, UInt8, UInt8)) {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(canvasWidth, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.count / (canvasWidth * 4), Int(rect.maxY.rounded(.up)))
        for y in minY..<maxY {
            for x in minX..<maxX {
                let idx = (y * canvasWidth + x) * 4
                pixels[idx] = fill.0
                pixels[idx + 1] = fill.1
                pixels[idx + 2] = fill.2
                pixels[idx + 3] = 255
            }
        }
    }

    private static func paintEllipse(in rect: CGRect, canvasWidth: Int, pixels: inout [UInt8], fill: (UInt8, UInt8, UInt8)) {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(canvasWidth, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.count / (canvasWidth * 4), Int(rect.maxY.rounded(.up)))
        let cx = rect.midX
        let cy = rect.midY
        let rx = max(0.5, rect.width / 2)
        let ry = max(0.5, rect.height / 2)
        for y in minY..<maxY {
            for x in minX..<maxX {
                let dx = (Double(x) + 0.5 - cx) / rx
                let dy = (Double(y) + 0.5 - cy) / ry
                if (dx * dx) + (dy * dy) <= 1.0 {
                    let idx = (y * canvasWidth + x) * 4
                    pixels[idx] = fill.0
                    pixels[idx + 1] = fill.1
                    pixels[idx + 2] = fill.2
                    pixels[idx + 3] = 255
                }
            }
        }
    }

    private static func paintMatrixRain(
        rect: CGRect,
        canvasWidth: Int,
        canvasHeight: Int,
        cellSize: Int,
        pixels: inout [UInt8],
        fill: (UInt8, UInt8, UInt8),
        sample: CGColor,
        params: TextCellParameters
    ) {
        let directionOffset: (dx: Int, dy: Int)
        switch params.direction {
        case .down: directionOffset = (0, 1)
        case .up: directionOffset = (0, -1)
        case .left: directionOffset = (-1, 0)
        case .right: directionOffset = (1, 0)
        }

        let trailScale = max(1, Int((params.trailLength * Double(cellSize)).rounded()))
        let glow = max(0, min(1, params.glow))
        let opacity = max(0, min(1, params.backgroundOpacity))
        let threshold = max(0, min(1, params.threshold))
        let rainFill: (UInt8, UInt8, UInt8) = {
            if let rainColor = params.rainColor {
                let c = rgbComponents(from: rainColor.cgColor)
                return (
                    UInt8((c[0] * 255).rounded()),
                    UInt8((c[1] * 255).rounded()),
                    UInt8((c[2] * 255).rounded())
                )
            }
            return fill
        }()

        if opacity > 0 {
            let bgRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            let bgFill = (
                UInt8(Double(rainFill.0) * opacity),
                UInt8(Double(rainFill.1) * opacity),
                UInt8(Double(rainFill.2) * opacity)
            )
            paintRect(bgRect, canvasWidth: canvasWidth, pixels: &pixels, fill: bgFill)
        }

        let brightness = ((sample.components?[0] ?? 0) + (sample.components?[1] ?? 0) + (sample.components?[2] ?? 0)) / 3.0
        guard brightness >= threshold else { return }

        let stemRect = CGRect(x: rect.minX + rect.width * 0.35, y: rect.minY, width: rect.width * 0.3, height: rect.height)
        paintRect(stemRect, canvasWidth: canvasWidth, pixels: &pixels, fill: rainFill)

        if glow > 0 {
            for step in 1...trailScale {
                let glowRect = stemRect.offsetBy(dx: CGFloat(directionOffset.dx * step), dy: CGFloat(directionOffset.dy * step))
                guard glowRect.minX < CGFloat(canvasWidth), glowRect.maxX >= 0, glowRect.minY < CGFloat(canvasHeight), glowRect.maxY >= 0 else { continue }
                let factor = max(0.15, glow * (1.0 - Double(step) / Double(trailScale + 1)))
                let glowFill = (
                    UInt8(Double(rainFill.0) * factor),
                    UInt8(Double(rainFill.1) * factor),
                    UInt8(Double(rainFill.2) * factor)
                )
                paintRect(glowRect, canvasWidth: canvasWidth, pixels: &pixels, fill: glowFill)
            }
        }
    }

    private static func paintDiamond(in rect: CGRect, canvasWidth: Int, pixels: inout [UInt8], fill: (UInt8, UInt8, UInt8)) {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(canvasWidth, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.count / (canvasWidth * 4), Int(rect.maxY.rounded(.up)))
        let cx = rect.midX
        let cy = rect.midY
        let rx = max(0.5, rect.width / 2)
        let ry = max(0.5, rect.height / 2)
        for y in minY..<maxY {
            for x in minX..<maxX {
                let dx = abs((Double(x) + 0.5 - cx) / rx)
                let dy = abs((Double(y) + 0.5 - cy) / ry)
                if dx + dy <= 1.0 {
                    let idx = (y * canvasWidth + x) * 4
                    pixels[idx] = fill.0
                    pixels[idx + 1] = fill.1
                    pixels[idx + 2] = fill.2
                    pixels[idx + 3] = 255
                }
            }
        }
    }

    private static func paintASCII(
        rect: CGRect,
        canvasWidth: Int,
        pixels: inout [UInt8],
        fill: (UInt8, UInt8, UInt8),
        params: TextCellParameters
    ) {
        switch params.characterSet {
        case .classicASCII:
            paintRect(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.25, width: rect.width, height: rect.height * 0.5), canvasWidth: canvasWidth, pixels: &pixels, fill: fill)
        case .blocks:
            paintRect(rect, canvasWidth: canvasWidth, pixels: &pixels, fill: fill)
        case .binary:
            let half = rect.width * 0.4
            paintRect(CGRect(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.15, width: half, height: rect.height * 0.7), canvasWidth: canvasWidth, pixels: &pixels, fill: fill)
            paintRect(CGRect(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.15, width: half * 0.55, height: rect.height * 0.7), canvasWidth: canvasWidth, pixels: &pixels, fill: fill)
        case .dense:
            paintRect(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.15, width: rect.width, height: rect.height * 0.25), canvasWidth: canvasWidth, pixels: &pixels, fill: fill)
            paintRect(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.60, width: rect.width, height: rect.height * 0.25), canvasWidth: canvasWidth, pixels: &pixels, fill: fill)
        }
    }
}
