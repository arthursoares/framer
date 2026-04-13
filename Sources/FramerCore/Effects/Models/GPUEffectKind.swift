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

    /// Variants shown in the layer-add picker. Excludes the three variants
    /// that duplicate an existing `.shader` layer type with a different
    /// (and better-tuned + GPU-accelerated) parameter surface:
    ///   - `.ascii`     → already exposed as `.shader` ShaderStyle.ascii
    ///   - `.halftone`  → already exposed as `.shader` ShaderStyle.halftone
    ///   - `.pixelSort` → already exposed as `.shader` ShaderStyle.pixelSort
    /// Without this filter the layer picker offered two different halftones,
    /// two ASCIIs, and two pixel sorts with overlapping-but-different
    /// parameter sets. The enum cases themselves are preserved (YAML
    /// back-compat, preset roundtrip, Codable).
    public static var userFacingCases: [GPUEffectKind] {
        allCases.filter { kind in
            switch kind {
            case .ascii, .halftone, .pixelSort: return false
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
