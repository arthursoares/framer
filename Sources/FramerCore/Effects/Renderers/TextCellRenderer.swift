// TextCellRenderer.swift
// GPU front door for the TextCell effect bucket. Phase 1 only wires the ASCII
// variant; Dots / Blockify / MatrixRain still take the existing CPU paths
// elsewhere in FramerCore (and will move here in Phase 2 of the migration).
//
// The public API mirrors `ShaderASCIIRenderer.apply` so callers can swap in
// the GPU path with no signature change. `ShaderRenderer.swift` dispatches
// `.ascii` through here and falls back to the CPU renderer when Metal is
// unavailable (e.g. headless CI without `MTLCreateSystemDefaultDevice()`).
//
// See:
//   - Sources/FramerCore/Effects/Metal/TextCell.metal           (asciiVariant)
//   - Sources/FramerCore/Processing/ShaderASCIIRenderer.swift   (CPU reference)
//   - docs/gpu-migration-plan.md                                 (Phase 1)

import Foundation
import CoreGraphics
import Metal

public enum TextCellRenderer {

    // MARK: - Uniform layout (mirrors TextCellUniforms in TextCell.metal)
    //
    // CRITICAL: field order, type, and explicit padding must match the MSL
    // struct exactly. Drift here causes garbage uniform reads that are
    // miserable to debug. When TextCell.metal changes, update this together.

    private struct FramerCommonUniforms {
        var brightness: Float = 0
        var contrast: Float = 0
        var saturation: Float = 1
        var hueRotation: Float = 0
        var sharpness: Float = 0
        var gamma: Float = 1
    }

    private struct FramerGeometryUniforms {
        var scale: Float = 1
        var spacing: Float = 1
        var outputWidth: Float = 0
        var _pad: Float = 0
    }

