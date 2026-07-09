import Foundation

public enum GPUEffectKind: String, Codable, Hashable, Sendable, CaseIterable {
    case ascii
    case dithering
    case halftone
    case matrixRain
    case dots
    case contour
    case pixelSort
    case blockify
    case threshold
    case edgeDetection
    case crosshatch
    case waveLines
    case noiseField
    case voronoi
    case vhs

    /// Variants shown in the layer-add picker. Filters out three variants:
    ///
    ///   - `.ascii`     → better-tuned + GPU-accelerated as `.shader` ASCII
    ///   - `.halftone`  → better-tuned + GPU-accelerated as `.shader` Halftone
    ///   - `.dithering` → the `.dither` Layer type is the canonical dither
    ///     path. It's GPU-accelerated, exposes all 17 dither algorithms
    ///     (Bayer / Floyd-Steinberg / Atkinson / Sierra family / JJN /
    ///     Burkes / IGN / Halftone / etc.) AND the four vintage palettes
    ///     (Game Boy / NES / C64 / CGA). The bucket system's
    ///     `.printSampling.dithering` variant only supports 3 algorithms
    ///     and no palette picker, which users hit immediately (reported
    ///     during the GPU migration session as "Dithering doesn't have
    ///     the presets"). Hiding it from the picker avoids the half-shipped
    ///     feature surface.
    ///
    /// PixelSort is exposed here as of sidebar harmony pass 4 — its GPU path
    /// routes through PixelSort.metal via `GlitchGPURenderer.renderPixelSort`
    /// (the same shader the `.shader` layer uses). The bucket path is GPU-only:
    /// the `GlitchRenderer` CPU loop was removed with the PR #12 merge, so
    /// Metal-less hosts get a thrown `MetalEffectError`, not a CPU render.
    ///
    /// The enum cases themselves are preserved (YAML back-compat, preset
    /// roundtrip, Codable).
    public static var userFacingCases: [GPUEffectKind] {
        allCases.filter { kind in
            switch kind {
            case .ascii, .halftone, .dithering: return false
            default: return true
            }
        }
    }

    public var label: String {
        switch self {
        case .ascii: return "ASCII"
        case .dithering: return "Dithering"
        case .halftone: return "Halftone"
        case .matrixRain: return "Matrix Rain"
        case .dots: return "Dots"
        case .contour: return "Contour"
        case .pixelSort: return "Pixel Sort"
        case .blockify: return "Blockify"
        case .threshold: return "Threshold"
        case .edgeDetection: return "Edge Detection"
        case .crosshatch: return "Crosshatch"
        case .waveLines: return "Wave Lines"
        case .noiseField: return "Noise Field"
        case .voronoi: return "Voronoi"
        case .vhs: return "VHS"
        }
    }

    // MARK: - Shader capability flags (drives per-variant UI pruning)
    //
    // The UI exposes a common / geometry / color block on every variant today
    // even when the shader ignores them. These flags let the UI render only
    // controls whose values the variant's Metal shader actually reads.
    // Source: docs/gpu-effects-parameter-matrix.md (per-variant inventory).

    /// Does the shader read `geometry.scale` + `geometry.spacing` for cell
    /// pitch? Only TextCell family (the shared `textCellFragment` uses
    /// `8.0 * spacing * scale` as the base cell pitch).
    public var usesGeometry: Bool {
        switch self {
        case .dots, .blockify, .matrixRain, .ascii: return true
        default: return false
        }
    }

    /// Does the shader consume `color.mode` + foregroundRGBA / backgroundRGBA
    /// to paint ink / paper colours?
    public var usesColorModeAndFgBg: Bool {
        switch self {
        case .dots, .blockify, .matrixRain, .threshold, .crosshatch, .edgeDetection: return true
        default: return false
        }
    }

    /// Does the variant's shader implement `.palette` colour mode
    /// (quantizing its output against `GPUEffectColorParameters.palette`
    /// via `framerPalettePick` in ShaderCommon.h)? Drives whether the
    /// colour-mode picker offers "Palette" and shows the palette editor.
    /// MatrixRain is excluded — its glyph colour comes from `rainColor`,
    /// not the shared colour block.
    public var usesPalette: Bool {
        switch self {
        case .dots, .blockify, .threshold, .crosshatch, .edgeDetection: return true
        default: return false
        }
    }

