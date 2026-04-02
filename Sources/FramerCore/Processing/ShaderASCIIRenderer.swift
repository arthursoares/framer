import Foundation
import CoreGraphics

enum ShaderASCIIRenderer {
    static func apply(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil
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

        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: workWidth * workHeight * 4)
        let outputPixels = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let cellSize = max(1, min(64, asciiParams.cellSize))
        let edgeBias = ShaderPrimitives.clamp01(asciiParams.edgeBias)
        let foreground = asciiParams.foreground
        let background = asciiParams.background
        let intensity = ShaderPrimitives.clamp01(params.intensity)

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

        func styleColorBytes(for normalizedValue: Double) -> (UInt8, UInt8, UInt8) {
            let value = asciiParams.invert ? 1.0 - normalizedValue : normalizedValue
            let red = background.red + ((foreground.red - background.red) * value)
            let green = background.green + ((foreground.green - background.green) * value)
            let blue = background.blue + ((foreground.blue - background.blue) * value)
            return (
                byte(red),
                byte(green),
                byte(blue)
            )
        }

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
                let weightedValue = (baseLuminance * (1.0 - edgeBias)) + (averageEdge * edgeBias)
                let (red, green, blue) = styleColorBytes(for: weightedValue)

                let outputXStart = min(width, Int((Double(cellX) * Double(width) / Double(workWidth)).rounded(.down)))
                let outputXEnd = max(
                    outputXStart + 1,
                    min(width, Int((Double(xEnd) * Double(width) / Double(workWidth)).rounded(.up)))
                )
                let outputYStart = min(height, Int((Double(cellY) * Double(height) / Double(workHeight)).rounded(.down)))
                let outputYEnd = max(
                    outputYStart + 1,
                    min(height, Int((Double(yEnd) * Double(height) / Double(workHeight)).rounded(.up)))
                )

                for y in outputYStart..<outputYEnd {
                    for x in outputXStart..<outputXEnd {
                        let idx = (y * width + x) * 4
                        outputPixels[idx] = ShaderPrimitives.mix(outputPixels[idx], red, intensity: intensity)
                        outputPixels[idx + 1] = ShaderPrimitives.mix(outputPixels[idx + 1], green, intensity: intensity)
                        outputPixels[idx + 2] = ShaderPrimitives.mix(outputPixels[idx + 2], blue, intensity: intensity)
                    }
                }
            }
        }

        guard let result = outputCtx.makeImage() else {
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
