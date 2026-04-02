import Foundation
import CoreGraphics

enum ShaderPixelSortRenderer {
    static func apply(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .pixelSort(let pixelSortParams) = params.params else {
            return image
        }

        let blendIntensity = ShaderPrimitives.clamp01(params.intensity * pixelSortParams.amount)
        guard blendIntensity > 0 else { return image }

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
        ), let outputCtx = CGContext(
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
        outputCtx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let sourceData = sourceCtx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let outputPixels = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let threshold = ShaderPrimitives.clamp01(pixelSortParams.threshold)
        let span = max(1, min(256, pixelSortParams.span))

        struct PixelSample {
            let rgba: (UInt8, UInt8, UInt8, UInt8)
            let luminance: Double
        }

        func pixelIndex(x: Int, y: Int) -> Int {
            (y * width + x) * 4
        }

        func luminanceAt(x: Int, y: Int) -> Double {
            let idx = pixelIndex(x: x, y: y)
            let r = Double(sourcePixels[idx])
            let g = Double(sourcePixels[idx + 1])
            let b = Double(sourcePixels[idx + 2])
            return ((0.299 * r) + (0.587 * g) + (0.114 * b)) / 255.0
        }

        func sampleAt(x: Int, y: Int) -> PixelSample {
            let idx = pixelIndex(x: x, y: y)
            return PixelSample(
                rgba: (sourcePixels[idx], sourcePixels[idx + 1], sourcePixels[idx + 2], sourcePixels[idx + 3]),
                luminance: luminanceAt(x: x, y: y)
            )
        }

        func writeSortedSpan(points: [(x: Int, y: Int)]) {
            let sorted = points
                .map { sampleAt(x: $0.x, y: $0.y) }
                .sorted { $0.luminance < $1.luminance }

            for (offset, point) in points.enumerated() {
                let idx = pixelIndex(x: point.x, y: point.y)
                let sample = sorted[offset].rgba
                outputPixels[idx] = ShaderPrimitives.mix(outputPixels[idx], sample.0, intensity: blendIntensity)
                outputPixels[idx + 1] = ShaderPrimitives.mix(outputPixels[idx + 1], sample.1, intensity: blendIntensity)
                outputPixels[idx + 2] = ShaderPrimitives.mix(outputPixels[idx + 2], sample.2, intensity: blendIntensity)
                outputPixels[idx + 3] = ShaderPrimitives.mix(outputPixels[idx + 3], sample.3, intensity: blendIntensity)
            }
        }

        func sortHorizontalRow(_ y: Int) throws {
            var x = 0
            while x < width {
                let currentLuminance = luminanceAt(x: x, y: y)
                guard currentLuminance >= threshold else {
                    x += 1
                    continue
                }

                var points: [(x: Int, y: Int)] = []
                while x < width, points.count < span, luminanceAt(x: x, y: y) >= threshold {
                    points.append((x: x, y: y))
                    x += 1
                }

                if points.count > 1 {
                    writeSortedSpan(points: points)
                }
            }
        }

        func sortVerticalColumn(_ x: Int) throws {
            var y = 0
            while y < height {
                let currentLuminance = luminanceAt(x: x, y: y)
                guard currentLuminance >= threshold else {
                    y += 1
                    continue
                }

                var points: [(x: Int, y: Int)] = []
                while y < height, points.count < span, luminanceAt(x: x, y: y) >= threshold {
                    points.append((x: x, y: y))
                    y += 1
                }

                if points.count > 1 {
                    writeSortedSpan(points: points)
                }
            }
        }

        switch pixelSortParams.direction {
        case .horizontal:
            for y in 0..<height {
                try Task.checkCancellation()
                try sortHorizontalRow(y)
            }
        case .vertical:
            for x in 0..<width {
                try Task.checkCancellation()
                try sortVerticalColumn(x)
            }
        }

        guard let result = outputCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        return result
    }
}
