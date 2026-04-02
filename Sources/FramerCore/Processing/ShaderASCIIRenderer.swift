import Foundation
import CoreGraphics

enum ShaderASCIIRenderer {
    private struct Glyph {
        let rows: [String]

        var width: Int { rows.first?.count ?? 0 }
        var height: Int { rows.count }

        func isFilled(x: Int, y: Int) -> Bool {
            guard y >= 0, y < rows.count else { return false }
            let row = rows[y]
            guard x >= 0, x < row.count else { return false }
            let index = row.index(row.startIndex, offsetBy: x)
            return row[index] == "#"
        }
    }

    private static let glyphRamp: [Glyph] = [
        Glyph(rows: [
            ".....",
            ".....",
            ".....",
            ".....",
            ".....",
            ".....",
            ".....",
        ]),
        Glyph(rows: [
            ".....",
            ".....",
            ".....",
            ".....",
            ".....",
            "..#..",
            ".....",
        ]),
        Glyph(rows: [
            ".....",
            ".#.#.",
            ".....",
            "..#..",
            ".....",
            ".#.#.",
            ".....",
        ]),
        Glyph(rows: [
            ".....",
            "..#..",
            "..#..",
            "#####",
            "..#..",
            "..#..",
            ".....",
        ]),
        Glyph(rows: [
            "#...#",
            ".#.#.",
            "..#..",
            ".#.#.",
            "#...#",
            ".....",
            ".....",
        ]),
        Glyph(rows: [
            "#...#",
            ".#.#.",
            "..#..",
            ".###.",
            "..#..",
            ".#.#.",
            "#...#",
        ]),
        Glyph(rows: [
            ".###.",
            "#...#",
            "#.#.#",
            "#...#",
            "#.#.#",
            "#...#",
            ".###.",
        ]),
        Glyph(rows: [
            "#####",
            "#.#.#",
            "#####",
            "#.#.#",
            "#####",
            "#.#.#",
            "#####",
        ]),
        Glyph(rows: [
            "#####",
            "##.##",
            "#####",
            ".###.",
            "#####",
            "##.##",
            "#####",
        ]),
        Glyph(rows: [
            ".###.",
            "#####",
            "#####",
            "#####",
            "#####",
            "#####",
            ".###.",
        ]),
    ]

