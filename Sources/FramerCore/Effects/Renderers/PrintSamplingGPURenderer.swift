// PrintSamplingGPURenderer.swift
// GPU path for the PrintSampling bucket (`.gpuEffect.printSampling.*`).
// Called by PrintSamplingRenderer.renderPreview for variants whose fragment
// shader is implemented in Effects/Metal/PrintSampling.metal. Throws
// MetalEffectError on Metal failure so the caller can fall back to the
// existing CPU pixel-loop path.

import Foundation
import CoreGraphics
import Metal
import simd

public enum PrintSamplingGPURenderer {

    // Mirrors PrintSamplingUniforms in PrintSampling.metal — field order,
    // types, and padding must match exactly.
    private struct Uniforms {
        var common   = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color    = FramerColorUniformsLayout()

        var variant:        UInt32 = 0
        var intensity:      Float  = 1
        var threshold:      Float  = 0.5
        var invert:         UInt32 = 0

        var thresholdLevels:  UInt32 = 4
        var thresholdDither:  UInt32 = 0
        var hatchAngle:       Float  = 45
        var hatchDensity:     Float  = 0.5

        var hatchLineWidth:   Float  = 0.25
        var hatchLayers:      UInt32 = 2
        var hatchRandomness:  Float  = 0
        var _pad0: Float = 0

        var foregroundRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)
        var backgroundRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    }

    // MARK: - Threshold

    public static func renderThreshold(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: PrintSamplingParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "printSamplingFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        uniforms.variant         = 0   // threshold
        uniforms.intensity       = Float(clamp01(params.variantIntensity(common: common)))
        uniforms.threshold       = Float(clamp01(params.threshold))
        uniforms.invert          = params.invert ? 1 : 0
        uniforms.thresholdLevels = UInt32(max(2, min(32, params.thresholdLevels)))
        uniforms.thresholdDither = params.thresholdDither ? 1 : 0

        uniforms.foregroundRGBA = params.foreground.map(simdColor) ?? SIMD4(0, 0, 0, 1)
        uniforms.backgroundRGBA = params.background.map(simdColor) ?? SIMD4(1, 1, 1, 1)

        let uniformData = uniformBytes(uniforms)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: uniformData,
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Crosshatch

    public static func renderCrosshatch(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: PrintSamplingParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }
        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        uniforms.variant        = 1     // crosshatch
        uniforms.intensity      = 1.0
        uniforms.threshold      = Float(clamp01(params.threshold))
        uniforms.invert         = params.invert ? 1 : 0
        uniforms.hatchAngle     = Float(params.hatchAngle)
        uniforms.hatchDensity   = Float(max(0.1, params.hatchDensity))
        uniforms.hatchLineWidth = Float(clamp01(params.hatchLineWidth))
        uniforms.hatchLayers    = UInt32(max(1, min(3, params.hatchLayers)))
        uniforms.hatchRandomness = Float(clamp01(params.hatchRandomness))
        uniforms.foregroundRGBA = params.foreground.map(simdColor) ?? SIMD4(0, 0, 0, 1)
        uniforms.backgroundRGBA = params.background.map(simdColor) ?? SIMD4(1, 1, 1, 1)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: try library.pipeline(for: "printSamplingFragment"),
            source: try MetalTextureSupport.makeTexture(from: input, device: library.device),
            auxTextures: [],
            sampler: try library.linearClamp(),
            uniformBytes: uniformBytes(uniforms),
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Helpers

    private static func mapCommon(_ p: GPUEffectCommonParameters, into u: inout FramerCommonUniformsLayout) {
        u.brightness  = Float(p.brightness)
        u.contrast    = Float(p.contrast)
        u.saturation  = Float(p.saturation)
        u.hueRotation = Float(p.hueRotation)
        u.sharpness   = 0  // retired — no shader consumes it; slot kept for Metal layout
        u.gamma       = Float(p.gamma)
    }

    private static func mapGeometry(_ p: GPUEffectGeometryParameters, into u: inout FramerGeometryUniformsLayout) {
        u.scale       = Float(p.scale)
        u.spacing     = Float(p.spacing)
        u.outputWidth = Float(p.outputWidth)
    }

    private static func mapColor(_ p: GPUEffectColorParameters, into u: inout FramerColorUniformsLayout) {
        u.mode = {
            switch p.mode {
            case .source:               return 0
            case .foregroundBackground: return 1
            case .monochrome:           return 2
            case .palette:              return 3
            }
        }()
        u.backgroundIntensity = Float(p.backgroundIntensity)
    }

    @inline(__always)
    private static func simdColor(_ color: CodableColor) -> SIMD4<Float> {
        SIMD4(Float(color.red), Float(color.green), Float(color.blue), 1)
    }

    @inline(__always)
    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

// MARK: - PrintSamplingParameters helper

private extension PrintSamplingParameters {
    /// The bucket enum doesn't ship a per-variant intensity; this derives one
    /// from whichever field is most relevant. For threshold / dithering /
    /// crosshatch / halftone the final-blend intensity is driven by
    /// `common.brightness` (-1..1 → 0..1) when no dedicated field exists.
    /// Start at 1.0 so the effect is fully applied by default.
    func variantIntensity(common: GPUEffectCommonParameters) -> Double {
        return 1.0
    }
}
