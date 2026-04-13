// PixelSortRenderer.swift
// Swift wrapper for PixelSort.metal. Pre-multiplies the blend intensity
// (`params.intensity * pixelSortParams.amount`) the same way the CPU path does,
// converts the direction enum to the uint the shader switches on, and clamps
// the span to the same 1..256 range.
//
// Note on parity: spans ≤ 24 sample exactly the same pixels as the CPU path
// and produce nearly identical output (modulo Float vs. Double precision).
// Spans > 24 are sub-sampled by the shader, so output diverges visibly. For
// export-quality renders prefer the CPU path; the GPU is intended for live
// preview where the 24-sample approximation is invisible at typical viewing
// scale.

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
        var direction: UInt32 = 0     // 0 horizontal, 1 vertical
        var spanCap: Int32 = 24

        var widthPx: Float = 0
        var heightPx: Float = 0
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
        uniforms.direction = (ps.direction == .vertical) ? 1 : 0
        uniforms.spanCap = Int32(max(1, min(256, ps.span)))
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)

        let pipeline = try library.pipeline(for: "pixelSortFragment")
        // Nearest sampling — span detection compares per-pixel luminance and
        // bilinear interpolation would smear span boundaries.
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
