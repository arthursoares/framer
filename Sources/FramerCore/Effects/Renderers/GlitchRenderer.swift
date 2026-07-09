import Foundation
import CoreGraphics

/// Dispatch entry for the Glitch bucket (`.gpuEffect` pixelSort / vhs).
///
/// GPU-only: the CPU pixel-loop fallback was removed once Metal became a
/// hard requirement. It interpreted parameters differently from the
/// shaders (summed `amount + distortion` and `threshold + trackingError`,
/// scaled `colorBleed`/`scanlines` to pixels instead of treating them as
/// normalized), so any host that actually hit it rendered a visibly
/// different image than the GPU path — worse than failing loudly.
public enum GlitchRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .glitch(common, geometry, color, payload) = parameters else {
            return input
        }

        switch payload.variant {
        case .vhs:
            return try GlitchGPURenderer.renderVHS(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        case .pixelSort:
            return try GlitchGPURenderer.renderPixelSort(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        }
    }
}
