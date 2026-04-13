import Foundation
import CoreGraphics

public enum ShaderRenderer {
    public static func apply(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        try Task.checkCancellation()

        switch params.params {
        case .ascii:
            // GPU path (Phase 1 of the Effects bucket migration — see
            // docs/gpu-migration-plan.md). Falls back to the CPU renderer when
            // Metal is unavailable (no GPU device, missing LUT atlases, etc.)
            // so headless and pre-Metal hosts keep working.
            do {
                return try TextCellRenderer.renderASCII(
                    to: image,
                    params: params,
                    previewBaseDimension: previewBaseDimension,
                    sourceImage: sourceImage
                )
            } catch is MetalEffectError {
                return try ShaderASCIIRenderer.apply(
                    to: image,
                    params: params,
                    previewBaseDimension: previewBaseDimension,
                    sourceImage: sourceImage
                )
            }
        case .pixelSort:
            return try ShaderPixelSortRenderer.apply(to: image, params: params)
        case .crimewave(let shaderParams):
            return try applyCrimewave(to: image, params: shaderParams, intensity: params.intensity)
        case .narc(let shaderParams):
            return try applyNarc(to: image, params: shaderParams, intensity: params.intensity)
        case .shiba(let shaderParams):
            return try applyShiba(to: image, params: shaderParams, intensity: params.intensity)
        case .distantPast(let shaderParams):
            return try applyDistantPast(to: image, params: shaderParams, intensity: params.intensity)
        case .crt(let shaderParams):
            return try applyCRT(to: image, params: shaderParams, intensity: params.intensity)
        case .halftone(let shaderParams):
            return try applyHalftone(to: image, params: shaderParams, intensity: params.intensity)
        case .kuwahara(let shaderParams):
            return try applyKuwahara(to: image, params: shaderParams, intensity: params.intensity)
        }
    }

