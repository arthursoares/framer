// RoughBorderRenderer.swift
// Swift wrapper for RoughBorder.metal — the seeded procedural darkroom
// border. The shader measures everything in min(width, height) units, so
// the border stays proportional across resolutions and aspect ratios; the
// seed makes every variation exactly reproducible.

import Foundation
import CoreGraphics
import Metal

public enum RoughBorderRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var size: Float = 0.05
        var spread: Float = 0.5
        var roughness: Float = 0.5

        var seed: Float = 1
        var widthPx: Float = 0
        var heightPx: Float = 0
        var _pad0: Float = 0

        var borderRGBA = SIMD4<Float>(1, 1, 1, 1)
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .roughBorder(let rb) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.size = Float(max(0, min(0.25, rb.size)))
        uniforms.spread = Float(max(0, min(1, rb.spread)))
        uniforms.roughness = Float(max(0, min(1, rb.roughness)))
        // Fold the integer seed into the float domain the noise hash reads.
        // Modulo keeps precision: beyond ~2^24 a Float can no longer resolve
        // adjacent seeds.
        uniforms.seed = Float(((rb.seed % 100_000) + 100_000) % 100_000)
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)
        uniforms.borderRGBA = SIMD4<Float>(
            Float(rb.borderColor.red),
            Float(rb.borderColor.green),
            Float(rb.borderColor.blue),
            1
        )

        let pipeline = try library.pipeline(for: "roughBorderFragment")
        // Nearest sampler — the shader reads only its own pinned pixel, and
        // exact reads keep the pass-through region byte-identical to source.
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
}
