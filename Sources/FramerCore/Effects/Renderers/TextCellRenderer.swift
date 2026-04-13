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

        // Atlas textures are required by the shader. Fall back to CPU if
        // either is missing on disk — matches CPU's `hasLUTs` short-circuit.
        guard let edgesTexture = try MetalTextureSupport.loadLUTTexture(
                named: "edgesASCII.png", device: library.device),
              let fillTexture = try MetalTextureSupport.loadLUTTexture(
                named: "fillASCII.png", device: library.device)
        else {
            throw MetalEffectError.textureLoadFailed("edgesASCII.png / fillASCII.png")
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

        let uniformData = withUnsafeBytes(of: uniforms) { Data($0) }

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
