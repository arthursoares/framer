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