    private static func applyCrimewave(
        to image: CGImage,
        params: CrimewaveShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Boost contrast strongly
        ShaderPrimitives.adjustContrastAndCrush(pixels, width: width, height: height, contrast: params.contrast * 1.3)

        // Push neon: saturate then heavy channel bias toward cyan/magenta
        ShaderPrimitives.adjustSaturation(pixels, width: width, height: height, amount: 1.0 + params.neon * 1.6)
        ShaderPrimitives.applyChannelBias(
            pixels, width: width, height: height,
            red: params.neon * 20.0,
            green: -params.neon * 15.0,
            blue: params.neon * 40.0
        )

        // Softness
        if params.softness > 0 {
            ShaderPrimitives.applyBoxBlur(
                pixels, width: width, height: height,
                radius: max(1, Int((params.softness * 3).rounded())),
                mixAmount: params.softness * 0.8
            )
        }

        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: params.grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func applyNarc(
        to image: CGImage,
        params: NarcShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Strong contrast and crush for gritty look
        ShaderPrimitives.adjustContrastAndCrush(
            pixels, width: width, height: height,
            contrast: params.contrast * 1.4,
            crush: min(1.0, params.crush * 1.5 + 0.15)
        )

        // Temperature shift
        ShaderPrimitives.adjustTemperature(pixels, width: width, height: height, amount: params.temperature * 1.5)

        // Slight desaturation for washed-out look
        ShaderPrimitives.adjustSaturation(pixels, width: width, height: height, amount: 0.85)

        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: params.grain * 1.5)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    private static func applyShiba(
        to image: CGImage,
        params: ShibaShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Warm temperature shift — more pronounced
        ShaderPrimitives.adjustTemperature(pixels, width: width, height: height, amount: params.warmth * 1.8)

        // Strong saturation boost
        ShaderPrimitives.adjustSaturation(pixels, width: width, height: height, amount: 1.0 + params.saturation * 1.5)

        // Softness
        if params.softness > 0 {
            ShaderPrimitives.applyBoxBlur(
                pixels, width: width, height: height,
                radius: max(1, Int((params.softness * 3).rounded())),
                mixAmount: params.softness * 0.7
            )
        }

        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: params.grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)
        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    // Reference palette from AcerolaFX_DistantPast.ini PaletteSwap colors,
    // ordered by luminance (dark → light). These are the muted watercolor
    // tones that define the "distant past" look.
    private static let distantPastPalette: [(r: Double, g: Double, b: Double)] = [
        (0.411765, 0.414072, 0.490196),  // muted lavender
        (0.537255, 0.466667, 0.466667),  // dusty mauve
        (0.582237, 0.690196, 0.407843),  // olive green
        (0.668166, 0.752941, 0.560784),  // sage green
        (0.815917, 0.835294, 0.725490),  // pale cream
        (0.921569, 0.912534, 0.912534),  // pearl white
    ]

    private static func applyDistantPast(
        to image: CGImage,
        params: DistantPastShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let paletteCount = max(2, min(distantPastPalette.count, params.paletteDepth))
        let fade = ShaderPrimitives.clamp01(params.fade)
        let softness = ShaderPrimitives.clamp01(params.softness)
        let grain = ShaderPrimitives.clamp01(params.grain)

        // Build the active palette (evenly spaced subset of the full 6 colors)
        var palette: [(r: Double, g: Double, b: Double)] = []
        if paletteCount >= distantPastPalette.count {
            palette = distantPastPalette
        } else {
            for i in 0..<paletteCount {
                let t = Double(i) / Double(paletteCount - 1)
                let idx = min(distantPastPalette.count - 1, Int((t * Double(distantPastPalette.count - 1)).rounded()))
                palette.append(distantPastPalette[idx])
            }
        }

        // Step 1: Gentle color grading — warm desaturation with slight exposure lift.
        // Keep values moderate so the palette snap produces visible tonal separation.
        let warmShift = fade * 0.04
        let desatAmount = 1.0 - fade * 0.35

        for i in 0..<(width * height) {
            let idx = i * 4
            var r = Double(pixels[idx]) / 255.0
            var g = Double(pixels[idx + 1]) / 255.0
            var b = Double(pixels[idx + 2]) / 255.0

            // Warm shift
            r += warmShift
            b -= warmShift * 0.6

            // Desaturate toward luminance
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            r = lum + (r - lum) * desatAmount
            g = lum + (g - lum) * desatAmount
            b = lum + (b - lum) * desatAmount

            pixels[idx] = ShaderPrimitives.clampByte(max(0, min(1, r)) * 255.0)
            pixels[idx + 1] = ShaderPrimitives.clampByte(max(0, min(1, g)) * 255.0)
            pixels[idx + 2] = ShaderPrimitives.clampByte(max(0, min(1, b)) * 255.0)
        }

        // Step 2: Palette snap — map each pixel to the nearest palette color
        // using Euclidean distance in RGB (not just luminance). This preserves
        // the hue variation between palette entries instead of collapsing to bands.
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = Double(pixels[idx]) / 255.0
                let g = Double(pixels[idx + 1]) / 255.0
                let b = Double(pixels[idx + 2]) / 255.0

                // Add dither noise before snapping to reduce banding
                let noiseSeed = ((x &* 31) &+ (y &* 17) &+ ((x ^ y) &* 13)) & 255
                let noise = (Double(noiseSeed) / 255.0 - 0.5) * 0.06
                let nr = r + noise
                let ng = g + noise
                let nb = b + noise

                var bestIdx = 0
                var bestDist = Double.greatestFiniteMagnitude
                for pi in 0..<palette.count {
                    let pc = palette[pi]
                    let dr = nr - pc.r
                    let dg = ng - pc.g
                    let db = nb - pc.b
                    let dist = dr * dr + dg * dg + db * db
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = pi
                    }
                }

                let pc = palette[bestIdx]
                pixels[idx] = ShaderPrimitives.clampByte(pc.r * 255.0)
                pixels[idx + 1] = ShaderPrimitives.clampByte(pc.g * 255.0)
                pixels[idx + 2] = ShaderPrimitives.clampByte(pc.b * 255.0)
            }
        }

        // Step 3: Vignette
        if fade > 0.05 {
            let cx = Double(width) / 2.0
            let cy = Double(height) / 2.0
            let vigStr = fade * 0.8
            for y in 0..<height {
                for x in 0..<width {
                    let dx = (Double(x) - cx) / cx
                    let dy = (Double(y) - cy) / cy
                    let dist = dx * dx + dy * dy
                    let vignette = max(0, 1.0 - dist * vigStr * 0.4)
                    let idx = (y * width + x) * 4
                    pixels[idx] = ShaderPrimitives.clampByte(Double(pixels[idx]) * vignette)
                    pixels[idx + 1] = ShaderPrimitives.clampByte(Double(pixels[idx + 1]) * vignette)
                    pixels[idx + 2] = ShaderPrimitives.clampByte(Double(pixels[idx + 2]) * vignette)
                }
            }
        }

        // Step 4: Softness (blur)
        if softness > 0 {
            ShaderPrimitives.applyBoxBlur(
                pixels,
                width: width,
                height: height,
                radius: max(1, Int((softness * 3).rounded())),
                mixAmount: softness * 0.7
            )
        }

        // Step 5: Film grain
        ShaderPrimitives.addDeterministicGrain(pixels, width: width, height: height, amount: grain)
        ShaderPrimitives.enforcePremultipliedAlpha(pixels, width: width, height: height)

        return try mixStylizedContext(ctx, with: image, intensity: intensity)
    }

    // MARK: - CRT

    private static func applyCRT(
        to image: CGImage,
        params: CRTShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let sourceCtx = try ShaderPrimitives.renderToRGBAContext(image)
        let outputCtx = try ShaderPrimitives.makeRGBAContext(width: width, height: height)
        guard let sourceData = sourceCtx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let src = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let dst = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let curvature = max(1.0, params.curvature)
        let lineScale = Double(height) / pow(2.0, Double(max(0, min(4, params.lineSize))))
        let lineStr = max(0, params.lineStrength)
        let brightnessAdj = params.brightness
        let vignetteWidth = max(1.0, params.vignette)

        func sampleSource(nx: Double, ny: Double) -> (Double, Double, Double) {
            let sx = max(0, min(width - 1, Int((nx * Double(width)).rounded(.down))))
            let sy = max(0, min(height - 1, Int((ny * Double(height)).rounded(.down))))
            let idx = (sy * width + sx) * 4
            return (Double(src[idx]) / 255.0, Double(src[idx + 1]) / 255.0, Double(src[idx + 2]) / 255.0)
        }

        for y in 0..<height {
            try Task.checkCancellation()
            let ny = Double(y) / Double(height)
            for x in 0..<width {
                let nx = Double(x) / Double(width)

                // Barrel distortion
                var crtX = nx * 2.0 - 1.0
                var crtY = ny * 2.0 - 1.0
                let offsetX = crtY / curvature
                let offsetY = crtX / curvature
                crtX += crtX * offsetX * offsetX
                crtY += crtY * offsetY * offsetY
                let sampleX = crtX * 0.5 + 0.5
                let sampleY = crtY * 0.5 + 0.5

                let idx = (y * width + x) * 4

                // Out of bounds = black
                guard sampleX > 0 && sampleX < 1 && sampleY > 0 && sampleY < 1 else {
                    dst[idx] = 0; dst[idx + 1] = 0; dst[idx + 2] = 0; dst[idx + 3] = src[idx + 3]
                    continue
                }

                var (r, g, b) = sampleSource(nx: sampleX, ny: sampleY)

                // Scanlines — green channel uses sin, red/blue use cos (reference pattern)
                let scanPhase = ny * lineScale * 2.0
                g *= (sin(scanPhase) + 1.0) * 0.15 * lineStr + 1.0 + brightnessAdj
                r *= (cos(scanPhase) + 1.0) * 0.135 * lineStr + 1.0 + brightnessAdj
                b *= (cos(scanPhase) + 1.0) * 0.135 * lineStr + 1.0 + brightnessAdj

                // Vignette
                let vigX = vignetteWidth / Double(width)
                let vigY = vignetteWidth / Double(height)
                let vx = smoothstep(0, vigX, 1.0 - abs(crtX))
                let vy = smoothstep(0, vigY, 1.0 - abs(crtY))

                r = max(0, min(1, r)) * vx * vy
                g = max(0, min(1, g)) * vx * vy
                b = max(0, min(1, b)) * vx * vy

                dst[idx] = ShaderPrimitives.clampByte(r * 255.0)
                dst[idx + 1] = ShaderPrimitives.clampByte(g * 255.0)
                dst[idx + 2] = ShaderPrimitives.clampByte(b * 255.0)
                dst[idx + 3] = src[idx + 3]
            }
        }

        return try mixStylizedContext(outputCtx, with: image, intensity: intensity)
    }

    @inline(__always)
    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / max(0.0001, edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    // MARK: - Halftone

    private static func applyHalftone(
        to image: CGImage,
        params: HalftoneShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        let outputCtx = try ShaderPrimitives.makeRGBAContext(width: width, height: height)
        guard let sourceData = ctx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let src = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let dst = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let dotSize = max(0.1, params.dotSize)
        let contrastExp = max(0.1, params.contrast)
        let wf = Double(width)
        let hf = Double(height)

        // CMYK rotation angles (reference: cyan 15°, magenta 75°, yellow 0°, black 45°)
        let cyanAngle = 0.261799
        let magentaAngle = 1.309
        let blackAngle = 0.785398

        func halftonePattern(ux: Double, uy: Double, value: Double) -> Double {
            let pattern = (sin(ux * wf * dotSize) + sin(uy * hf * dotSize)) / 2.0
            return pattern < pow(max(0, min(1, value)), contrastExp) ? 1.0 : 0.0
        }

        func rotateUV(ux: Double, uy: Double, angle: Double) -> (Double, Double) {
            let c = cos(angle), s = sin(angle)
            return (ux * c - uy * s, ux * s + uy * c)
        }

        for y in 0..<height {
            try Task.checkCancellation()
            let uy = Double(y) / hf
            for x in 0..<width {
                let ux = Double(x) / wf
                let idx = (y * width + x) * 4
                let r = Double(src[idx]) / 255.0
                let g = Double(src[idx + 1]) / 255.0
                let b = Double(src[idx + 2]) / 255.0

                if params.monochrome {
                    // Simple B&W halftone based on luminance
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b
                    let (rx, ry) = rotateUV(ux: ux, uy: uy, angle: blackAngle)
                    let dot = halftonePattern(ux: rx, uy: ry, value: lum)
                    let v = ShaderPrimitives.clampByte(dot * 255.0)
                    dst[idx] = v; dst[idx + 1] = v; dst[idx + 2] = v
                } else {
                    // CMYK halftone (reference algorithm)
                    let k = min(1.0 - r, min(1.0 - g, 1.0 - b))
                    let invK = 1.0 - k
                    var c_val = 0.0, m_val = 0.0, y_val = 0.0
                    if invK > 0.001 {
                        c_val = (1.0 - r - k) / invK
                        m_val = (1.0 - g - k) / invK
                        y_val = (1.0 - b - k) / invK
                    }

                    let (cux, cuy) = rotateUV(ux: ux, uy: uy, angle: cyanAngle)
                    let cDot = halftonePattern(ux: cux, uy: cuy, value: c_val)

                    let (mux, muy) = rotateUV(ux: ux, uy: uy, angle: magentaAngle)
                    let mDot = halftonePattern(ux: mux, uy: muy, value: m_val)

                    let yDot = halftonePattern(ux: ux, uy: uy, value: y_val)

                    let (kux, kuy) = rotateUV(ux: ux, uy: uy, angle: blackAngle)
                    let kDot = halftonePattern(ux: kux, uy: kuy, value: k)

                    // CMY to RGB: subtract from white, then subtract K
                    let outR = max(0, min(1, 1.0 - cDot - kDot))
                    let outG = max(0, min(1, 1.0 - mDot - kDot))
                    let outB = max(0, min(1, 1.0 - yDot - kDot))

                    dst[idx] = ShaderPrimitives.clampByte(outR * 255.0)
                    dst[idx + 1] = ShaderPrimitives.clampByte(outG * 255.0)
                    dst[idx + 2] = ShaderPrimitives.clampByte(outB * 255.0)
                }
                dst[idx + 3] = src[idx + 3]
            }
        }

        return try mixStylizedContext(outputCtx, with: image, intensity: intensity)
    }

    // MARK: - Kuwahara

    private static func applyKuwahara(
        to image: CGImage,
        params: KuwaharaShaderParams,
        intensity: Double
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let ctx = try ShaderPrimitives.renderToRGBAContext(image)
        let outputCtx = try ShaderPrimitives.makeRGBAContext(width: width, height: height)
        guard let sourceData = ctx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let src = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let dst = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let radius = max(1, min(15, params.kernelSize))
        let sharpness = max(0, params.sharpness)

        // Basic Kuwahara: split neighborhood into 4 quadrants,
        // pick the quadrant with lowest variance, output its mean color.
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                var bestVariance = Double.greatestFiniteMagnitude
                var bestR = 0.0, bestG = 0.0, bestB = 0.0

                // Four quadrants: top-left, top-right, bottom-left, bottom-right
                for qy in 0...1 {
                    for qx in 0...1 {
                        let startX = qx == 0 ? x - radius : x
                        let endX = qx == 0 ? x : x + radius
                        let startY = qy == 0 ? y - radius : y
                        let endY = qy == 0 ? y : y + radius

                        var sumR = 0.0, sumG = 0.0, sumB = 0.0
                        var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
                        var count = 0.0

                        for ky in startY...endY {
                            let cy = max(0, min(height - 1, ky))
                            for kx in startX...endX {
                                let cx = max(0, min(width - 1, kx))
                                let idx = (cy * width + cx) * 4
                                let r = Double(src[idx])
                                let g = Double(src[idx + 1])
                                let b = Double(src[idx + 2])
                                sumR += r; sumG += g; sumB += b
                                sumR2 += r * r; sumG2 += g * g; sumB2 += b * b
                                count += 1.0
                            }
                        }

                        let meanR = sumR / count
                        let meanG = sumG / count
                        let meanB = sumB / count
                        let variance = (sumR2 / count - meanR * meanR)
                            + (sumG2 / count - meanG * meanG)
                            + (sumB2 / count - meanB * meanB)

                        if variance < bestVariance {
                            bestVariance = variance
                            bestR = meanR; bestG = meanG; bestB = meanB
                        }
                    }
                }

                let idx = (y * width + x) * 4

                // Unsharp mask: blend between Kuwahara (smooth) and sharpened
                // sharpened = original + (original - smooth) * sharpness_factor
                if sharpness > 0 {
                    let factor = sharpness / 8.0
                    let origR = Double(src[idx])
                    let origG = Double(src[idx + 1])
                    let origB = Double(src[idx + 2])
                    bestR = bestR + (origR - bestR) * factor
                    bestG = bestG + (origG - bestG) * factor
                    bestB = bestB + (origB - bestB) * factor
                }

                dst[idx] = ShaderPrimitives.clampByte(bestR)
                dst[idx + 1] = ShaderPrimitives.clampByte(bestG)
                dst[idx + 2] = ShaderPrimitives.clampByte(bestB)
                dst[idx + 3] = src[idx + 3]
            }
        }

        return try mixStylizedContext(outputCtx, with: image, intensity: intensity)
    }

    private static func mixStylizedContext(
        _ stylizedContext: CGContext,
        with originalImage: CGImage,
        intensity: Double
    ) throws -> CGImage {
        guard let stylized = stylizedContext.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let width = originalImage.width
        let height = originalImage.height
        let originalCtx = try ShaderPrimitives.renderToRGBAContext(originalImage)
        let stylizedCtx = try ShaderPrimitives.renderToRGBAContext(stylized)
        let mixedCtx = try ShaderPrimitives.renderToRGBAContext(originalImage)
        guard
            let originalData = originalCtx.data,
            let stylizedData = stylizedCtx.data,
            let mixedData = mixedCtx.data
        else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let originalPixels = originalData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let stylizedPixels = stylizedData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let mixedPixels = mixedData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for i in 0..<(width * height) {
            let idx = i * 4
            mixedPixels[idx] = ShaderPrimitives.mix(originalPixels[idx], stylizedPixels[idx], intensity: intensity)
            mixedPixels[idx + 1] = ShaderPrimitives.mix(originalPixels[idx + 1], stylizedPixels[idx + 1], intensity: intensity)
            mixedPixels[idx + 2] = ShaderPrimitives.mix(originalPixels[idx + 2], stylizedPixels[idx + 2], intensity: intensity)
            mixedPixels[idx + 3] = originalPixels[idx + 3]
        }

        guard let result = mixedCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }
}
