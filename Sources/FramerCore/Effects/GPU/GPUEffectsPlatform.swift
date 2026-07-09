import Foundation
import CoreGraphics
import CoreImage

public enum GPUEffectsPlatformError: Error {
    case metalUnavailable
    case renderFailed
}

public final class GPUEffectsPlatform {
    private let context: GPUCommandContext
    private let texturePool: GPUTexturePool

    public init(context: GPUCommandContext, texturePool: GPUTexturePool = GPUTexturePool()) {
        self.context = context
        self.texturePool = texturePool
    }

    public static func makeForTests() throws -> GPUEffectsPlatform {
        let context = try GPUCommandContext.makeDefault()
        return GPUEffectsPlatform(context: context)
    }

    public func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        try Self.dispatchRenderPreview(
            input: input,
            effect: effect,
            parameters: parameters,
            outputSize: outputSize
        )
    }

    /// Stateless dispatch entry point. Routes a `.gpuEffect` parameter set to
    /// the corresponding bucket renderer. The bucket path is GPU-only —
    /// renderers throw `MetalEffectError` on Metal-less hosts instead of
    /// falling back to CPU (PR #12 + docs/adr/2026-07-09-retire-cpu-effect-path.md).
    /// The only CPU routes left are the hidden legacy variants with no GPU
    /// entry: textCell `.ascii` and printSampling `.halftone`/`.dithering`,
    /// selected by variant rather than by caught error.
    public static func dispatchRenderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        switch parameters {
        case .textCell:
            return try TextCellBucketRenderer.renderPreview(input: input, effect: effect, parameters: parameters, outputSize: outputSize)
        case .printSampling:
            return try PrintSamplingRenderer.renderPreview(input: input, effect: effect, parameters: parameters, outputSize: outputSize)
        case .edgeField:
            return try EdgeFieldRenderer.renderPreview(input: input, effect: effect, parameters: parameters, outputSize: outputSize)
        case .glitch:
            return try GlitchRenderer.renderPreview(input: input, effect: effect, parameters: parameters, outputSize: outputSize)
        }
    }

    private func encodedParameters(for parameters: GPUEffectParameters) -> (SIMD4<Float>, SIMD4<Float>) {
        switch parameters {
        case .textCell(let common, let geometry, _, _),
             .printSampling(let common, let geometry, _, _),
             .edgeField(let common, let geometry, _, _),
             .glitch(let common, let geometry, _, _):
            return (GPUParameterEncoder.common(common), GPUParameterEncoder.geometry(geometry))
        }
    }
}
