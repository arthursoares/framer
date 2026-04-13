// DistantPastRenderer.swift
// Swift wrapper for DistantPast.metal. Computes the active palette CPU-side
// (taking an evenly-spaced subset of the canonical 6-colour palette) and
// uploads it as part of the uniform block so the shader stays a pure kernel.

import Foundation
import CoreGraphics
import Metal

public enum DistantPastRenderer {

    private static let MAX_PALETTE_COLORS = 6

    // Same canonical palette as ShaderRenderer.distantPastPalette
    // (Sources/FramerCore/Processing/ShaderRenderer.swift). Order matters —
    // dark → light, so the palette-depth subset interpolates evenly.
    private static let canonicalPalette: [SIMD3<Float>] = [
        SIMD3(0.411765, 0.414072, 0.490196),  // muted lavender
        SIMD3(0.537255, 0.466667, 0.466667),  // dusty mauve
        SIMD3(0.582237, 0.690196, 0.407843),  // olive green
        SIMD3(0.668166, 0.752941, 0.560784),  // sage green
        SIMD3(0.815917, 0.835294, 0.725490),  // pale cream
        SIMD3(0.921569, 0.912534, 0.912534),  // pearl white
    ]

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var fade: Float = 0
        var softness: Float = 0
        var grain: Float = 0

        var paletteCount: UInt32 = 0
        var blurRadius: UInt32 = 0
        var blurMixAmount: Float = 0
        var _pad0: Float = 0

        var widthPx: Float = 0
        var heightPx: Float = 0
        var _pad1: Float = 0
        var _pad2: Float = 0

        // 6 × float4 = 96 bytes. Slot 0 is .x = palette[0].r etc.
        var palette: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                       SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
            (SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0),
             SIMD4(0,0,0,0), SIMD4(0,0,0,0), SIMD4(0,0,0,0))
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .distantPast(let dp) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.fade = Float(max(0.0, min(1.0, dp.fade)))
        uniforms.softness = Float(max(0.0, min(1.0, dp.softness)))
        uniforms.grain = Float(max(0.0, min(1.0, dp.grain)))
        uniforms.widthPx = Float(image.width)
        uniforms.heightPx = Float(image.height)

        // Blur descriptor matches ShaderRenderer.applyDistantPast: radius
        // scales with softness × 3, mixAmount = softness × 0.7.
        if dp.softness > 0 {
            let radius = max(1, Int((dp.softness * 3).rounded()))
            uniforms.blurRadius = UInt32(min(3, radius))
            uniforms.blurMixAmount = Float(dp.softness * 0.7)
        }

        let activePalette = makeActivePalette(depth: dp.paletteDepth)
        uniforms.paletteCount = UInt32(activePalette.count)
        let palette4 = activePalette.map { SIMD4<Float>($0.x, $0.y, $0.z, 1) }
        // Splat into the fixed-size tuple. Unfilled slots stay zero.
        if palette4.count > 0 { uniforms.palette.0 = palette4[0] }
        if palette4.count > 1 { uniforms.palette.1 = palette4[1] }
        if palette4.count > 2 { uniforms.palette.2 = palette4[2] }
        if palette4.count > 3 { uniforms.palette.3 = palette4[3] }
        if palette4.count > 4 { uniforms.palette.4 = palette4[4] }
        if palette4.count > 5 { uniforms.palette.5 = palette4[5] }

        let pipeline = try library.pipeline(for: "distantPastFragment")
        let sampler = try library.linearClamp()
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

    /// Pick `paletteDepth` evenly-spaced colours from the canonical 6-colour
    /// table. Mirrors the CPU subset logic exactly so palette transitions snap
    /// to the same indices.
    private static func makeActivePalette(depth: Int) -> [SIMD3<Float>] {
        let count = max(2, min(canonicalPalette.count, depth))
        if count >= canonicalPalette.count {
            return canonicalPalette
        }
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let idx = min(canonicalPalette.count - 1,
                          Int((t * Double(canonicalPalette.count - 1)).rounded()))
            return canonicalPalette[idx]
        }
    }
}
