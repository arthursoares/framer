// HalftoneRenderer.swift
// Swift wrapper for Halftone.metal. The shader takes pixel dimensions
// directly (used inside the dot pattern's `sin(ux * wf * dotSize) + ...`
// expression) so we pass `image.width / image.height` through.

import Foundation
import CoreGraphics
import Metal

public enum HalftoneRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var dotSize: Float = 1
        var halftoneContrast: Float = 1
        var monochrome: UInt32 = 0

        var widthPx: Float = 0
        var heightPx: Float = 0
        var _pad0: Float = 0
        var _pad1: Float = 0
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .halftone(let h) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.dotSize = Float(max(0.1, h.dotSize))
        uniforms.halftoneContrast = Float(max(0.1, h.contrast))
        uniforms.monochrome = h.monochrome ? 1 : 0
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)

        let pipeline = try library.pipeline(for: "halftoneFragment")
        // Nearest sampler — CPU does exact integer-pixel byte reads
        // (Sources/FramerCore/Processing/ShaderRenderer.swift:466-468). Bilinear
        // would smear the source channels into adjacent pixels and shift the
        // halftone phase by half a texel, producing a systematic delta.
        let sampler = try library.nearestClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: image, device: library.device)

        let bytes = withUnsafeBytes(of: uniforms) { Data($0) }
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
