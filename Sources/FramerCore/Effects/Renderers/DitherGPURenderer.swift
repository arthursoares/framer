// DitherGPURenderer.swift
// GPU dither implementation. Mirrors DitherRenderer.apply signature so
// callers can swap in the GPU path transparently. Falls back to CPU for:
//   - Riemersma (Hilbert-curve traversal — inherently serial, no GPU port)
//   - dominantTwoTone colour mode for the colour extraction step (the dither
//     itself runs GPU; the dominant-colour resolution happens CPU-side and
//     the resolved colours are passed in as the foreground/background)
//
// Pixel-scale handling matches the CPU pipeline exactly:
//   1. Downscale source to (work_width, work_height) with bilinear (.high
//      interpolation) when scale > 1.
//   2. Run the dither pass at work resolution.
//   3. Upscale to the original dimensions with nearest-neighbour for chunky
//      pixels.

import Foundation
import CoreGraphics
import Metal

public enum DitherGPURenderer {

    // MARK: - Algorithm IDs (mirror Dither.metal constants)

    private enum AlgorithmID: UInt32 {
        case bayer = 0
        case floydSteinberg = 1
        case atkinson = 2
        case blueNoise = 3
        case artisticDrip = 4
        case halftone = 5
        case stucki = 6
        case whiteNoise = 7
        // 8 reserved for riemersma — deliberately not represented; Swift forces CPU fallback
        case sierra = 9
        case sierraTwoRow = 10
        case sierraLite = 11
        case jarvisJudiceNinke = 12
        case burkes = 13
        case interleavedGradientNoise = 14
        case cmykHalftone = 15

        init?(_ algorithm: DitherAlgorithm) {
            switch algorithm {
            case .bayer:                    self = .bayer
            case .floydSteinberg:           self = .floydSteinberg
            case .atkinson:                 self = .atkinson
            case .blueNoise:                self = .blueNoise
            case .artisticDrip:             self = .artisticDrip
            case .halftone:                 self = .halftone
            case .stucki:                   self = .stucki
            case .whiteNoise:               self = .whiteNoise
            case .riemersma:                return nil
            case .sierra:                   self = .sierra
            case .sierraTwoRow:             self = .sierraTwoRow
            case .sierraLite:               self = .sierraLite
            case .jarvisJudiceNinke:        self = .jarvisJudiceNinke
            case .burkes:                   self = .burkes
            case .interleavedGradientNoise: self = .interleavedGradientNoise
            case .cmykHalftone:             self = .cmykHalftone
            }
        }
    }

    // MARK: - Uniform layout (mirrors DitherUniforms in Dither.metal)

    /// Hard cap on uploaded palette colours. Mirrors `DITHER_MAX_PALETTE` in
    /// Dither.metal and `DitherColorMode.MAX_PALETTE_COLORS` in the model.
    /// All three constants must move together.
    private static let MAX_PALETTE_COLORS = 16

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var algorithm: UInt32 = 0
        var bayerLevel: UInt32 = 2
        var colorMode: UInt32 = 0           // 0 mono, 1 levels, 2 palette
        var colorLevels: UInt32 = 4

        var threshold: Float = 0.5
        var sharpenAmount: Float = 0
        var contrastAmount: Float = 0
        var _pad0: Float = 0

