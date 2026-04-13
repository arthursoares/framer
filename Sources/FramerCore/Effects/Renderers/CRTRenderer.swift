// CRTRenderer.swift
// Swift wrapper for CRT.metal. Pre-computes `lineScale` (CPU does this from
// `height / pow(2, lineSize)`) so the shader stays branchless.

import Foundation
import CoreGraphics
import Metal

public enum CRTRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var curvature: Float = 1
        var lineScale: Float = 0
        var lineStrength: Float = 0
        var brightness: Float = 0
        var vignetteWidth: Float = 1

        var widthPx: Float = 0
        var heightPx: Float = 0
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .crt(let crt) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.curvature = Float(max(1.0, crt.curvature))

        let clampedLineSize = max(0, min(4, crt.lineSize))
        uniforms.lineScale = Float(Double(image.height) / pow(2.0, Double(clampedLineSize)))
        uniforms.lineStrength = Float(max(0.0, crt.lineStrength))
        uniforms.brightness = Float(crt.brightness)
        uniforms.vignetteWidth = Float(max(1.0, crt.vignette))

        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)

        let pipeline = try library.pipeline(for: "crtFragment")
        // Nearest sampler — CPU does exact integer-pixel byte reads. Bilinear
        // filtering would blur the source by ~half a texel and bias every
        // sample toward neighbour pixels, producing a systematic delta vs CPU.
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
