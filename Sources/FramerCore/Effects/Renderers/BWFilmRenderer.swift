// BWFilmRenderer.swift
// Swift wrapper for BWFilm.metal — SEP-style B&W conversion. Bakes the
// tone curve (gamma + black/white nodes + control points, SEP lacdata
// semantics) into a 256×1 r32Float LUT texture bound at fragment slot 1.

import Foundation
import CoreGraphics
import Metal

public enum BWFilmRenderer {

    private struct Uniforms {
        var common = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color = FramerColorUniformsLayout()

        var intensity: Float = 1
        var sensR: Float = 0
        var sensYe: Float = 0
        var sensG: Float = 0

        var sensCy: Float = 0
        var sensB: Float = 0
        var sensMg: Float = 0
        var brightness: Float = 0

        var briHighlights: Float = 0
        var briMidtones: Float = 0
        var briShadows: Float = 0
        var contrast: Float = 0

        var protectHighlights: Float = 0
        var protectShadows: Float = 0
        var toningStrength: Float = 0
        var toneHueHigh: Float = 40

        var toneStrengthHigh: Float = 0
        var toneHueLow: Float = 40
        var toneStrengthLow: Float = 0
        var toneBalance: Float = 0

        var vigStrength: Float = 0
        var vigSize: Float = 50
        var vigShape: Float = 3
        var beStrengthTop: Float = 0

        var beStrengthBottom: Float = 0
        var beStrengthLeft: Float = 0
        var beStrengthRight: Float = 0
        var beSizeTop: Float = 25

        var beSizeBottom: Float = 25
        var beSizeLeft: Float = 25
        var beSizeRight: Float = 25
        var beTransitionTop: Float = 50

        var beTransitionBottom: Float = 50
        var beTransitionLeft: Float = 50
        var beTransitionRight: Float = 50
        var _pad0: Float = 0
    }

    /// Bake the tone curve into 256 output samples. SEP lacdata semantics:
    /// endpoints are the low/high nodes, interior control points are NOT
    /// x-sorted on disk (sort first), interpolation is a clamped
    /// Catmull-Rom through the sorted nodes, then the gamma bend.
    static func bakeCurve(_ p: BWFilmShaderParams) -> [Float] {
        var nodes: [(x: Double, y: Double)] = [(p.curveLowX, p.curveLowY)]
        nodes.append(contentsOf: p.curvePoints
            .map { (x: $0.x, y: $0.y) }
            .filter { $0.x > p.curveLowX && $0.x < p.curveHighX }
            .sorted { $0.x < $1.x })
        nodes.append((p.curveHighX, p.curveHighY))

        func evaluate(_ t: Double) -> Double {
            if t <= nodes.first!.x { return nodes.first!.y }
            if t >= nodes.last!.x { return nodes.last!.y }
            var seg = 0
            while seg < nodes.count - 2 && t > nodes[seg + 1].x { seg += 1 }
            let p1 = nodes[seg], p2 = nodes[seg + 1]
            let p0 = seg > 0 ? nodes[seg - 1] : p1
            let p3 = seg < nodes.count - 2 ? nodes[seg + 2] : p2
            let span = p2.x - p1.x
            guard span > 1e-9 else { return p2.y }
            let u = (t - p1.x) / span
            // Catmull-Rom on y with non-uniform x flattened to the segment.
            let u2 = u * u, u3 = u2 * u
            let y = 0.5 * ((2 * p1.y)
                + (-p0.y + p2.y) * u
                + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * u2
                + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * u3)
            return min(1, max(0, y))
        }

        // gamma > 0 brightens midtones (exponent < 1), matching the sign
        // convention implied by SEP's negative-gamma darkening presets.
        let exponent = exp(-p.curveGamma * 1.5)
        return (0..<256).map { i in
            let t = Double(i) / 255.0
            let curved = evaluate(t)
            return Float(pow(curved, exponent))
        }
    }

    private static func makeCurveTexture(_ samples: [Float], device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: samples.count, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalEffectError.textureCreationFailed
        }
        samples.withUnsafeBufferPointer { buffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, samples.count, 1),
                mipmapLevel: 0,
                withBytes: buffer.baseAddress!,
                bytesPerRow: samples.count * MemoryLayout<Float>.stride)
        }
        return texture
    }

    public static func render(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .bwFilm(let bw) = params.params else { return image }
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        var uniforms = Uniforms()
        uniforms.intensity = Float(params.intensity)
        uniforms.sensR = Float(bw.sensRed)
        uniforms.sensYe = Float(bw.sensYellow)
        uniforms.sensG = Float(bw.sensGreen)
        uniforms.sensCy = Float(bw.sensCyan)
        uniforms.sensB = Float(bw.sensBlue)
        uniforms.sensMg = Float(bw.sensMagenta)
        uniforms.brightness = Float(bw.brightness)
        uniforms.briHighlights = Float(bw.brightnessHighlights)
        uniforms.briMidtones = Float(bw.brightnessMidtones)
        uniforms.briShadows = Float(bw.brightnessShadows)
        uniforms.contrast = Float(bw.contrast)
        uniforms.protectHighlights = Float(bw.protectHighlights)
        uniforms.protectShadows = Float(bw.protectShadows)
        uniforms.toningStrength = Float(bw.toningStrength)
        uniforms.toneHueHigh = Float(bw.toneHueHigh)
        uniforms.toneStrengthHigh = Float(bw.toneStrengthHigh)
        uniforms.toneHueLow = Float(bw.toneHueLow)
        uniforms.toneStrengthLow = Float(bw.toneStrengthLow)
        uniforms.toneBalance = Float(bw.toneBalance)
        uniforms.vigStrength = Float(bw.vigStrength)
        uniforms.vigSize = Float(bw.vigSize)
        uniforms.vigShape = Float(bw.vigShape)
        uniforms.beStrengthTop = Float(bw.beStrengthTop)
        uniforms.beStrengthBottom = Float(bw.beStrengthBottom)
        uniforms.beStrengthLeft = Float(bw.beStrengthLeft)
        uniforms.beStrengthRight = Float(bw.beStrengthRight)
        uniforms.beSizeTop = Float(bw.beSizeTop)
        uniforms.beSizeBottom = Float(bw.beSizeBottom)
        uniforms.beSizeLeft = Float(bw.beSizeLeft)
        uniforms.beSizeRight = Float(bw.beSizeRight)
        uniforms.beTransitionTop = Float(bw.beTransitionTop)
        uniforms.beTransitionBottom = Float(bw.beTransitionBottom)
        uniforms.beTransitionLeft = Float(bw.beTransitionLeft)
        uniforms.beTransitionRight = Float(bw.beTransitionRight)

        let pipeline = try library.pipeline(for: "bwFilmFragment")
        // Nearest sampler — the shader reads only its own pinned pixel;
        // the curve LUT is read via .read(), no sampler involved.
        let sampler = try library.nearestClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: image, device: library.device)
        let curveTexture = try makeCurveTexture(bakeCurve(bw), device: library.device)

        let bytes = uniformBytes(uniforms)
        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [curveTexture],
            sampler: sampler,
            uniformBytes: bytes,
            outputSize: (image.width, image.height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }
}