        var foregroundRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
        var backgroundRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)
        var useTwoTone: UInt32 = 0
        var paletteCount: UInt32 = 0
        var _pad2: Float = 0
        var _pad3: Float = 0

        // 16 × float4 = 256 bytes. Slot order matches MSL palette[] indexing.
        var palette: (
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
        ) = (
            SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0),
            SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0),
            SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0),
            SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0)
        )

        mutating func setPalette(_ colors: [SIMD4<Float>]) {
            // Clamp to capacity. `DitherColorMode.palette` already truncates
            // on decode so this is mostly defensive.
            let n = min(colors.count, DitherGPURenderer.MAX_PALETTE_COLORS)
            for i in 0..<n {
                switch i {
                case 0:  palette.0  = colors[i]
                case 1:  palette.1  = colors[i]
                case 2:  palette.2  = colors[i]
                case 3:  palette.3  = colors[i]
                case 4:  palette.4  = colors[i]
                case 5:  palette.5  = colors[i]
                case 6:  palette.6  = colors[i]
                case 7:  palette.7  = colors[i]
                case 8:  palette.8  = colors[i]
                case 9:  palette.9  = colors[i]
                case 10: palette.10 = colors[i]
                case 11: palette.11 = colors[i]
                case 12: palette.12 = colors[i]
                case 13: palette.13 = colors[i]
                case 14: palette.14 = colors[i]
                case 15: palette.15 = colors[i]
                default: break
                }
            }
            paletteCount = UInt32(n)
        }
    }

    // MARK: - Public entry

    /// GPU dither. Mirrors `DitherRenderer.apply` signature.
    /// Throws `MetalEffectError` on any GPU failure or for algorithms the GPU
    /// path doesn't implement (currently: Riemersma) — callers handle the
    /// fallback.
    public static func apply(
        to image: CGImage,
        params: DitherLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }
        guard let algoID = AlgorithmID(params.algorithm) else {
            // Riemersma — force CPU fallback.
            throw MetalEffectError.metalUnavailable
        }

        let width = image.width
        let height = image.height

        // Match CPU's pixel-scale handling exactly so preview / export sizes
        // and dither cell counts agree.
        let scale: Int
        if params.pixelScale > 1, let previewBase = previewBaseDimension {
            let currentMax = max(width, height)
            scale = max(1, min(32, Int(round(
                Double(currentMax) * Double(params.pixelScale) / Double(previewBase)
            ))))
        } else {
            scale = max(1, min(8, params.pixelScale))
        }
        let workW = scale > 1 ? max(1, width / scale) : width
        let workH = scale > 1 ? max(1, height / scale) : height

        // 1. Downscale CPU-side when needed (CIContext upload via MTKTextureLoader
        //    handles full-resolution efficiently, but reduced resolution is
        //    cheaper and matches CPU output-grid spacing exactly).
        let workImage: CGImage
        if scale > 1 {
            workImage = try resize(image, to: workW, height: workH, quality: .high)
        } else {
            workImage = image
        }

        // 2. Resolve colour mode. dominantTwoTone resolves CPU-side via
        //    ColorExtractor; the shader only sees flat fg/bg.
        let resolvedColors = resolveColors(
            colorMode: params.colorMode,
            paletteSource: sourceImage ?? image
        )

        // 3. Pack uniforms.
        var uniforms = Uniforms()
        uniforms.algorithm = algoID.rawValue
        uniforms.bayerLevel = UInt32(max(1, min(4, params.bayerLevel)))
        uniforms.threshold = Float(max(0.1, min(0.9, params.threshold)))
        uniforms.sharpenAmount = Float(max(0.0, min(1.0, params.sharpen)))
        uniforms.contrastAmount = Float(max(0.0, min(1.0, params.contrast)))

        switch resolvedColors {
        case .bw:
            uniforms.colorMode = 0
            uniforms.useTwoTone = 0

        case .twoTone(let fg, let bg):
            uniforms.colorMode = 0
            uniforms.useTwoTone = 1
            uniforms.foregroundRGBA = simdColor(fg)
            uniforms.backgroundRGBA = simdColor(bg)

        case .levels(let n):
            uniforms.colorMode = 1
            uniforms.colorLevels = UInt32(max(2, min(8, n)))

        case .palette(let colors):
            // Empty palette → fall back to bw mode rather than uploading
            // garbage. Should be impossible (decoder rejects empty palettes)
            // but keeps the GPU defensive.
            guard !colors.isEmpty else {
                uniforms.colorMode = 0
                uniforms.useTwoTone = 0
                break
            }
            uniforms.colorMode = 2
            let simdPalette = colors.prefix(Self.MAX_PALETTE_COLORS).map { simdColor($0) }
            uniforms.setPalette(simdPalette)
        }

        // 4. Run the GPU pass at work resolution.
        let pipeline = try library.pipeline(for: "ditherFragment")
        // Linear sampling for the sharpen pre-pass; nearest in the algorithms
        // themselves (which read at integer pixel positions via the uv
        // unproject above).
        let sampler = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: workImage, device: library.device)

        let bytes = uniformBytes(uniforms)
        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: bytes,
            outputSize: (workW, workH),
            library: library
        )
        let dithered = try MetalTextureSupport.makeCGImage(from: outputTexture)

        // 5. Upscale back to original dimensions with nearest-neighbour for
        //    chunky pixels (matches CPU path).
        if scale > 1 {
            return try resize(dithered, to: width, height: height, quality: .none)
        }
        return dithered
    }

    // MARK: - Colour mode resolution

    private enum ResolvedColors {
        case bw
        case twoTone(fg: CodableColor, bg: CodableColor)
        case levels(Int)
        case palette([CodableColor])
    }

    private static func resolveColors(
        colorMode: DitherColorMode,
        paletteSource: CGImage
    ) -> ResolvedColors {
        switch colorMode {
        case .bw:
            return .bw
        case .twoTone(let fg, let bg):
            return .twoTone(fg: fg, bg: bg)
        case .dominantTwoTone(let flipped, let satShift, let lightShift):
            var (primary, secondary) = ColorExtractor.extractTwoDominantColors(from: paletteSource)
            if satShift != 0 || lightShift != 0 {
                primary = ShaderPrimitives.adjustColor(primary,
                                                       saturationShift: satShift,
                                                       lightnessShift: lightShift)
                secondary = ShaderPrimitives.adjustColor(secondary,
                                                         saturationShift: satShift,
                                                         lightnessShift: lightShift)
            }
            let fg = flipped ? secondary : primary
            let bg = flipped ? primary : secondary
            return .twoTone(fg: fg, bg: bg)
        case .color(let levels):
            return .levels(levels)
        case .palette(let colors):
            return .palette(colors)
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func simdColor(_ c: CodableColor) -> SIMD4<Float> {
        SIMD4(Float(c.red), Float(c.green), Float(c.blue), 1)
    }

    private static func resize(
        _ image: CGImage,
        to width: Int,
        height: Int,
        quality: CGInterpolationQuality
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        context.interpolationQuality = quality
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }
}
