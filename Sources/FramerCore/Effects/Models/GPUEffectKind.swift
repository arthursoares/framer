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

    /// Variants shown in the layer-add picker. Filters out four variants:
    ///
    ///   - `.ascii`     → better-tuned + GPU-accelerated as `.shader` ASCII
    ///   - `.halftone`  → better-tuned + GPU-accelerated as `.shader` Halftone
    ///   - `.pixelSort` → better-tuned + GPU-accelerated as `.shader` PixelSort
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
    /// The enum cases themselves are preserved (YAML back-compat, preset
    /// roundtrip, Codable).
    public static var userFacingCases: [GPUEffectKind] {
        allCases.filter { kind in
            switch kind {
            case .ascii, .halftone, .pixelSort, .dithering: return false
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

    /// Does the shader use `color.backgroundIntensity` as a general "paper
    /// level" (max'd against the computed ink)?
    public var usesBackgroundIntensity: Bool {
        switch self {
        case .edgeDetection, .contour, .waveLines, .voronoi, .noiseField: return true
        default: return false
        }
    }

    /// Common adjustments (brightness / contrast / saturation / hueRotation /
    /// sharpness / gamma). Currently no bucket shader consumes these — they
    /// were carried through for uniform layout symmetry but never wired into
    /// any fragment. Hide globally.
    public var usesCommonAdjustments: Bool { false }

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

    /// Build a fresh `.gpuEffect` layer pre-scoped to this kind with sensible
    /// default parameters. Used by the per-variant add-layer menu entries so
    /// each effect is a first-class layer type in the UI while sharing the
    /// same underlying data model.
    public func makeDefaultLayer() -> CompositionLayer {
        let common   = GPUEffectCommonParameters()
        let geometry = GPUEffectGeometryParameters(scale: 1.0, spacing: 2.0, outputWidth: 240)
        let color    = GPUEffectColorParameters(mode: .foregroundBackground, backgroundIntensity: 0.2)

        let params: GPUEffectParameters
        switch self {
        // TextCell bucket
        case .ascii:
            var p = TextCellParameters(); p.variant = .ascii
            params = .textCell(common: common, geometry: geometry, color: color, textCell: p)
        case .dots:
            var p = TextCellParameters(); p.variant = .dots
            params = .textCell(common: common, geometry: geometry, color: color, textCell: p)
        case .blockify:
            var p = TextCellParameters(); p.variant = .blockify
            params = .textCell(common: common, geometry: geometry, color: color, textCell: p)
        case .matrixRain:
            var p = TextCellParameters()
            p.variant = .matrixRain
            p.direction = .down
            p.trailLength = 0.5
            p.glow = 0.5
            params = .textCell(common: common, geometry: geometry, color: color, textCell: p)

        // PrintSampling bucket
        case .threshold:
            var p = PrintSamplingParameters()
            p.variant = .threshold
            p.threshold = 0.5
            p.thresholdLevels = 2
            params = .printSampling(common: common, geometry: geometry, color: color, printSampling: p)
        case .crosshatch:
            var p = PrintSamplingParameters()
            p.variant = .crosshatch
            p.threshold = 0.5
            p.hatchDensity = 0.5
            p.hatchLayers = 2
            params = .printSampling(common: common, geometry: geometry, color: color, printSampling: p)
        case .halftone:
            var p = PrintSamplingParameters(); p.variant = .halftone
            params = .printSampling(common: common, geometry: geometry, color: color, printSampling: p)
        case .dithering:
            var p = PrintSamplingParameters(); p.variant = .dithering
            params = .printSampling(common: common, geometry: geometry, color: color, printSampling: p)

        // EdgeField bucket
        case .edgeDetection:
            var p = EdgeFieldParameters()
            p.variant = .edgeDetection
            p.lineStrength = 0.7
            p.thickness = 0.3
            p.edgeAlgorithm = .sobel
            p.edgeThreshold = 0.2
            params = .edgeField(common: common, geometry: geometry, color: color, edgeField: p)
        case .contour:
            var p = EdgeFieldParameters()
            p.variant = .contour
            p.lineStrength = 0.5
            p.thickness = 0.3
            p.contourLevels = 8
            p.contourFillMode = .linesOnly
            params = .edgeField(common: common, geometry: geometry, color: color, edgeField: p)
        case .waveLines:
            var p = EdgeFieldParameters()
            p.variant = .waveLines
            p.lineStrength = 0.5
            p.thickness = 0.3
            p.amplitude = 0.5
            p.frequency = 1.0
            p.direction = .horizontal
            params = .edgeField(common: common, geometry: geometry, color: color, edgeField: p)
        case .voronoi:
            var p = EdgeFieldParameters()
            p.variant = .voronoi
            p.cellSize = 16.0
            p.edgeWidth = 0.25
            p.lineStrength = 0.5
            params = .edgeField(common: common, geometry: geometry, color: color, edgeField: p)
        case .noiseField:
            var p = EdgeFieldParameters()
            p.variant = .noiseField
            p.amplitude = 0.5
            p.fieldIntensity = 0.5
            params = .edgeField(common: common, geometry: geometry, color: color, edgeField: p)

        // Glitch bucket
        case .pixelSort:
            var p = GlitchParameters(); p.variant = .pixelSort
            params = .glitch(common: common, geometry: geometry, color: color, glitch: p)
        case .vhs:
            var p = GlitchParameters()
            p.variant = .vhs
            p.amount = 0.5
            p.scanlines = 0.5
            p.colorBleed = 0.5
            p.trackingError = 0.3
            params = .glitch(common: common, geometry: geometry, color: color, glitch: p)
        }

        return .gpuEffect(GPUEffectLayerParams(kind: self, params: params))
    }
}
