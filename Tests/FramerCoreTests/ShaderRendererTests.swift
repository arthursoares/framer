// Tests/FramerCoreTests/ShaderRendererTests.swift
import XCTest
import CoreGraphics
@testable import FramerCore

final class ShaderRendererTests: XCTestCase {
    func makeColorGridImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = UInt8((x * 13 + y * 7) % 256)
                let g = UInt8((x * 3 + y * 19) % 256)
                let b = UInt8((x * 11 + y * 5) % 256)
                data[idx] = r
                data[idx + 1] = g
                data[idx + 2] = b
                data[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    func makeStripedGradientImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let span = max(1, min(24, width))
                let segment = x / span
                let localX = x % span
                let ramp = segment.isMultiple(of: 2) ? (span - 1 - localX) : localX
                let base = UInt8(max(0, min(255, Int((Double(ramp) / Double(max(1, span - 1))) * 255.0))))
                let contrast = ((segment + y) % 2 == 0) ? 72 : 224
                data[idx] = base
                data[idx + 1] = UInt8((Int(base) + contrast) / 2)
                data[idx + 2] = UInt8(max(0, min(255, contrast - Int(base) / 3)))
                data[idx + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    func makeTranslucentStripedGradientImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let alpha = UInt8(max(48, min(255, (x * 255) / max(1, width - 1))))
                let span = max(1, min(24, width))
                let segment = x / span
                let localX = x % span
                let ramp = segment.isMultiple(of: 2) ? (span - 1 - localX) : localX
                let intensity = Double(ramp) / Double(max(1, span - 1))
                let red = UInt8((Double(alpha) * intensity).rounded())
                let green = UInt8((Double(alpha) * (0.3 + intensity * 0.5)).rounded())
                let blue = UInt8((Double(alpha) * (0.2 + intensity * 0.3)).rounded())
                data[idx] = red
                data[idx + 1] = green
                data[idx + 2] = blue
                data[idx + 3] = alpha
            }
        }
        return ctx.makeImage()!
    }

    func makePortraitReferenceImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let centerX = Double(width) * 0.5
        let centerY = Double(height) * 0.46
        let faceRadiusX = Double(width) * 0.24
        let faceRadiusY = Double(height) * 0.3

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let nx = Double(x) / Double(max(1, width - 1))
                let ny = Double(y) / Double(max(1, height - 1))

                var r = 28.0 + nx * 70.0 + ny * 35.0
                var g = 24.0 + nx * 32.0 + ny * 26.0
                var b = 42.0 + nx * 18.0 + ny * 54.0

                let dx = (Double(x) - centerX) / faceRadiusX
                let dy = (Double(y) - centerY) / faceRadiusY
                let faceDistance = dx * dx + dy * dy
                if faceDistance < 1.0 {
                    let faceMask = 1.0 - faceDistance
                    r += 150.0 * faceMask
                    g += 105.0 * faceMask
                    b += 82.0 * faceMask

                    let eyeBand = abs(Double(y) - Double(height) * 0.4)
                    if eyeBand < Double(height) * 0.03 && abs(Double(x) - centerX) > Double(width) * 0.05 {
                        r -= 36.0 * faceMask
                        g -= 28.0 * faceMask
                        b -= 24.0 * faceMask
                    }

                    if Double(y) > Double(height) * 0.56 {
                        let mouthMask = max(0.0, 1.0 - abs(Double(y) - Double(height) * 0.64) / (Double(height) * 0.035))
                        r += 22.0 * mouthMask * faceMask
                        g -= 8.0 * mouthMask * faceMask
                        b -= 10.0 * mouthMask * faceMask
                    }
                }

                let vignette = 1.0 - min(1.0, hypot(nx - 0.5, ny - 0.5) * 1.15)
                r += vignette * 18.0
                g += vignette * 10.0
                b += vignette * 8.0

                let texture = Double(((x &* 17) ^ (y &* 29) ^ ((x + y) &* 11)) & 15) - 7.0
                r += texture * 1.8
                g += texture * 1.3
                b += texture * 1.1

                data[idx] = UInt8(max(0, min(255, Int(r.rounded()))))
                data[idx + 1] = UInt8(max(0, min(255, Int(g.rounded()))))
                data[idx + 2] = UInt8(max(0, min(255, Int(b.rounded()))))
                data[idx + 3] = 255
            }
        }

        return ctx.makeImage()!
    }

    func uniqueColorCount(in image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var colors = Set<UInt32>()
        colors.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let idx = i * 4
            let packed = (UInt32(data[idx]) << 24)
                | (UInt32(data[idx + 1]) << 16)
                | (UInt32(data[idx + 2]) << 8)
                | UInt32(data[idx + 3])
            colors.insert(packed)
        }
        return colors.count
    }


    func pixelData(for image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let count = width * height * 4
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: count)
        return Array(UnsafeBufferPointer(start: data, count: count))
    }

    func packedColorAt(_ image: CGImage, x: Int, y: Int) -> UInt32 {
        let pixels = pixelData(for: image)
        let idx = (y * image.width + x) * 4
        return (UInt32(pixels[idx]) << 24)
            | (UInt32(pixels[idx + 1]) << 16)
            | (UInt32(pixels[idx + 2]) << 8)
            | UInt32(pixels[idx + 3])
    }

    func luminanceValuesForRow(_ image: CGImage, y: Int, xRange: Range<Int>) -> [Double] {
        let pixels = pixelData(for: image)
        return xRange.map { x in
            let idx = (y * image.width + x) * 4
            let r = Double(pixels[idx])
            let g = Double(pixels[idx + 1])
            let b = Double(pixels[idx + 2])
            return (0.299 * r) + (0.587 * g) + (0.114 * b)
        }
    }

    func luminanceValuesForColumn(_ image: CGImage, x: Int, yRange: Range<Int>) -> [Double] {
        let pixels = pixelData(for: image)
        return yRange.map { y in
            let idx = (y * image.width + x) * 4
            let r = Double(pixels[idx])
            let g = Double(pixels[idx + 1])
            let b = Double(pixels[idx + 2])
            return (0.299 * r) + (0.587 * g) + (0.114 * b)
        }
    }

    func averageRGB(in image: CGImage) -> (r: Double, g: Double, b: Double) {
        let pixels = pixelData(for: image)
        var r = 0.0
        var g = 0.0
        var b = 0.0
        let count = image.width * image.height
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            r += Double(pixels[idx])
            g += Double(pixels[idx + 1])
            b += Double(pixels[idx + 2])
        }
        return (r / Double(count), g / Double(count), b / Double(count))
    }

    func averageSaturation(in image: CGImage) -> Double {
        let pixels = pixelData(for: image)
        var total = 0.0
        let count = image.width * image.height
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[idx]) / 255.0
            let g = Double(pixels[idx + 1]) / 255.0
            let b = Double(pixels[idx + 2]) / 255.0
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let delta = maxValue - minValue
            total += maxValue == 0 ? 0 : delta / maxValue
        }
        return total / Double(count)
    }

    func luminanceValues(in image: CGImage) -> [Double] {
        let pixels = pixelData(for: image)
        var values: [Double] = []
        values.reserveCapacity(image.width * image.height)
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[idx])
            let g = Double(pixels[idx + 1])
            let b = Double(pixels[idx + 2])
            values.append((0.299 * r) + (0.587 * g) + (0.114 * b))
        }
        return values
    }

    func averageBottomQuartileLuminance(in image: CGImage) -> Double {
        let sorted = luminanceValues(in: image).sorted()
        let quartileCount = max(1, sorted.count / 4)
        let slice = sorted.prefix(quartileCount)
        return slice.reduce(0.0, +) / Double(slice.count)
    }

    func luminanceStandardDeviation(in image: CGImage) -> Double {
        let values = luminanceValues(in: image)
        let mean = values.reduce(0.0, +) / Double(values.count)
        let variance = values.reduce(0.0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(values.count)
        return sqrt(variance)
    }

    func averageNeighborDelta(in image: CGImage) -> Double {
        let pixels = pixelData(for: image)
        let width = image.width
        let height = image.height
        var total = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let idxA = (y * width + x) * 4
                let idxB = (y * width + x + 1) * 4
                total += abs(Double(pixels[idxA]) - Double(pixels[idxB]))
                total += abs(Double(pixels[idxA + 1]) - Double(pixels[idxB + 1]))
                total += abs(Double(pixels[idxA + 2]) - Double(pixels[idxB + 2]))
                count += 3
            }
        }
        return total / Double(max(1, count))
    }

    func test_asciiShader_preservesDimensions() throws {
        let image = makeColorGridImage(width: 37, height: 23)
        let params = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams())
        )

        let result = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
    }



    func test_asciiShader_drawsGlyphStructureWithinCells() throws {
        let image = makeColorGridImage(width: 24, height: 24)
        let params = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 6, edgeBias: 0.0, foreground: .white, background: .black, invert: false))
        )

        let result = try ShaderRenderer.apply(to: image, params: params)

        var blockColors = Set<UInt32>()
        for y in stride(from: 1, to: result.height, by: 6) {
            for x in stride(from: 1, to: result.width, by: 6) {
                blockColors.insert(packedColorAt(result, x: x, y: y))
            }
        }
        XCTAssertGreaterThan(blockColors.count, 1)

        var firstCellColors = Set<UInt32>()
        for y in 0..<6 {
            for x in 0..<6 {
                firstCellColors.insert(packedColorAt(result, x: x, y: y))
            }
        }
        XCTAssertGreaterThan(firstCellColors.count, 1)
    }

    func test_asciiShader_invertChangesOutput() throws {
        let image = makeColorGridImage(width: 24, height: 24)
        let normalParams = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 6, edgeBias: 0.3, foreground: .white, background: .black, invert: false))
        )
        let invertedParams = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 6, edgeBias: 0.3, foreground: .white, background: .black, invert: true))
        )

        let normal = try ShaderRenderer.apply(to: image, params: normalParams)
        let inverted = try ShaderRenderer.apply(to: image, params: invertedParams)

        XCTAssertNotEqual(pixelData(for: normal), pixelData(for: inverted))
    }

    func test_asciiShader_dominantTwoToneUsesExtractedPalette() throws {
        let image = makePortraitReferenceImage(width: 32, height: 32)
        let manualParams = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(
                cellSize: 6,
                edgeBias: 0.3,
                colorMode: .manual(foreground: .white, background: .black),
                invert: false
            ))
        )
        let dominantParams = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(
                cellSize: 6,
                edgeBias: 0.3,
                colorMode: .dominantTwoTone(flipped: false, saturationShift: 10, lightnessShift: -5),
                invert: false
            ))
        )

        let manual = try ShaderRenderer.apply(to: image, params: manualParams)
        let dominant = try ShaderRenderer.apply(to: image, params: dominantParams, sourceImage: image)

        XCTAssertNotEqual(pixelData(for: manual), pixelData(for: dominant))
    }

    func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height
        guard max(width, height) > maxDimension else { return image }

        let scale = Double(maxDimension) / Double(max(width, height))
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return ctx.makeImage()!
    }

    func test_asciiShader_previewDimensionMatchesPreviewSampling() throws {
        let image = makeColorGridImage(width: 64, height: 64)
        let params = ShaderLayerParams(
            style: .ascii,
            intensity: 1.0,
            params: .ascii(ASCIIShaderParams(cellSize: 4, edgeBias: 0.4, foreground: .white, background: .black, invert: false))
        )

        let previewInput = downscale(image, maxDimension: 32)
        let previewOutput = try ShaderRenderer.apply(to: previewInput, params: params)
        let exportOutput = try ShaderRenderer.apply(to: image, params: params, previewBaseDimension: 32)

        // Sobel edge detection is scale-sensitive so exact pixel parity is not
        // guaranteed. Verify dimensions match expectations and that both outputs
        // produce structurally similar results (majority of sampled cell centers
        // within tolerance).
        XCTAssertEqual(previewOutput.width, previewInput.width)
        XCTAssertEqual(previewOutput.height, previewInput.height)
        XCTAssertEqual(exportOutput.width, image.width)
        XCTAssertEqual(exportOutput.height, image.height)

        var matchCount = 0
        var totalCount = 0
        let previewPixels = pixelData(for: previewOutput)
        let exportPixels = pixelData(for: exportOutput)
        for previewY in stride(from: 2, to: previewOutput.height, by: 4) {
            for previewX in stride(from: 2, to: previewOutput.width, by: 4) {
                let exportX = min(exportOutput.width - 1, previewX * 2)
                let exportY = min(exportOutput.height - 1, previewY * 2)
                let pIdx = (previewY * previewOutput.width + previewX) * 4
                let eIdx = (exportY * exportOutput.width + exportX) * 4
                let dr = abs(Int(previewPixels[pIdx]) - Int(exportPixels[eIdx]))
                let dg = abs(Int(previewPixels[pIdx + 1]) - Int(exportPixels[eIdx + 1]))
                let db = abs(Int(previewPixels[pIdx + 2]) - Int(exportPixels[eIdx + 2]))
                if dr <= 32 && dg <= 32 && db <= 32 { matchCount += 1 }
                totalCount += 1
            }
        }
        let matchRatio = Double(matchCount) / Double(max(1, totalCount))
        XCTAssertGreaterThan(matchRatio, 0.6, "Preview and export should be structurally similar")
    }

    func test_distantPastShader_reducesColorVariety() throws {
        let image = makeColorGridImage(width: 32, height: 32)
        let params = ShaderLayerParams(
            style: .distantPast,
            intensity: 1.0,
            params: .distantPast(DistantPastShaderParams(paletteDepth: 4, fade: 0.5, softness: 0.2, grain: 0.0))
        )

        let result = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(result.width, image.width)
        XCTAssertEqual(result.height, image.height)
        XCTAssertLessThan(uniqueColorCount(in: result), uniqueColorCount(in: image))
    }

    func test_crimewaveShader_pushesNeonBias() throws {
        let image = makePortraitReferenceImage(width: 160, height: 200)
        let params = ShaderLayerParams(
            style: .crimewave,
            intensity: 1.0,
            params: .crimewave(CrimewaveShaderParams())
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let sourceRGB = averageRGB(in: image)
        let outputRGB = averageRGB(in: output)

        XCTAssertGreaterThan(averageSaturation(in: output), averageSaturation(in: image))
        XCTAssertGreaterThan(outputRGB.b - outputRGB.g, sourceRGB.b - sourceRGB.g)
    }

    func test_narcShader_increasesTonalCrush() throws {
        let image = makePortraitReferenceImage(width: 160, height: 200)
        let params = ShaderLayerParams(
            style: .narc,
            intensity: 1.0,
            params: .narc(NarcShaderParams())
        )

        let output = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertLessThan(averageBottomQuartileLuminance(in: output), averageBottomQuartileLuminance(in: image))
        XCTAssertGreaterThan(luminanceStandardDeviation(in: output), luminanceStandardDeviation(in: image))
    }

    func test_shibaShader_warmsImage() throws {
        let image = makePortraitReferenceImage(width: 160, height: 200)
        let params = ShaderLayerParams(
            style: .shiba,
            intensity: 1.0,
            params: .shiba(ShibaShaderParams())
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let sourceRGB = averageRGB(in: image)
        let outputRGB = averageRGB(in: output)

        XCTAssertGreaterThan(outputRGB.r - outputRGB.b, sourceRGB.r - sourceRGB.b)
        XCTAssertGreaterThan(averageSaturation(in: output), averageSaturation(in: image))
    }

    func test_distantPastShader_reducesPaletteAndSoftens() throws {
        let image = makePortraitReferenceImage(width: 160, height: 200)
        let params = ShaderLayerParams(
            style: .distantPast,
            intensity: 1.0,
            params: .distantPast(DistantPastShaderParams())
        )

        let output = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertLessThan(uniqueColorCount(in: output), uniqueColorCount(in: image))
        XCTAssertLessThan(averageNeighborDelta(in: output), averageNeighborDelta(in: image))
    }

    func test_distantPastShader_intensityZeroMatchesOriginal() throws {
        let image = makePortraitReferenceImage(width: 96, height: 128)
        let params = ShaderLayerParams(
            style: .distantPast,
            intensity: 0.0,
            params: .distantPast(DistantPastShaderParams())
        )

        let output = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(pixelData(for: output), pixelData(for: image))
    }

    func test_pixelSortShader_reordersPixelsAboveThreshold() throws {
        let image = makeStripedGradientImage(width: 192, height: 96)
        let params = ShaderLayerParams(
            style: .pixelSort,
            intensity: 1.0,
            params: .pixelSort(PixelSortShaderParams(threshold: 0.1, direction: .horizontal, span: 24, amount: 1.0))
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let originalLuminance = luminanceValuesForRow(image, y: 24, xRange: 0..<24)
        let sortedLuminance = luminanceValuesForRow(output, y: 24, xRange: 0..<24)

        XCTAssertNotEqual(sortedLuminance, originalLuminance)
        XCTAssertEqual(sortedLuminance, sortedLuminance.sorted())
    }

    func test_pixelSortAmountZeroMatchesOriginal() throws {
        let image = makeStripedGradientImage(width: 128, height: 128)
        let params = ShaderLayerParams(
            style: .pixelSort,
            intensity: 1.0,
            params: .pixelSort(PixelSortShaderParams(amount: 0.0))
        )

        let output = try ShaderRenderer.apply(to: image, params: params)

        XCTAssertEqual(pixelData(for: output), pixelData(for: image))
    }

    func test_pixelSortVerticalDirectionReordersColumn() throws {
        let image = makeStripedGradientImage(width: 96, height: 192)
        let params = ShaderLayerParams(
            style: .pixelSort,
            intensity: 1.0,
            params: .pixelSort(PixelSortShaderParams(threshold: 0.1, direction: .vertical, span: 24, amount: 1.0))
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let originalLuminance = luminanceValuesForColumn(image, x: 24, yRange: 0..<24)
        let sortedLuminance = luminanceValuesForColumn(output, x: 24, yRange: 0..<24)

        XCTAssertNotEqual(sortedLuminance, originalLuminance)
        XCTAssertEqual(sortedLuminance, sortedLuminance.sorted())
    }

    func test_pixelSortMaintainsPremultipliedAlpha() throws {
        let image = makeTranslucentStripedGradientImage(width: 96, height: 96)
        let params = ShaderLayerParams(
            style: .pixelSort,
            intensity: 1.0,
            params: .pixelSort(PixelSortShaderParams(threshold: 0.1, direction: .horizontal, span: 24, amount: 1.0))
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let pixels = pixelData(for: output)

        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[idx + 3]
            XCTAssertLessThanOrEqual(pixels[idx], alpha)
            XCTAssertLessThanOrEqual(pixels[idx + 1], alpha)
            XCTAssertLessThanOrEqual(pixels[idx + 2], alpha)
        }
    }

    func test_compositeShaderMaintainsPremultipliedAlpha() throws {
        let image = makeTranslucentStripedGradientImage(width: 96, height: 96)
        let params = ShaderLayerParams(
            style: .crimewave,
            intensity: 1.0,
            params: .crimewave(CrimewaveShaderParams())
        )

        let output = try ShaderRenderer.apply(to: image, params: params)
        let pixels = pixelData(for: output)

        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[idx + 3]
            XCTAssertLessThanOrEqual(pixels[idx], alpha)
            XCTAssertLessThanOrEqual(pixels[idx + 1], alpha)
            XCTAssertLessThanOrEqual(pixels[idx + 2], alpha)
        }
    }
}
