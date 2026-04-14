import Foundation
import CoreGraphics
import ImageIO

enum ShaderASCIIRenderer {

    // MARK: - LUT Loading

    private struct LUT {
        let pixels: [UInt8] // grayscale values
        let width: Int
        let height: Int

        func sample(x: Int, y: Int) -> Double {
            let cx = max(0, min(width - 1, x))
            let cy = max(0, min(height - 1, y))
            return Double(pixels[cy * width + cx]) / 255.0
        }
    }

    private static let _lutLock = NSLock()
    nonisolated(unsafe) private static var _edgesLUT: LUT?
    nonisolated(unsafe) private static var _fillLUT: LUT?

    private static func loadLUT(named name: String) -> LUT? {
        for searchPath in TextureFrameProvider.searchPaths {
            let url = searchPath.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continue
            }
            return extractGrayscale(from: cgImage)
        }
        return nil
    }

    private static func extractGrayscale(from image: CGImage) -> LUT? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else {
            return nil
        }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var grayscale = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let idx = i * 4
            let r = UInt16(ptr[idx])
            let g = UInt16(ptr[idx + 1])
            let b = UInt16(ptr[idx + 2])
            grayscale[i] = UInt8((r + g + b) / 3)
        }
        return LUT(pixels: grayscale, width: w, height: h)
    }

    private static func edgesLUT() -> LUT? {
        _lutLock.lock()
        defer { _lutLock.unlock() }
        if let cached = _edgesLUT { return cached }
        let lut = loadLUT(named: "edgesASCII.png")
        _edgesLUT = lut
        return lut
    }

    private static func fillLUT() -> LUT? {
        _lutLock.lock()
        defer { _lutLock.unlock() }
        if let cached = _fillLUT { return cached }
        let lut = loadLUT(named: "fillASCII.png")
        _fillLUT = lut
        return lut
    }

    // MARK: - Edge Direction

    private enum EdgeDirection: Int {
        case vertical = 0   // |
        case horizontal = 1 // —
        case diagonal1 = 2  // one slash direction
        case diagonal2 = 3  // other slash direction
    }

    // MARK: - Main Entry

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
            width: width, height: height,
            previewBaseDimension: previewBaseDimension
        )
        let workWidth = workSize.width
        let workHeight = workSize.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let sourceCtx = CGContext(
            data: nil, width: workWidth, height: workHeight,
            bitsPerComponent: 8, bytesPerRow: workWidth * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        sourceCtx.interpolationQuality = workWidth == width && workHeight == height ? .none : .high
        sourceCtx.draw(image, in: CGRect(x: 0, y: 0, width: workWidth, height: workHeight))

        guard let outputCtx = CGContext(
            data: nil, width: workWidth, height: workHeight,
            bitsPerComponent: 8, bytesPerRow: workWidth * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        guard let sourceData = sourceCtx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: workWidth * workHeight * 4)
        let outputPixels = outputData.bindMemory(to: UInt8.self, capacity: workWidth * workHeight * 4)

        let cellSize = max(4, min(64, asciiParams.cellSize))
        let edgeBias = ShaderPrimitives.clamp01(asciiParams.edgeBias)
        let intensity = ShaderPrimitives.clamp01(params.intensity)
        let exposure = max(0.0, min(5.0, asciiParams.exposure))
        let attenuation = max(0.0, min(5.0, asciiParams.attenuation))
        let paletteSource = sourceImage ?? image

        // Resolve color mode to concrete values
        let colorState = resolveColorState(
            asciiParams: asciiParams, paletteSource: paletteSource
        )

        // Load LUTs. When the user supplies a custom character palette *or* a
        // font override, build the atlases via Core Text (same cache the GPU
        // path uses — CGImage side) rather than reading the baked PNGs.
        // Setting `fontName` alone (with characters == nil) falls back to the
        // classic palette rasterised in the chosen font — that's the point of
        // the font-picker feature.
        let edges: LUT?
        let fill: LUT?
        let hasCustomChars = (asciiParams.characters ?? "").isEmpty == false
        let hasCustomFont  = (asciiParams.fontName   ?? "").isEmpty == false
        let hiDetail       = asciiParams.highDetail
        // Route to runtime Core Text generation if *anything* is customised
        // OR the user wants hi-res. Pure-defaults state still reads the
        // baked pixel-art PNG, so toggling High Detail alone only changes
        // the cell size — it no longer swaps the glyph source (that only
        // happens if you also touch Characters or Font).
        if hasCustomChars || hasCustomFont || hiDetail {
            let charsForStyle = hasCustomChars ? asciiParams.characters! : " .:-=+*#%@"
            let style = ASCIIAtlasGenerator.Style(
                fillCharacters: charsForStyle,
                fontName: hasCustomFont ? asciiParams.fontName : nil,
                cellSize: hiDetail ? 16 : 8
            )
            if let edgesImg = try? ASCIIAtlasGenerator.atlasCGImage(for: style, kind: .edges),
               let fillImg  = try? ASCIIAtlasGenerator.atlasCGImage(for: style, kind: .fill) {
                edges = extractGrayscale(from: edgesImg)
                fill  = extractGrayscale(from: fillImg)
            } else {
                edges = nil
                fill  = nil
            }
        } else {
            edges = edgesLUT()
            fill  = fillLUT()
        }
        let hasLUTs = edges != nil && fill != nil

        // Pre-compute luminance buffer
        var luminanceBuffer = [Double](repeating: 0, count: workWidth * workHeight)
        for i in 0..<(workWidth * workHeight) {
            let idx = i * 4
            luminanceBuffer[i] = ShaderPrimitives.luminance(
                r: sourcePixels[idx], g: sourcePixels[idx + 1], b: sourcePixels[idx + 2]
            )
        }

        // Copy source into output for intensity blending
        memcpy(outputPixels, sourcePixels, workWidth * workHeight * 4)

        func lum(_ x: Int, _ y: Int) -> Double {
            let cx = max(0, min(workWidth - 1, x))
            let cy = max(0, min(workHeight - 1, y))
            return luminanceBuffer[cy * workWidth + cx]
        }

        for cellY in stride(from: 0, to: workHeight, by: cellSize) {
            try Task.checkCancellation()

            for cellX in stride(from: 0, to: workWidth, by: cellSize) {
                let xEnd = min(cellX + cellSize, workWidth)
                let yEnd = min(cellY + cellSize, workHeight)
                let cellW = xEnd - cellX
                let cellH = yEnd - cellY

                // Compute per-cell average luminance and color
                var lumSum = 0.0
                var rSum = 0.0, gSum = 0.0, bSum = 0.0
                var count = 0
                for y in cellY..<yEnd {
                    for x in cellX..<xEnd {
                        lumSum += lum(x, y)
                        let idx = (y * workWidth + x) * 4
                        rSum += Double(sourcePixels[idx])
                        gSum += Double(sourcePixels[idx + 1])
                        bSum += Double(sourcePixels[idx + 2])
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                let avgLum = lumSum / Double(count)
                let avgR = rSum / Double(count)
                let avgG = gSum / Double(count)
                let avgB = bSum / Double(count)

                // Detect edge direction using Sobel on luminance
                let edgeResult = detectEdgeDirection(
                    luminanceBuffer: luminanceBuffer,
                    width: workWidth, height: workHeight,
                    cellX: cellX, cellY: cellY,
                    cellW: cellW, cellH: cellH,
                    edgeBias: edgeBias
                )

                // Apply exposure, attenuation, and black level to luminance for fill lookup.
                // Invert is applied below as a fg/bg swap — flipping adjustedLum
                // here only affected fill-cell level selection, leaving edge
                // cells (the majority of edge-heavy images) unchanged.
                var adjustedLum = ShaderPrimitives.clamp01(
                    pow(avgLum * exposure, attenuation)
                )
                // Lift blacks: remap [0,1] → [blackLevel,1]
                let bl = asciiParams.blackLevel
                if bl > 0 { adjustedLum = bl + adjustedLum * (1.0 - bl) }

                // Determine foreground color for this cell
                let (rawFgR, rawFgG, rawFgB) = cellForegroundColor(
                    colorState: colorState,
                    avgR: avgR, avgG: avgG, avgB: avgB,
                    luminance: adjustedLum
                )
                let (rawBgR, rawBgG, rawBgB) = colorState.background
                // Invert = negative-image: swap ink and paper colours.
                let (fgR, fgG, fgB) = asciiParams.invert
                    ? (rawBgR, rawBgG, rawBgB) : (rawFgR, rawFgG, rawFgB)
                let (bgR, bgG, bgB) = asciiParams.invert
                    ? (rawFgR, rawFgG, rawFgB) : (rawBgR, rawBgG, rawBgB)

                // Render each pixel in the cell
                for y in cellY..<yEnd {
                    for x in cellX..<xEnd {
                        let localX = x - cellX
                        let localY = y - cellY

                        let glyphValue: Double
                        if hasLUTs {
                            glyphValue = sampleLUT(
                                edges: edges!, fill: fill!,
                                edgeDirection: edgeResult,
                                luminance: adjustedLum,
                                localX: localX, localY: localY,
                                cellW: cellW, cellH: cellH
                            )
                        } else {
                            glyphValue = proceduralGlyph(
                                luminance: adjustedLum,
                                localX: localX, localY: localY,
                                cellW: cellW, cellH: cellH
                            )
                        }

                        // lerp(background, foreground, glyphValue) — matching reference shader
                        let pr = bgR + (fgR - bgR) * glyphValue
                        let pg = bgG + (fgG - bgG) * glyphValue
                        let pb = bgB + (fgB - bgB) * glyphValue

                        let idx = (y * workWidth + x) * 4
                        outputPixels[idx] = ShaderPrimitives.mix(
                            sourcePixels[idx], ShaderPrimitives.clampByte(pr), intensity: intensity
                        )
                        outputPixels[idx + 1] = ShaderPrimitives.mix(
                            sourcePixels[idx + 1], ShaderPrimitives.clampByte(pg), intensity: intensity
                        )
                        outputPixels[idx + 2] = ShaderPrimitives.mix(
                            sourcePixels[idx + 2], ShaderPrimitives.clampByte(pb), intensity: intensity
                        )
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
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        // Nearest-neighbour upscale preserves the crisp pixel-art glyph
        // edges. `.high` bilinear smoothing blurred the binary atlas output
        // and made preview (rendered at work size, no upscale) diverge
        // from export (rendered at work size, then interpolated back up).
        finalCtx.interpolationQuality = .none
        finalCtx.draw(workResult, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let result = finalCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Color Resolution

    private struct ColorState {
        let mode: ColorMode
        let background: (Double, Double, Double)

        enum ColorMode {
            case flat(r: Double, g: Double, b: Double)
            case source
            case gradient(r1: Double, g1: Double, b1: Double, r2: Double, g2: Double, b2: Double)
        }
    }

    private static func resolveColorState(
        asciiParams: ASCIIShaderParams,
        paletteSource: CGImage
    ) -> ColorState {
        switch asciiParams.colorMode {
        case .manual(let fg, let bg):
            return ColorState(
                mode: .flat(r: fg.red * 255, g: fg.green * 255, b: fg.blue * 255),
                background: (bg.red * 255, bg.green * 255, bg.blue * 255)
            )
        case .dominantTwoTone(let flipped, let satShift, let lightShift):
            var (primary, secondary) = ColorExtractor.extractTwoDominantColors(from: paletteSource)
            if satShift != 0 || lightShift != 0 {
                primary = ShaderPrimitives.adjustColor(primary, saturationShift: satShift, lightnessShift: lightShift)
                secondary = ShaderPrimitives.adjustColor(secondary, saturationShift: satShift, lightnessShift: lightShift)
            }
            let fg = flipped ? secondary : primary
            let bg = flipped ? primary : secondary
            return ColorState(
                mode: .flat(r: fg.red * 255, g: fg.green * 255, b: fg.blue * 255),
                background: (bg.red * 255, bg.green * 255, bg.blue * 255)
            )
        case .source(let bg):
            return ColorState(
                mode: .source,
                background: (bg.red * 255, bg.green * 255, bg.blue * 255)
            )
        case .gradient(let c1, let c2, let bg):
            return ColorState(
                mode: .gradient(
                    r1: c1.red * 255, g1: c1.green * 255, b1: c1.blue * 255,
                    r2: c2.red * 255, g2: c2.green * 255, b2: c2.blue * 255
                ),
                background: (bg.red * 255, bg.green * 255, bg.blue * 255)
            )
        }
    }

    @inline(__always)
    private static func cellForegroundColor(
        colorState: ColorState,
        avgR: Double, avgG: Double, avgB: Double,
        luminance: Double
    ) -> (Double, Double, Double) {
        switch colorState.mode {
        case .flat(let r, let g, let b):
            return (r, g, b)
        case .source:
            return (avgR, avgG, avgB)
        case .gradient(let r1, let g1, let b1, let r2, let g2, let b2):
            let t = luminance
            return (
                r1 + (r2 - r1) * t,
                g1 + (g2 - g1) * t,
                b1 + (b2 - b1) * t
            )
        }
    }

    // MARK: - Edge Detection (Sobel)

    private static func detectEdgeDirection(
        luminanceBuffer: [Double],
        width: Int, height: Int,
        cellX: Int, cellY: Int,
        cellW: Int, cellH: Int,
        edgeBias: Double
    ) -> EdgeDirection? {
        // Sobel gradient across the cell
        var gxSum = 0.0
        var gySum = 0.0
        var edgeMagnitudeSum = 0.0

        func lum(_ x: Int, _ y: Int) -> Double {
            let cx = max(0, min(width - 1, x))
            let cy = max(0, min(height - 1, y))
            return luminanceBuffer[cy * width + cx]
        }

        for y in cellY..<(cellY + cellH) {
            for x in cellX..<(cellX + cellW) {
                // Sobel 3x3
                let tl = lum(x - 1, y - 1), tc = lum(x, y - 1), tr = lum(x + 1, y - 1)
                let ml = lum(x - 1, y),                          mr = lum(x + 1, y)
                let bl = lum(x - 1, y + 1), bc = lum(x, y + 1), br = lum(x + 1, y + 1)

                let gx = (-tl - 2.0 * ml - bl) + (tr + 2.0 * mr + br)
                let gy = (-tl - 2.0 * tc - tr) + (bl + 2.0 * bc + br)

                gxSum += gx
                gySum += gy
                edgeMagnitudeSum += sqrt(gx * gx + gy * gy)
            }
        }

        let sampleCount = Double(cellW * cellH)
        let avgMagnitude = edgeMagnitudeSum / sampleCount

        // Edge threshold based on edgeBias: higher bias = more sensitive to edges
        // Reference shader uses _EdgeThreshold as count of edge pixels in 8x8 tile.
        // We map edgeBias [0..1] to a magnitude threshold: 0 = never edge, 1 = very sensitive
        let threshold = 0.05 + (1.0 - edgeBias) * 0.35
        guard avgMagnitude > threshold else { return nil }

        // Determine dominant direction from accumulated gradient
        let theta = atan2(gySum, gxSum)
        let absTheta = abs(theta) / .pi

        if absTheta < 0.1 || absTheta > 0.9 {
            return .vertical
        } else if absTheta > 0.4 && absTheta < 0.6 {
            return .horizontal
        } else if theta > 0 {
            return absTheta < 0.5 ? .diagonal2 : .diagonal1
        } else {
            return absTheta < 0.5 ? .diagonal1 : .diagonal2
        }
    }

    // MARK: - LUT Sampling

    @inline(__always)
    private static func sampleLUT(
        edges: LUT, fill: LUT,
        edgeDirection: EdgeDirection?,
        luminance: Double,
        localX: Int, localY: Int,
        cellW: Int, cellH: Int
    ) -> Double {
        // Atlas cell size is derived from the LUT height — matches the
        // shader's `atlasCell = fillAtlas.get_height()`. Baked PNGs are 8 px,
        // High Detail runtime atlases are 16 px.
        let atlasCell = max(4, fill.height)
        let glyphX = (localX * atlasCell) / max(1, cellW)
        let glyphY = (localY * atlasCell) / max(1, cellH)
        let gx = min(atlasCell - 1, glyphX)
        let gy = min(atlasCell - 1, glyphY)

        if let direction = edgeDirection {
            // Edge glyph: offset = (direction + 1) * atlasCell, matching shader.
            let offset = (direction.rawValue + 1) * atlasCell
            return edges.sample(x: gx + offset, y: gy)
        } else {
            // Fill glyph: quantize luminance to 0-9, offset into the N-cell-
            // wide LUT (80 px baked / 160 px High Detail).
            let quantized = max(0, min(9, Int(floor(luminance * 9.999))))
            let offset = quantized * atlasCell
            return fill.sample(x: gx + offset, y: gy)
        }
    }

    // MARK: - Procedural Fallback

    private static let fallbackRamp: [[UInt8]] = {
        // 10-level brightness ramp as 5x7 bitmaps packed into bytes
        // Used only when LUT textures aren't available (e.g. tests, CLI)
        let patterns: [[String]] = [
            [".....", ".....", ".....", ".....", ".....", ".....", "....."],
            [".....", ".....", ".....", ".....", ".....", "..#..", "....."],
            [".....", ".#.#.", ".....", "..#..", ".....", ".#.#.", "....."],
            [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
            ["#...#", ".#.#.", "..#..", ".#.#.", "#...#", ".....", "....."],
            ["#...#", ".#.#.", "..#..", ".###.", "..#..", ".#.#.", "#...#"],
            [".###.", "#...#", "#.#.#", "#...#", "#.#.#", "#...#", ".###."],
            ["#####", "#.#.#", "#####", "#.#.#", "#####", "#.#.#", "#####"],
            ["#####", "##.##", "#####", ".###.", "#####", "##.##", "#####"],
            [".###.", "#####", "#####", "#####", "#####", "#####", ".###."],
        ]
        return patterns.map { rows in
            var bitmap = [UInt8]()
            for row in rows {
                for ch in row { bitmap.append(ch == "#" ? 1 : 0) }
            }
            return bitmap
        }
    }()

    @inline(__always)
    private static func proceduralGlyph(
        luminance: Double,
        localX: Int, localY: Int,
        cellW: Int, cellH: Int
    ) -> Double {
        let glyphIndex = max(0, min(fallbackRamp.count - 1, Int((luminance * Double(fallbackRamp.count - 1)).rounded())))
        let bitmap = fallbackRamp[glyphIndex]
        let glyphW = 5
        let glyphH = 7
        let gx = min(glyphW - 1, (localX * glyphW) / max(1, cellW))
        let gy = min(glyphH - 1, (localY * glyphH) / max(1, cellH))
        return Double(bitmap[gy * glyphW + gx])
    }

    // MARK: - Scale

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
