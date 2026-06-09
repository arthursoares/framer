import Foundation
import CoreGraphics

/// Dispatch entry for the EdgeField bucket (`.gpuEffect` contour /
/// edgeDetection / waveLines / voronoi / noiseField).
///
/// GPU-only: the CPU pixel-loop fallback was removed once Metal became a
/// hard requirement. It diverged from the shaders (contrast bias on
/// `fieldIntensity`, a frequency boost the GPU never applied, different
/// minimums on `amplitude`/`edgeWidth`), so any host that actually hit it
/// rendered a visibly different image than the GPU path — worse than
/// failing loudly.
public enum EdgeFieldRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .edgeField(common, geometry, color, payload) = parameters else {
            return input
        }

        switch payload.variant {
        case .edgeDetection:
            return try EdgeFieldGPURenderer.renderEdgeDetection(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        case .contour:
            return try EdgeFieldGPURenderer.renderContour(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        case .waveLines:
            return try EdgeFieldGPURenderer.renderWaveLines(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        case .voronoi:
            return try EdgeFieldGPURenderer.renderVoronoi(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        case .noiseField:
            return try EdgeFieldGPURenderer.renderNoiseField(
                input: input, common: common, geometry: geometry,
                color: color, params: payload, outputSize: outputSize)
        }
    }
}
