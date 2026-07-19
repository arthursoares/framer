import Foundation
import CoreGraphics

/// Dispatches `.shader` layers to their Metal renderers. GPU-only: the CPU
/// twin implementations were retired (docs/adr/2026-07-09-retire-cpu-effect-path.md),
/// so `MetalEffectError` propagates to the caller instead of triggering a
/// silently different CPU render. Regression coverage anchors to frozen
/// golden references in EffectGPUGoldenTests.
public enum ShaderRenderer {
    public static func apply(
        to image: CGImage,
        params: ShaderLayerParams,
        previewBaseDimension: Int? = nil,
        sourceImage: CGImage? = nil,
        sourceIdentity: String? = nil
    ) throws -> CGImage {
        try Task.checkCancellation()

        switch params.params {
        case .ascii:
            return try TextCellRenderer.renderASCII(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension,
                sourceImage: sourceImage
            )
        case .pixelSort:
            // Spans ≤ 24 read every pixel in the span (exact rank); longer
            // spans are sub-sampled by the shader — the 24-sample
            // approximation from grainrad/notes/pixel-sort.md.
            return try PixelSortRenderer.render(to: image, params: params)
        case .crimewave:
            return try ColorGradeRenderer.renderCrimewave(to: image, params: params)
        case .narc:
            return try ColorGradeRenderer.renderNarc(to: image, params: params)
        case .shiba:
            return try ColorGradeRenderer.renderShiba(to: image, params: params)
        case .distantPast:
            return try DistantPastRenderer.render(to: image, params: params)
        case .crt:
            return try CRTRenderer.render(to: image, params: params)
        case .halftone:
            return try HalftoneRenderer.render(to: image, params: params)
        case .kuwahara:
            return try KuwaharaRenderer.render(to: image, params: params)
        case .roughBorder:
            return try RoughBorderRenderer.render(to: image, params: params, sourceIdentity: sourceIdentity)
        case .filmGrain:
            return try FilmGrainRenderer.render(
                to: image,
                params: params,
                previewBaseDimension: previewBaseDimension,
                sourceIdentity: sourceIdentity
            )
        }
    }
}
