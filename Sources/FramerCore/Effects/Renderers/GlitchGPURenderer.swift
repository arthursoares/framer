// GlitchGPURenderer.swift
// GPU paths for the Glitch bucket (`.gpuEffect.glitch.*`). Each variant is
// called from `GlitchRenderer.renderPreview` which falls back to the CPU path
// in `GlitchRenderer` on `MetalEffectError`.
//
// VHS dispatches to Glitch.metal's `glitchFragment`.
// PixelSort dispatches to PixelSort.metal's `pixelSortFragment`, reusing the
// same shader the `.shader` layer's PixelSort style uses (the bucket brings
// its own GlitchParameters adapter; the Shader layer has its own
// PixelSortRenderer for full-featured params).

import Foundation
import CoreGraphics
import Metal
import simd

public enum GlitchGPURenderer {

    /// Upper bound on the pixel-sort span walk. Must stay in sync with
    /// `PIXEL_SORT_MAX_WALK` in PixelSort.metal and the CPU path in
    /// `GlitchRenderer`. It bounds the shader's per-fragment O(span) walk, so it
    /// also caps how long a resolution-relative Streak can get on large images.
    static let maxSpanWalk = 1024

    // Mirrors GlitchUniforms in Glitch.metal.
    private struct Uniforms {
        var common   = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color    = FramerColorUniformsLayout()

        var variant:       UInt32 = 0
        var intensity:     Float  = 1
        var amount:        Float  = 0.5
        var distortion:    Float  = 0

        var colorBleed:    Float  = 0
        var scanlines:     Float  = 0
        var trackingError: Float  = 0
        var _pad0:         Float  = 0
    }

    // Mirrors PixelSortUniforms in PixelSort.metal. Duplicated in-file (vs.
    // reused from PixelSortRenderer) because the Shader layer's version is
    // fileprivate and serves a richer parameter surface; the bucket maps a
    // leaner GlitchParameters → uniforms subset here.
    private struct PixelSortUniforms {
        var common   = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color    = FramerColorUniformsLayout()

        var intensity:   Float  = 1
        var threshold:   Float  = 0
        var direction:   UInt32 = 0     // 0 horizontal, 1 vertical, 2 diagonal
        var spanCap:     Int32  = 24

        var widthPx:     Float  = 0
        var heightPx:    Float  = 0
        var spanMode:    UInt32 = 0     // 0 luminance, 1..4 Kim Asendorf (bucket: always 0)
        var reverse:     UInt32 = 0

        var randomness:  Float  = 0
        var sortBy:      UInt32 = 0     // 0 luminance, 1 brightness, 2 hue
        var _pad0:       Float  = 0
        var _pad1:       Float  = 0
    }

    public static func renderVHS(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: GlitchParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "glitchFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        uniforms.variant       = 0     // VHS
        uniforms.intensity     = 1.0
        uniforms.amount        = Float(clamp01(params.amount))
        uniforms.distortion    = Float(clamp01(params.distortion))
        uniforms.colorBleed    = Float(clamp01(params.colorBleed))
        uniforms.scanlines     = Float(clamp01(params.scanlines))
        uniforms.trackingError = Float(clamp01(params.trackingError))

        let uniformData = uniformBytes(uniforms)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: uniformData,
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    /// GPU dispatch for pixelSort in the Glitch bucket. Maps GlitchParameters
    /// (the bucket's leaner struct) onto the PixelSort.metal uniforms and runs
    /// `pixelSortFragment`. The bucket doesn't expose Kim-Asendorf span modes,
    /// so `spanMode` is fixed at 0 (classic luminance span). Threshold,
    /// direction, sort mode, streak length, randomness, and reverse all map
    /// straight across.
    public static func renderPixelSort(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: GlitchParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "pixelSortFragment")
        // Nearest sampling — span detection compares per-pixel luminance and
        // bilinear interpolation would smear span boundaries.
        let sampler = try library.nearestClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = PixelSortUniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        // `amount` drives blend intensity (matches CPU path's
        // `params.intensity * pixelSortParams.amount`; Glitch bucket's own
        // intensity defaults to 1.0 so amount alone is the dial).
        uniforms.intensity  = Float(clamp01(params.amount))
        uniforms.threshold  = Float(clamp01(params.threshold))
        uniforms.direction  = {
            switch params.direction {
            case .horizontal: return 0
            case .vertical:   return 1
            }
        }()
        // Streak is a 0..1 dial mapped to a fraction of the image's sort-axis
        // dimension (width for horizontal sorting, height for vertical), so the
        // streak length is resolution-independent: the preview and a full-res
        // export show the same proportional streaks. The quadratic curve keeps
        // fine control in the low band. Clamped to `maxSpanWalk` to bound the
        // shader's per-fragment O(span) walk — extreme streaks on very large
        // images clamp there for GPU performance.
        let sortAxisDimension = params.direction == .horizontal ? width : height
        let proportionalSpan = params.streakLength * params.streakLength * Double(sortAxisDimension)
        uniforms.spanCap    = Int32(max(1, min(maxSpanWalk, Int(proportionalSpan.rounded()))))
        uniforms.widthPx    = Float(width)
        uniforms.heightPx   = Float(height)
        uniforms.spanMode   = 0
        uniforms.reverse    = params.reverse ? 1 : 0
        uniforms.randomness = Float(clamp01(params.randomness))
        uniforms.sortBy     = {
            switch params.sortMode {
            case .luminance:  return 0
            case .brightness: return 1
            case .hue:        return 2
            }
        }()

        let uniformData = uniformBytes(uniforms)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: uniformData,
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Helpers

    private static func mapCommon(_ p: GPUEffectCommonParameters, into u: inout FramerCommonUniformsLayout) {
        u.brightness  = Float(p.brightness)
        u.contrast    = Float(p.contrast)
        u.saturation  = Float(p.saturation)
        u.hueRotation = Float(p.hueRotation)
        u.sharpness   = Float(p.sharpness)
        u.gamma       = Float(p.gamma)
    }

    private static func mapGeometry(_ p: GPUEffectGeometryParameters, into u: inout FramerGeometryUniformsLayout) {
        u.scale       = Float(p.scale)
        u.spacing     = Float(p.spacing)
        u.outputWidth = Float(p.outputWidth)
    }

    private static func mapColor(_ p: GPUEffectColorParameters, into u: inout FramerColorUniformsLayout) {
        u.mode = {
            switch p.mode {
            case .source:               return 0
            case .foregroundBackground: return 1
            case .monochrome:           return 2
            case .palette:              return 3
            }
        }()
        u.backgroundIntensity = Float(p.backgroundIntensity)
    }

    @inline(__always)
    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
