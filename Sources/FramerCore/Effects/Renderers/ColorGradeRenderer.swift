// ColorGradeRenderer.swift
// Swift wrapper for ColorGrade.metal. One entry point per variant
// (Crimewave / Narc / Shiba) — they share a fragment pipeline keyed on
// `variant`, so the entry points only differ in how they pack uniforms.
//
// All three variants follow the same encoding pattern as TextCellRenderer:
// load pipeline, upload source, encode uniforms, run pass, read back CGImage.
// Errors propagate as `MetalEffectError`; ShaderRenderer catches them and
// falls back to the CPU implementation.

import Foundation
import CoreGraphics
import Metal

public enum ColorGradeRenderer {

    // MARK: - Uniform layout (mirrors ColorGradeUniforms in ColorGrade.metal)

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var variant: UInt32 = 0
        var intensity: Float = 1
        var blurRadius: UInt32 = 0
        var blurMixAmount: Float = 0

        var neon: Float = 0
        var crimewaveContrast: Float = 0

        var narcContrast: Float = 0
        var narcCrush: Float = 0
        var narcTemperature: Float = 0

        var shibaWarmth: Float = 0
        var shibaSaturation: Float = 0

        var grain: Float = 0
        var _pad0: Float = 0
        var _pad1: Float = 0
    }

    // MARK: - Public entry points

    public static func renderCrimewave(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .crimewave(let cw) = params.params else { return image }

        var uniforms = Uniforms()
        uniforms.variant = 0
        uniforms.intensity = Float(params.intensity)
        let blur = blurDescriptor(softness: cw.softness, mixScale: 0.8)
        uniforms.blurRadius = blur.radius
        uniforms.blurMixAmount = blur.mix
        uniforms.neon = Float(cw.neon)
        // CPU multiplies contrast by 1.3 inside applyCrimewave.
        uniforms.crimewaveContrast = Float(max(0.0, cw.contrast * 1.3))
        uniforms.grain = Float(max(0.0, min(1.0, cw.grain)))
        return try runPass(image: image, uniforms: uniforms)
    }

    public static func renderNarc(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .narc(let n) = params.params else { return image }

        var uniforms = Uniforms()
        uniforms.variant = 1
        uniforms.intensity = Float(params.intensity)
        // No blur in CPU narc path.
        uniforms.blurRadius = 0
        uniforms.blurMixAmount = 0
        uniforms.narcContrast = Float(max(0.0, n.contrast * 1.4))
        uniforms.narcCrush = Float(min(1.0, n.crush * 1.5 + 0.15))
        uniforms.narcTemperature = Float(n.temperature * 1.5)
        // CPU grain factor is 1.5× narc.grain.
        uniforms.grain = Float(max(0.0, min(1.0, n.grain * 1.5)))
        return try runPass(image: image, uniforms: uniforms)
    }

    public static func renderShiba(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .shiba(let s) = params.params else { return image }

        var uniforms = Uniforms()
        uniforms.variant = 2
        uniforms.intensity = Float(params.intensity)
        let blur = blurDescriptor(softness: s.softness, mixScale: 0.7)
        uniforms.blurRadius = blur.radius
        uniforms.blurMixAmount = blur.mix
        uniforms.shibaWarmth = Float(s.warmth * 1.8)
        uniforms.shibaSaturation = Float(s.saturation * 1.5)
        uniforms.grain = Float(max(0.0, min(1.0, s.grain)))
        return try runPass(image: image, uniforms: uniforms)
    }

    // MARK: - Helpers

    private static func blurDescriptor(softness: Double, mixScale: Double) -> (radius: UInt32, mix: Float) {
        guard softness > 0 else { return (0, 0) }
        let radius = max(1, Int((softness * 3).rounded()))
        return (UInt32(min(3, radius)), Float(softness * mixScale))
    }

    private static func runPass(image: CGImage, uniforms: Uniforms) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }
        let pipeline = try library.pipeline(for: "colorGradeFragment")
        let sampler = try library.linearClamp()
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
}
