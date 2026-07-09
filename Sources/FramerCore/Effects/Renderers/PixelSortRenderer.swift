// PixelSortRenderer.swift
// Swift wrapper for PixelSort.metal. Pre-multiplies the blend intensity
// (`params.intensity * pixelSortParams.amount`) the same way the CPU path does,
// converts the direction enum to the uint the shader switches on, and clamps
// the span to the same 1..256 range.
//
// Note on span sampling: spans ≤ 24 read every pixel in the span, so the
// rank lookup is exact. Spans > 24 are sub-sampled by the shader (the
// 24-sample approximation from grainrad/notes/pixel-sort.md) — a deliberate
// quality/speed tradeoff for long streaks. This is the only pixel-sort
// implementation: the exact-rank CPU sorter was retired with the CPU effect
// path (docs/adr/2026-07-09-retire-cpu-effect-path.md).

import Foundation
import CoreGraphics
import Metal

public enum PixelSortRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var threshold: Float = 0
        var direction: UInt32 = 0     // 0 horizontal, 1 vertical, 2 diagonal
        var spanCap: Int32 = 24

        var widthPx: Float = 0
        var heightPx: Float = 0
        var spanMode: UInt32 = 0      // 0 luminance, 1..4 Kim Asendorf
        var reverse: UInt32 = 0       // 0/1

        var randomness: Float = 0
        var sortBy: UInt32 = 0        // 0 luminance, 1 brightness, 2 hue
        var _pad0: Float = 0
        var _pad1: Float = 0
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .pixelSort(let ps) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        // CPU pre-multiplies intensity * amount and clamps to 0..1; mirror it
        // so the GPU and CPU agree on the final blend factor.
        uniforms.intensity = Float(max(0.0, min(1.0, params.intensity * ps.amount)))
        uniforms.threshold = Float(max(0.0, min(1.0, ps.threshold)))
        uniforms.direction = directionID(ps.direction)
        uniforms.spanCap = Int32(max(1, min(256, ps.span)))
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)
        uniforms.spanMode = spanModeID(ps.spanMode)
        uniforms.reverse = ps.reverse ? 1 : 0
        uniforms.randomness = Float(max(0.0, min(1.0, ps.randomness)))
        uniforms.sortBy     = sortByID(ps.sortBy)

        let pipeline = try library.pipeline(for: "pixelSortFragment")
        // Nearest sampling — span detection compares per-pixel luminance and
        // bilinear interpolation would smear span boundaries.
        let sampler = try library.nearestClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: image, device: library.device)

        let bytes = uniformBytes(uniforms)
        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: bytes,
            outputSize: (image.width, image.height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Enum mapping

    @inline(__always)
    private static func directionID(_ direction: PixelSortDirection) -> UInt32 {
        switch direction {
        case .horizontal: return 0
        case .vertical:   return 1
        case .diagonal:   return 2
        }
    }

    @inline(__always)
    private static func spanModeID(_ mode: PixelSortSpanMode) -> UInt32 {
        switch mode {
        case .luminance: return 0
        case .kimBlack:  return 1
        case .kimWhite:  return 2
        case .kimBright: return 3
        case .kimDark:   return 4
        }
    }

    @inline(__always)
    private static func sortByID(_ mode: PixelSortCriterion) -> UInt32 {
        switch mode {
        case .luminance:  return 0
        case .brightness: return 1
        case .hue:        return 2
        }
    }
}
