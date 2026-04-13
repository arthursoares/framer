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
}
