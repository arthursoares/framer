// FilmGrainRenderer.swift
// Swift wrapper for FilmGrain.metal — seeded procedural film grain with
// SEP-style grains-per-pixel density, soft↔hard kernel, and highlight/
// shadow protection. Layer intensity drives the grain amount.

import Foundation
import CoreGraphics
import Metal

public enum FilmGrainRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var grainsPerPixel: Float = 250
        var softness: Float = 0.5
        var protectHighlights: Float = 0.15

        var protectShadows: Float = 0.15
        var seed: Float = 1
        var widthPx: Float = 0
        var heightPx: Float = 0

        var pitchScale: Float = 1
        var _pad0: Float = 0
        var _pad1: Float = 0
        var _pad2: Float = 0
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil,
        sourceIdentity: String? = nil
    ) throws -> CGImage {
        guard case .filmGrain(let fg) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.grainsPerPixel = Float(max(1, min(500, fg.grainsPerPixel)))
        uniforms.softness = Float(max(0, min(1, fg.softness)))
        uniforms.protectHighlights = Float(max(0, min(1, fg.protectHighlights)))
        uniforms.protectShadows = Float(max(0, min(1, fg.protectShadows)))
        let effectiveSeed = EffectSeed.effective(fg.seed, varyPerImage: fg.varyPerImage, identity: sourceIdentity)
        uniforms.seed = EffectSeed.uniformValue(effectiveSeed)
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)
        // Export path: enlarge the grain lattice by the preview→export scale
        // so the export reproduces the grain size the preview showed (same
        // convention as DitherGPURenderer's pixel-scale compensation).
        if let previewBase = previewBaseDimension, previewBase > 0 {
            let currentMax = max(image.width, image.height)
            uniforms.pitchScale = Float(max(1.0, Double(currentMax) / Double(previewBase)))
        }

        let pipeline = try library.pipeline(for: "filmGrainFragment")
        // Nearest sampler — the shader reads only its own pinned pixel.
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
