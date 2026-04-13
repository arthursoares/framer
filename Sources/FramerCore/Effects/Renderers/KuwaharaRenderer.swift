// KuwaharaRenderer.swift
// Swift wrapper for Kuwahara.metal. Trivial uniform packing — the heavy
// quadrant-variance work is entirely shader-side.

import Foundation
import CoreGraphics
import Metal

public enum KuwaharaRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var kernelSize: Int32 = 1
        var sharpness: Float = 0
        var _pad0: Float = 0
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .kuwahara(let k) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.kernelSize = Int32(max(1, min(15, k.kernelSize)))
        uniforms.sharpness = Float(max(0.0, k.sharpness))

        let pipeline = try library.pipeline(for: "kuwaharaFragment")
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
