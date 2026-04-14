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
    /// the corresponding bucket renderer. Each renderer attempts its GPU path
    /// and falls back to CPU on `MetalEffectError`, so callers can dispatch
    /// without first proving Metal is available — required to support headless
    /// hosts where `MTLCreateSystemDefaultDevice()` returns nil.
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