    private struct FramerColorUniforms {
        var mode: UInt32 = 0
        var backgroundIntensity: Float = 1
        var _pad0: Float = 0
        var _pad1: Float = 0
        var foregroundRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
        var backgroundRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)
    }

    private struct TextCellUniforms {
        var common = FramerCommonUniforms()
        var geometry = FramerGeometryUniforms()
        var color = FramerColorUniforms()

        var variant: UInt32 = 2          // 2 = ascii
        var dotShape: UInt32 = 0
        var gridType: UInt32 = 0
        var blockStyle: UInt32 = 0

        var sizeMultiplier: Float = 1
        var intensity: Float = 1
        var invert: UInt32 = 0
        var borderWidth: Float = 0

        var threshold: Float = 0
        var glow: Float = 0
        var backgroundOpacity: Float = 1
        var _pad0: Float = 0

        // ASCII-specific
        var cellSize: Float = 10
        var edgeBias: Float = 0.5
        var exposure: Float = 1
        var attenuation: Float = 1
        var blackLevel: Float = 0
        var asciiColorMode: UInt32 = 0
        var _pad1: Float = 0
        var _pad2: Float = 0

        var asciiForegroundRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
        var asciiBackgroundRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)
        var gradientStartRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)
        var gradientEndRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    }

    // MARK: - ASCII entry point

    /// Render the ASCII effect on the GPU. Mirrors `ShaderASCIIRenderer.apply`
    /// signature so callers can swap implementations transparently.
    ///
    /// - Returns: A new CGImage with the effect applied. Falls back to throwing
    ///   if Metal is unavailable or the LUT atlases can't be loaded — the
    ///   caller decides whether to retry on the CPU path.
    public static func renderASCII(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        guard case .ascii(let asciiParams) = params.params else {
            return image
        }

        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        // Atlas textures are required by the shader. When the user supplies
        // a custom character palette, generate atlases via Core Text at
        // runtime (cached by Style); otherwise fall back to the baked PNGs
        // in Bundle.module (FileManager + CGImageSourceCreate path).
        let edgesTexture: MTLTexture
        let fillTexture: MTLTexture
        if let chars = asciiParams.characters, !chars.isEmpty {
            let style = ASCIIAtlasGenerator.Style(fillCharacters: chars)
            let atlases = try ASCIIAtlasGenerator.atlases(for: style, device: library.device)
            edgesTexture = atlases.edges
            fillTexture  = atlases.fill
        } else {
            guard let edges = try MetalTextureSupport.loadLUTTexture(
                    named: "edgesASCII.png", device: library.device),
                  let fill  = try MetalTextureSupport.loadLUTTexture(
                    named: "fillASCII.png", device: library.device)
            else {
                throw MetalEffectError.textureLoadFailed("edgesASCII.png / fillASCII.png")
            }
            edgesTexture = edges
            fillTexture  = fill
        }

        // Compute the work-size the same way the CPU path does so the cell
        // grid lands on identical pixel boundaries (necessary for parity tests).
        let workSize = scaledWorkSize(
            width: image.width,
            height: image.height,
            previewBaseDimension: previewBaseDimension
        )

        let pipeline = try library.pipeline(for: "textCellFragment")
        // Nearest-clamp sampling matches the CPU path (which indexes exact
        // pixels) and gives crisp atlas glyph reads.
        let sampler = try library.nearestClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: image, device: library.device)

        let uniforms = makeUniforms(
            asciiParams: asciiParams,
            intensity: params.intensity,
            paletteSource: sourceImage ?? image
        )

        let uniformData = uniformBytes(uniforms)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [edgesTexture, fillTexture],
            sampler: sampler,
            uniformBytes: uniformData,
            outputSize: (workSize.width, workSize.height),
            library: library
        )

        let workImage = try MetalTextureSupport.makeCGImage(from: outputTexture)

        // If we rendered at a reduced preview size, scale back up so the
        // returned image matches the input dimensions (CPU path does the same).
        if workSize.width == image.width && workSize.height == image.height {
            return workImage
        }
        return try resize(workImage, to: image.width, height: image.height)
    }

    // MARK: - Dots entry point (.gpuEffect.textCell bucket)

    /// Render the Dots variant on the GPU via the bucket-system parameter
    /// surface. Shares the same `textCellFragment` pipeline as ASCII; the
    /// variant=0 branch in TextCell.metal::dotsVariant handles the geometry.
    /// Throws `MetalEffectError` on Metal failure so the caller's
    /// `gpuOrCPU` helper can fall back to the CPU paintEllipse / paintRect /
    /// paintDiamond path.
    public static func renderDotsFromBucket(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: TextCellParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "textCellFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        let uniforms = makeDotsUniforms(
            common: common,
            geometry: geometry,
            color: color,
            params: params
        )
        let uniformData = uniformBytes(uniforms)

        // The ASCII atlases are bound at texture slots 1 and 2 for variant=2;
        // for variant=0 (dots) the shader ignores them but the bindings must
        // still be valid textures. Reuse the source texture as placeholders.
        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [sourceTexture, sourceTexture],
            sampler: sampler,
            uniformBytes: uniformData,
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Blockify entry point (.gpuEffect.textCell bucket)

    /// Render the Blockify variant on the GPU via the bucket-system parameter
    /// surface. Shares the `textCellFragment` pipeline with dots + ASCII; the
    /// variant=1 branch in TextCell.metal::blockifyVariant handles the
    /// rectangle drawing. Throws MetalEffectError on Metal failure.
    public static func renderBlockifyFromBucket(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: TextCellParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "textCellFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = makeDotsUniforms(
            common: common,
            geometry: geometry,
            color: color,
            params: params
        )
        uniforms.variant = 1                                        // 1 = blockify
        uniforms.blockStyle = UInt32(blockStyleRawValue(params.blockStyle))
        let uniformData = uniformBytes(uniforms)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [sourceTexture, sourceTexture],           // dummy atlas binds
            sampler: sampler,
            uniformBytes: uniformData,
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    private static func blockStyleRawValue(_ style: BlockStyle) -> Int {
        switch style {
        case .solid:    return 0
        case .outlined: return 1
        }
    }

    private static func makeDotsUniforms(
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: TextCellParameters
    ) -> TextCellUniforms {
        var u = TextCellUniforms()

        // Common / geometry / color blocks — map bucket params into the
        // shared uniform layouts MSL's TextCellUniforms embeds.
        u.common.brightness  = Float(common.brightness)
        u.common.contrast    = Float(common.contrast)
        u.common.saturation  = Float(common.saturation)
        u.common.hueRotation = Float(common.hueRotation)
        u.common.sharpness   = Float(common.sharpness)
        u.common.gamma       = Float(common.gamma)

        u.geometry.scale       = Float(geometry.scale)
        u.geometry.spacing     = Float(max(0.5, geometry.spacing))
        u.geometry.outputWidth = Float(geometry.outputWidth)

        u.color.mode = {
            switch color.mode {
            case .source:               return 0
            case .foregroundBackground: return 1
            case .monochrome:           return 2
            case .palette:              return 3
            }
        }()
        u.color.backgroundIntensity = Float(color.backgroundIntensity)

        // TextCellParameters carries its own fg/bg overrides which take
        // precedence over the shared color block when present. This matches
        // the convention used elsewhere in the bucket renderers.
        if let fg = params.foreground {
            u.color.foregroundRGBA = simdColor(fg)
        }
        if let bg = params.background {
            u.color.backgroundRGBA = simdColor(bg)
        }

        // Variant-specific.
        u.variant = 0                                              // 0 = dots
        u.dotShape = UInt32(dotShapeRawValue(params.dotShape))
        u.gridType = UInt32(gridTypeRawValue(params.gridType))
        u.blockStyle = 0                                            // unused for dots

        u.sizeMultiplier     = 1.0                                 // baseline; the shader multiplies by 0.4
        u.intensity          = Float(clamp01(params.intensity))
        u.invert             = params.invert ? 1 : 0
        u.borderWidth        = Float(params.borderWidth)
        u.threshold          = Float(clamp01(params.threshold))
        u.glow               = Float(clamp01(params.glow))
        u.backgroundOpacity  = Float(clamp01(params.backgroundOpacity))
        return u
    }

    // MARK: - Matrix Rain entry point (.gpuEffect.textCell bucket)

    /// Render Matrix Rain on the GPU via the bucket-system parameter surface.
    /// Reuses the textCellFragment pipeline (variant=3). Several
    /// TextCellUniforms fields are repurposed so the same MSL struct can
    /// carry matrixRain-specific data without growing the uniform block:
    ///   - `backgroundOpacity` → time/phase-scrub (drives per-column offset)
    ///   - `threshold`         → trail length (as fraction of axis dimension)
    ///   - `glow`              → leading-glyph brightness
    ///   - `dotShape`          → direction (0 = down, 1 = right)
    ///   - `asciiForegroundRGBA` → rain colour tint (defaults green if unset)
    /// See Sources/FramerCore/Effects/Metal/TextCell.metal::matrixRainVariant
    /// for the per-pixel pipeline.
    public static func renderMatrixRainFromBucket(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: TextCellParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }
        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "textCellFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = makeDotsUniforms(common: common, geometry: geometry, color: color, params: params)
        uniforms.variant           = 3                                     // matrixRain
        uniforms.dotShape          = (params.direction == .left || params.direction == .right) ? 1 : 0
        uniforms.glow              = Float(clamp01(params.glow))
        uniforms.threshold         = Float(clamp01(max(0.1, params.trailLength)))
        uniforms.backgroundOpacity = Float(clamp01(params.speed))          // phase-scrub
        uniforms.color.backgroundIntensity = Float(clamp01(params.backgroundOpacity))
        if let rainColor = params.rainColor {
            uniforms.asciiForegroundRGBA = simdColor(rainColor)
        } else {
            uniforms.asciiForegroundRGBA = SIMD4(0.1, 1.0, 0.3, 1.0)       // classic Matrix green
        }

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [sourceTexture, sourceTexture],                   // dummy atlas binds
            sampler: sampler,
            uniformBytes: uniformBytes(uniforms),
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    private static func dotShapeRawValue(_ shape: DotShape) -> Int {
        switch shape {
        case .circle:  return 0
        case .square:  return 1
        case .diamond: return 2
        }
    }

    private static func gridTypeRawValue(_ grid: DotGridType) -> Int {
        switch grid {
        case .square: return 0
        case .hex:    return 1
        }
    }

    // MARK: - Uniform packing

    private static func makeUniforms(
        asciiParams: ASCIIShaderParams,
        intensity: Double,
        paletteSource: CGImage
    ) -> TextCellUniforms {
        var u = TextCellUniforms()
        u.variant = 2
        u.cellSize = Float(max(4, min(64, asciiParams.cellSize)))
        u.edgeBias = Float(clamp01(asciiParams.edgeBias))
        u.exposure = Float(max(0.0, min(5.0, asciiParams.exposure)))
        u.attenuation = Float(max(0.0, min(5.0, asciiParams.attenuation)))
        u.blackLevel = Float(clamp01(asciiParams.blackLevel))
        u.invert = asciiParams.invert ? 1 : 0
        u.intensity = Float(clamp01(intensity))

        // Resolve the colour mode CPU-side. The shader only supports three
        // concrete modes: flat (0), source (1), gradient (2). dominantTwoTone
        // resolves to flat after running the colour extractor here.
        switch asciiParams.colorMode {
        case .manual(let foreground, let background):
            u.asciiColorMode = 0
            u.asciiForegroundRGBA = simdColor(foreground)
            u.asciiBackgroundRGBA = simdColor(background)

        case .dominantTwoTone(let flipped, let satShift, let lightShift):
            var (primary, secondary) = ColorExtractor.extractTwoDominantColors(from: paletteSource)
            if satShift != 0 || lightShift != 0 {
                primary = ShaderPrimitives.adjustColor(
                    primary, saturationShift: satShift, lightnessShift: lightShift
                )
                secondary = ShaderPrimitives.adjustColor(
                    secondary, saturationShift: satShift, lightnessShift: lightShift
                )
            }
            let fg = flipped ? secondary : primary
            let bg = flipped ? primary : secondary
            u.asciiColorMode = 0
            u.asciiForegroundRGBA = simdColor(fg)
            u.asciiBackgroundRGBA = simdColor(bg)

        case .source(let background):
            u.asciiColorMode = 1
            u.asciiBackgroundRGBA = simdColor(background)

        case .gradient(let color1, let color2, let background):
            u.asciiColorMode = 2
            u.gradientStartRGBA = simdColor(color1)
            u.gradientEndRGBA = simdColor(color2)
            u.asciiBackgroundRGBA = simdColor(background)
        }

        return u
    }

    @inline(__always)
    private static func simdColor(_ color: CodableColor) -> SIMD4<Float> {
        SIMD4(Float(color.red), Float(color.green), Float(color.blue), 1)
    }

    @inline(__always)
    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    // MARK: - Work-size scaling (matches ShaderASCIIRenderer.scaledWorkSize)

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

    // MARK: - Final upscale to original dimensions

    private static func resize(_ image: CGImage, to width: Int, height: Int) throws -> CGImage {
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
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }
}