    /// Does the shader use `color.backgroundIntensity` as a general "paper
    /// level" (max'd against the computed ink)?
    public var usesBackgroundIntensity: Bool {
        switch self {
        case .edgeDetection, .contour, .waveLines, .voronoi, .noiseField: return true
        default: return false
        }
    }

    /// Common adjustments (brightness / contrast / saturation / hueRotation /
    /// gamma). All bucket fragments EXCEPT pixelSort wrap their source sample
    /// in `applyCommonAdjustments` (see ShaderCommon.h); flipping this true
    /// surfaces the standard adjustment controls in the sidebar. (A
    /// `sharpness` field used to exist here but no shader ever consumed it;
    /// the model field was retired — only the Metal uniform slot remains,
    /// always written as 0, to preserve struct layout.)
    ///
    /// PixelSort returns false — Effects/Metal/PixelSort.metal marks its
    /// `colorBlock` uniform as unused and never calls
    /// `applyCommonAdjustments(u.common, …)`, so the common-adjustment sliders
    /// would show as inert controls (the same pattern as the Sharpness slider
    /// we removed in pass 3). Wire a colour pre-pass into both GPU and CPU
    /// pixel-sort paths before flipping this to true.
    public var usesCommonAdjustments: Bool {
        switch self {
        case .pixelSort: return false
        default: return true
        }
    }

    /// SF Symbol name for the layer-add menu entry.
    public var menuIcon: String {
        switch self {
        case .ascii:         return "textformat"
        case .dithering:     return "square.grid.4x3.fill"
        case .halftone:      return "circle.dotted"
        case .matrixRain:    return "cloud.rain"
        case .dots:          return "circle.grid.3x3.fill"
        case .contour:       return "map"
        case .pixelSort:     return "rectangle.split.3x1"
        case .blockify:      return "square.grid.3x3.fill"
        case .threshold:     return "circle.lefthalf.filled"
        case .edgeDetection: return "scope"
        case .crosshatch:    return "line.diagonal"
        case .waveLines:     return "waveform"
        case .noiseField:    return "sparkle"
        case .voronoi:       return "hexagon"
        case .vhs:           return "tv"
        }
    }

    /// Canonical per-kind default parameters. Single source of truth for
    /// BOTH the add-layer path (`makeDefaultLayer`) and the kind-switch
    /// path in the macOS / iOS inspectors — previously each UI carried its
    /// own duplicated `defaultParams(for:)` with values that had drifted
    /// from this file (e.g. pixelSort amount 0.65 vs 0.5, vhs scanlines 0
    /// vs 0.5, and a waveLines `.palette` color mode that no bucket shader
    /// reads and no picker offers).
    ///
    /// Geometry/color are tuned per kind (dots reads best monochrome,
    /// halftone over source colour, etc.); payload values keep the
    /// add-layer tuning from the per-variant add-menu pass.
    public func defaultParameters() -> GPUEffectParameters {
        let common = GPUEffectCommonParameters()

        switch self {
        // TextCell bucket
        case .ascii:
            return .textCell(
                common: common,
                geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .foregroundBackground, backgroundIntensity: 0.2),
                textCell: .init(variant: .ascii)
            )
        case .dots:
            return .textCell(
                common: common,
                geometry: .init(scale: 0.9, spacing: 4.0, outputWidth: 240),
                color: .init(mode: .monochrome, backgroundIntensity: 0.1),
                textCell: .init(variant: .dots)
            )
        case .blockify:
            return .textCell(
                common: common,
                geometry: .init(scale: 1.0, spacing: 3.0, outputWidth: 240),
                color: .init(mode: .source, backgroundIntensity: 0.0),
                textCell: .init(variant: .blockify)
            )
        case .matrixRain:
            return .textCell(
                common: common,
                geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .foregroundBackground, backgroundIntensity: 0.2),
                textCell: .init(variant: .matrixRain, trailLength: 0.5, direction: .down, glow: 0.5)
            )

