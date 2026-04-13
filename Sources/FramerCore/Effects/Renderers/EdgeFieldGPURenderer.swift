// EdgeFieldGPURenderer.swift
// GPU path for the EdgeField bucket (`.gpuEffect.edgeField.*`). Called by
// EdgeFieldRenderer.renderPreview for variants whose fragment shader is
// implemented in Effects/Metal/EdgeField.metal. Throws MetalEffectError on
// Metal failure so the caller can fall back to the existing CPU path.

import Foundation
import CoreGraphics
import Metal
import simd

public enum EdgeFieldGPURenderer {

    // Mirrors EdgeFieldUniforms in EdgeField.metal — field order, types, and
    // padding must match exactly.
    private struct Uniforms {
        var common   = FramerCommonUniformsLayout()
        var geometry = FramerGeometryUniformsLayout()
        var color    = FramerColorUniformsLayout()

        var variant:       UInt32 = 0
        var intensity:     Float  = 1
        var lineStrength:  Float  = 0.5
        var thickness:     Float  = 0.3

        var edgeThreshold: Float  = 0.5
        var edgeAlgorithm: UInt32 = 0
        var invert:        UInt32 = 0
        var fieldIntensity: Float = 0.5

        var contourLevels:   UInt32 = 8
        var contourFillMode: UInt32 = 0       // 0 linesOnly, 1 filledBands
        var direction:       UInt32 = 0       // 0 horizontal, 1 vertical
        var amplitude:       Float  = 0.5

        var frequency: Float = 1.0
        var lineCount: Float = 12
        var spacing:   Float = 8.0
        var cellSize:  Float = 16.0

        var edgeWidth:   Float  = 0.25
        var randomize:   UInt32 = 0
        var fieldWeight: Float  = 0.5
        var _pad0: Float = 0

        var edgeColor: SIMD4<Float> = SIMD4(0, 0, 0, 0)
    }

    // MARK: - Edge Detection

    public static func renderEdgeDetection(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: EdgeFieldParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "edgeFieldFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        uniforms.variant       = 0        // edgeDetection
        uniforms.intensity     = 1.0
        uniforms.lineStrength  = Float(clamp01(params.lineStrength))
        uniforms.thickness     = Float(clamp01(params.thickness))
        uniforms.edgeThreshold = Float(clamp01(params.edgeThreshold))
        uniforms.edgeAlgorithm = (params.edgeAlgorithm == .laplacian) ? 1 : 0
        uniforms.invert        = params.invert ? 1 : 0
        uniforms.edgeColor     = params.edgeColor.map { simdColor($0) } ?? SIMD4(0, 0, 0, 0)

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

    // MARK: - Contour

    public static func renderContour(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: EdgeFieldParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "edgeFieldFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        uniforms.variant         = 1        // contour
        uniforms.intensity       = 1.0
        uniforms.lineStrength    = Float(clamp01(params.lineStrength))
        uniforms.thickness       = Float(clamp01(params.thickness))
        uniforms.invert          = params.invert ? 1 : 0
        uniforms.fieldIntensity  = Float(clamp01(params.fieldIntensity))
        uniforms.contourLevels   = UInt32(max(2, min(32, params.contourLevels)))
        uniforms.contourFillMode = (params.contourFillMode == .filledBands) ? 1 : 0
        uniforms.edgeColor       = params.edgeColor.map { simdColor($0) } ?? SIMD4(0, 0, 0, 0)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: uniformBytes(uniforms),
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Wave Lines

    public static func renderWaveLines(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: EdgeFieldParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else {
            throw MetalEffectError.metalUnavailable
        }

        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        let pipeline = try library.pipeline(for: "edgeFieldFragment")
        let sampler  = try library.linearClamp()
        let sourceTexture = try MetalTextureSupport.makeTexture(from: input, device: library.device)

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)

        uniforms.variant      = 2            // waveLines
        uniforms.intensity    = 1.0
        uniforms.lineStrength = Float(clamp01(params.lineStrength))
        uniforms.thickness    = Float(clamp01(params.thickness))
        uniforms.invert       = params.invert ? 1 : 0
        uniforms.direction    = (params.direction == .vertical) ? 1 : 0
        uniforms.amplitude    = Float(clamp01(params.amplitude))
        uniforms.frequency    = Float(max(0.1, params.frequency))
        uniforms.lineCount    = Float(params.lineCount)
        uniforms.spacing      = Float(max(1.0, geometry.spacing + geometry.scale * 2.0))
        uniforms.edgeColor    = params.edgeColor.map { simdColor($0) } ?? SIMD4(0, 0, 0, 0)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: pipeline,
            source: sourceTexture,
            auxTextures: [],
            sampler: sampler,
            uniformBytes: uniformBytes(uniforms),
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Voronoi

    public static func renderVoronoi(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: EdgeFieldParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else { throw MetalEffectError.metalUnavailable }
        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)
        uniforms.variant      = 3
        uniforms.intensity    = 1.0
        uniforms.lineStrength = Float(clamp01(params.lineStrength))
        uniforms.invert       = params.invert ? 1 : 0
        uniforms.cellSize     = Float(max(2.0, params.cellSize))
        uniforms.edgeWidth    = Float(clamp01(params.edgeWidth))
        uniforms.randomize    = params.randomize ? 1 : 0
        uniforms.fieldWeight  = Float(clamp01(params.fieldIntensity))
        uniforms.edgeColor    = params.edgeColor.map { simdColor($0) } ?? SIMD4(0, 0, 0, 0)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: try library.pipeline(for: "edgeFieldFragment"),
            source: try MetalTextureSupport.makeTexture(from: input, device: library.device),
            auxTextures: [],
            sampler: try library.linearClamp(),
            uniformBytes: uniformBytes(uniforms),
            outputSize: (width, height),
            library: library
        )
        return try MetalTextureSupport.makeCGImage(from: outputTexture)
    }

    // MARK: - Noise Field

    public static func renderNoiseField(
        input: CGImage,
        common: GPUEffectCommonParameters,
        geometry: GPUEffectGeometryParameters,
        color: GPUEffectColorParameters,
        params: EdgeFieldParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard let library = MetalEffectLibrary.shared else { throw MetalEffectError.metalUnavailable }
        let width  = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        var uniforms = Uniforms()
        mapCommon(common, into: &uniforms.common)
        mapGeometry(geometry, into: &uniforms.geometry)
        mapColor(color, into: &uniforms.color)
        uniforms.variant      = 4
        uniforms.intensity    = 1.0
        uniforms.lineStrength = Float(clamp01(params.lineStrength))
        uniforms.invert       = params.invert ? 1 : 0
        uniforms.amplitude    = Float(clamp01(params.amplitude))
        uniforms.fieldWeight  = Float(clamp01(params.fieldIntensity))
        uniforms.edgeColor    = params.edgeColor.map { simdColor($0) } ?? SIMD4(0, 0, 0, 0)

        let outputTexture = try MetalRenderPass.encode(
            pipeline: try library.pipeline(for: "edgeFieldFragment"),
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
        u.sharpness   = Float(p.sharpness)
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
