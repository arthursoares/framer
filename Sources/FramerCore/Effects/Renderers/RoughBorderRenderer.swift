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
        var borderType: UInt32 = 3

        var borderRGBA = SIMD4<Float>(1, 1, 1, 1)
    }

    /// FNV-1a over the identity string's UTF-8 bytes. Swift's `hashValue` is
    /// randomized per process — a border seeded from it would change on every
    /// launch, breaking preview/export agreement and re-run reproducibility.
    private static func stableHash(_ identity: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams,
        sourceIdentity: String? = nil
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
        // Vary-per-image: fold a stable hash of the source filename into the
        // seed so each image in a batch gets its own border while the same
        // image always reproduces the same edge.
        var effectiveSeed = rb.seed
        if rb.varyPerImage, let identity = sourceIdentity {
            effectiveSeed = rb.seed &+ Int(truncatingIfNeeded: stableHash(identity))
        }
        // Fold the integer seed into the float domain the noise hash reads.
        // Modulo keeps precision: beyond ~2^24 a Float can no longer resolve
        // adjacent seeds.
        uniforms.seed = Float(((effectiveSeed % 100_000) + 100_000) % 100_000)
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)
        uniforms.borderType = UInt32(rb.borderType.shaderIndex)
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