        // PrintSampling bucket
        case .threshold:
            return .printSampling(
                common: common,
                geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .monochrome, backgroundIntensity: 0.2),
                printSampling: .init(variant: .threshold, threshold: 0.5, thresholdLevels: 2)
            )
        case .crosshatch:
            return .printSampling(
                common: common,
                geometry: .init(scale: 0.8, spacing: 4.0, outputWidth: 240),
                color: .init(mode: .foregroundBackground, backgroundIntensity: 0.15),
                printSampling: .init(variant: .crosshatch, threshold: 0.5, hatchDensity: 0.5, hatchLayers: 2)
            )
        case .halftone:
            return .printSampling(
                common: common,
                geometry: .init(scale: 0.9, spacing: 3.0, outputWidth: 240),
                color: .init(mode: .source, backgroundIntensity: 0.0),
                printSampling: .init(variant: .halftone, sampleDensity: 0.7, threshold: 0.4)
            )
        case .dithering:
            return .printSampling(
                common: common,
                geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .monochrome, backgroundIntensity: 0.1),
                printSampling: .init(variant: .dithering)
            )

        // EdgeField bucket
        case .edgeDetection:
            return .edgeField(
                common: common,
                geometry: .init(scale: 0.9, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .foregroundBackground, backgroundIntensity: 0.1),
                edgeField: .init(variant: .edgeDetection, lineStrength: 0.7, thickness: 0.3, edgeAlgorithm: .sobel, edgeThreshold: 0.2)
            )
        case .contour:
            return .edgeField(
                common: common,
                geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .monochrome, backgroundIntensity: 0.05),
                edgeField: .init(variant: .contour, lineStrength: 0.5, fieldIntensity: 0.7, thickness: 0.3, contourFillMode: .linesOnly, contourLevels: 8)
            )
        case .waveLines:
            return .edgeField(
                common: common,
                geometry: .init(scale: 1.2, spacing: 4.0, outputWidth: 240),
                // Was `.palette` in the old UI-side defaults — dead value:
                // no bucket shader reads a palette uniform and the color
                // mode picker no longer offers it.
                color: .init(mode: .monochrome, backgroundIntensity: 0.2),
                edgeField: .init(variant: .waveLines, lineStrength: 0.5, fieldIntensity: 0.9, amplitude: 0.5, frequency: 1.0, thickness: 0.3, direction: .horizontal)
            )
        case .voronoi:
            return .edgeField(
                common: common,
                geometry: .init(scale: 1.1, spacing: 3.0, outputWidth: 240),
                color: .init(mode: .source, backgroundIntensity: 0.0),
                edgeField: .init(variant: .voronoi, lineStrength: 0.5, fieldIntensity: 0.85, cellSize: 16.0, edgeWidth: 0.25)
            )
        case .noiseField:
            return .edgeField(
                common: common,
                geometry: .init(scale: 0.8, spacing: 5.0, outputWidth: 240),
                color: .init(mode: .monochrome, backgroundIntensity: 0.15),
                edgeField: .init(variant: .noiseField, fieldIntensity: 0.5, amplitude: 0.5)
            )

        // Glitch bucket
        case .pixelSort:
            return .glitch(
                common: common,
                geometry: .init(scale: 1.0, spacing: 1.0, outputWidth: 240),
                color: .init(mode: .source, backgroundIntensity: 0.0),
                glitch: .init(variant: .pixelSort)
            )
        case .vhs:
            return .glitch(
                common: common,
                geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                color: .init(mode: .foregroundBackground, backgroundIntensity: 0.08),
                glitch: .init(variant: .vhs, amount: 0.5, colorBleed: 0.5, scanlines: 0.5, trackingError: 0.3)
            )
        }
    }

    /// Build a fresh `.gpuEffect` layer pre-scoped to this kind with sensible
    /// default parameters. Used by the per-variant add-layer menu entries so
    /// each effect is a first-class layer type in the UI while sharing the
    /// same underlying data model.
    public func makeDefaultLayer() -> CompositionLayer {
        .gpuEffect(GPUEffectLayerParams(kind: self, params: defaultParameters()))
    }
}
