import Foundation
import CoreGraphics

enum ShaderASCIIRenderer {
    static func apply(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .ascii(let asciiParams) = params.params else {
            return image
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let sourceCtx = CGContext(
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
        sourceCtx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let outputCtx = CGContext(
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
        outputCtx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let sourceData = sourceCtx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let outputPixels = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let cellSize = max(1, asciiParams.cellSize)
        let edgeBias = ShaderPrimitives.clamp01(asciiParams.edgeBias)
        let foreground = asciiParams.foreground
        let background = asciiParams.background
        let intensity = ShaderPrimitives.clamp01(params.intensity)

        func byte(_ component: Double) -> UInt8 {
            UInt8(max(0, min(255, Int((component * 255.0).rounded()))))
        }

        func luminance(atX x: Int, y: Int) -> Double {
            let clampedX = max(0, min(width - 1, x))
            let clampedY = max(0, min(height - 1, y))
            let idx = (clampedY * width + clampedX) * 4
            let r = Double(sourcePixels[idx])
            let g = Double(sourcePixels[idx + 1])
            let b = Double(sourcePixels[idx + 2])
            return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }

        func styleColor(for normalizedValue: Double) -> CodableColor {
            let value = asciiParams.invert ? 1.0 - normalizedValue : normalizedValue
            let red = background.red + ((foreground.red - background.red) * value)
            let green = background.green + ((foreground.green - background.green) * value)
            let blue = background.blue + ((foreground.blue - background.blue) * value)
            return CodableColor(
                unchecked: String(
                    format: "#%02X%02X%02X",
                    Int((red * 255.0).rounded()),
                    Int((green * 255.0).rounded()),
                    Int((blue * 255.0).rounded())
                )
            )
        }

        for cellY in stride(from: 0, to: height, by: cellSize) {
            try Task.checkCancellation()

            for cellX in stride(from: 0, to: width, by: cellSize) {
                let xEnd = min(cellX + cellSize, width)
                let yEnd = min(cellY + cellSize, height)

                var luminanceSum = 0.0
                var edgeSum = 0.0
                var alphaSum = 0.0
                var sampleCount = 0

                for y in cellY..<yEnd {
                    for x in cellX..<xEnd {
                        let idx = (y * width + x) * 4
                        let center = luminance(atX: x, y: y)
                        let dx = abs(luminance(atX: x + 1, y: y) - luminance(atX: x - 1, y: y))
                        let dy = abs(luminance(atX: x, y: y + 1) - luminance(atX: x, y: y - 1))
                        luminanceSum += center
                        edgeSum += min(1.0, dx + dy)
                        alphaSum += Double(sourcePixels[idx + 3]) / 255.0
                        sampleCount += 1
                    }
                }

                guard sampleCount > 0 else { continue }

                let baseLuminance = luminanceSum / Double(sampleCount)
                let averageEdge = edgeSum / Double(sampleCount)
                let alpha = alphaSum / Double(sampleCount)
                let weightedValue = (baseLuminance * (1.0 - edgeBias)) + (averageEdge * edgeBias)
                let blockColor = styleColor(for: weightedValue)
                let red = byte(blockColor.red)
                let green = byte(blockColor.green)
                let blue = byte(blockColor.blue)

                for y in cellY..<yEnd {
                    for x in cellX..<xEnd {
                        let idx = (y * width + x) * 4
                        let averagedAlpha = UInt8(max(0, min(255, Int((alpha * 255.0).rounded()))))
                        outputPixels[idx] = ShaderPrimitives.mix(sourcePixels[idx], red, intensity: intensity)
                        outputPixels[idx + 1] = ShaderPrimitives.mix(sourcePixels[idx + 1], green, intensity: intensity)
                        outputPixels[idx + 2] = ShaderPrimitives.mix(sourcePixels[idx + 2], blue, intensity: intensity)
                        outputPixels[idx + 3] = ShaderPrimitives.mix(sourcePixels[idx + 3], averagedAlpha, intensity: intensity)
                    }
                }
            }
        }

        guard let result = outputCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        return result
    }
}
