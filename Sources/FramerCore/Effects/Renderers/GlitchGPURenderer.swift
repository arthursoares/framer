// GlitchGPURenderer.swift
// GPU path for the Glitch bucket (`.gpuEffect.glitch.vhs` — pixelSort has its
// own dedicated shader wired through ShaderStyle.pixelSort). Called by
// GlitchRenderer.renderPreview for variants whose fragment shader is in
// Effects/Metal/Glitch.metal.

import Foundation
import CoreGraphics
import Metal
import simd

public enum GlitchGPURenderer {

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