    static func apply(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        guard case .ascii(let asciiParams) = params.params else {
            return image
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let workSize = scaledWorkSize(
            width: width,
            height: height,
            previewBaseDimension: previewBaseDimension
        )
        let workWidth = workSize.width
        let workHeight = workSize.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let sourceCtx = CGContext(
            data: nil,
            width: workWidth,
            height: workHeight,
            bitsPerComponent: 8,
            bytesPerRow: workWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        sourceCtx.interpolationQuality = workWidth == width && workHeight == height ? .none : .high
        sourceCtx.draw(image, in: CGRect(x: 0, y: 0, width: workWidth, height: workHeight))

        guard let outputCtx = CGContext(
            data: nil,
            width: workWidth,
            height: workHeight,
            bitsPerComponent: 8,
            bytesPerRow: workWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        outputCtx.draw(sourceCtx.makeImage()!, in: CGRect(x: 0, y: 0, width: workWidth, height: workHeight))

        guard let sourceData = sourceCtx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: workWidth * workHeight * 4)
        let outputPixels = outputData.bindMemory(to: UInt8.self, capacity: workWidth * workHeight * 4)

        let cellSize = max(1, min(64, asciiParams.cellSize))
        let edgeBias = ShaderPrimitives.clamp01(asciiParams.edgeBias)
        let intensity = ShaderPrimitives.clamp01(params.intensity)
        let paletteSource = sourceImage ?? image

        let foreground: CodableColor
        let background: CodableColor
        switch asciiParams.colorMode {
        case .manual(let manualForeground, let manualBackground):
            foreground = manualForeground
            background = manualBackground
        case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift):
            var (primary, secondary) = ColorExtractor.extractTwoDominantColors(from: paletteSource)
            if saturationShift != 0 || lightnessShift != 0 {
                primary = ShaderPrimitives.adjustColor(primary, saturationShift: saturationShift, lightnessShift: lightnessShift)
                secondary = ShaderPrimitives.adjustColor(secondary, saturationShift: saturationShift, lightnessShift: lightnessShift)
            }
            foreground = flipped ? secondary : primary
            background = flipped ? primary : secondary
        }

        func byte(_ component: Double) -> UInt8 {
            UInt8(max(0, min(255, Int((component * 255.0).rounded()))))
        }

        func luminance(atX x: Int, y: Int) -> Double {
            let clampedX = max(0, min(workWidth - 1, x))
            let clampedY = max(0, min(workHeight - 1, y))
            let idx = (clampedY * workWidth + clampedX) * 4
            let r = Double(sourcePixels[idx])
            let g = Double(sourcePixels[idx + 1])
            let b = Double(sourcePixels[idx + 2])
            return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }

        func colorBytes(for color: CodableColor) -> (UInt8, UInt8, UInt8) {
            return (
                byte(color.red),
                byte(color.green),
                byte(color.blue)
            )
        }

        let foregroundBytes = colorBytes(for: foreground)
        let backgroundBytes = colorBytes(for: background)

        for cellY in stride(from: 0, to: workHeight, by: cellSize) {
            try Task.checkCancellation()

            for cellX in stride(from: 0, to: workWidth, by: cellSize) {
                let xEnd = min(cellX + cellSize, workWidth)
                let yEnd = min(cellY + cellSize, workHeight)

                var luminanceSum = 0.0
                var edgeSum = 0.0
                var sampleCount = 0

                for y in cellY..<yEnd {
                    for x in cellX..<xEnd {
                        let center = luminance(atX: x, y: y)
                        let dx = abs(luminance(atX: x + 1, y: y) - luminance(atX: x - 1, y: y))
                        let dy = abs(luminance(atX: x, y: y + 1) - luminance(atX: x, y: y - 1))
                        luminanceSum += center
                        edgeSum += min(1.0, dx + dy)
                        sampleCount += 1
                    }
                }

                guard sampleCount > 0 else { continue }

                let baseLuminance = luminanceSum / Double(sampleCount)
                let averageEdge = edgeSum / Double(sampleCount)
                let weightedValue = ShaderPrimitives.clamp01((baseLuminance * (1.0 - edgeBias)) + (averageEdge * edgeBias))
                let glyphValue = asciiParams.invert ? 1.0 - weightedValue : weightedValue
                let glyphIndex = max(0, min(glyphRamp.count - 1, Int((glyphValue * Double(glyphRamp.count - 1)).rounded())))
                let glyph = glyphRamp[glyphIndex]

                let workCellWidth = max(1, xEnd - cellX)
                let workCellHeight = max(1, yEnd - cellY)
                let glyphDrawWidth = max(1, Int((Double(workCellWidth) * 0.7).rounded()))
                let glyphDrawHeight = max(1, Int((Double(workCellHeight) * 0.82).rounded()))
                let glyphXInset = max(0, (workCellWidth - glyphDrawWidth) / 2)
                let glyphYInset = max(0, (workCellHeight - glyphDrawHeight) / 2)

                for y in cellY..<yEnd {
                    for x in cellX..<xEnd {
                        let localX = x - cellX
                        let localY = y - cellY
                        let glyphMinX = glyphXInset
                        let glyphMaxX = glyphXInset + glyphDrawWidth
                        let glyphMinY = glyphYInset
                        let glyphMaxY = glyphYInset + glyphDrawHeight
                        let isInsideGlyphBounds =
                            localX >= glyphMinX && localX < glyphMaxX &&
                            localY >= glyphMinY && localY < glyphMaxY

                        let effectColor: (UInt8, UInt8, UInt8)
                        if isInsideGlyphBounds {
                            let normalizedX = Double(localX - glyphMinX) / Double(max(1, glyphDrawWidth))
                            let normalizedY = Double(localY - glyphMinY) / Double(max(1, glyphDrawHeight))
                            let glyphX = min(glyph.width - 1, max(0, Int((normalizedX * Double(glyph.width)).rounded(.down))))
                            let glyphY = min(glyph.height - 1, max(0, Int((normalizedY * Double(glyph.height)).rounded(.down))))
                            effectColor = glyph.isFilled(x: glyphX, y: glyphY) ? foregroundBytes : backgroundBytes
                        } else {
                            effectColor = backgroundBytes
                        }

                        let idx = (y * workWidth + x) * 4
                        outputPixels[idx] = ShaderPrimitives.mix(outputPixels[idx], effectColor.0, intensity: intensity)
                        outputPixels[idx + 1] = ShaderPrimitives.mix(outputPixels[idx + 1], effectColor.1, intensity: intensity)
                        outputPixels[idx + 2] = ShaderPrimitives.mix(outputPixels[idx + 2], effectColor.2, intensity: intensity)
                    }
                }
            }
        }

        guard let workResult = outputCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        guard workWidth != width || workHeight != height else {
            return workResult
        }

        guard let finalCtx = CGContext(
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
        finalCtx.interpolationQuality = .high
        finalCtx.draw(workResult, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let result = finalCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    private static func scaledWorkSize(
        width: Int,
        height: Int,
        previewBaseDimension: Int?
    ) -> (width: Int, height: Int) {
        guard let previewBaseDimension, max(width, height) > previewBaseDimension else {
            return (width, height)
        }

        let scale = Double(previewBaseDimension) / Double(max(width, height))
        return (
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }
}
