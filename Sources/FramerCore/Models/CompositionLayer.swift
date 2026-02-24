import Foundation
import CoreGraphics

// MARK: - LayerFill

public enum LayerFill: Codable, Equatable, Sendable {
    case color(CodableColor)
    case dominantColor
    case gradientLinear
    case gradientRadial

    private enum CodingKeys: String, CodingKey {
        case type, color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "color":
            let c = try container.decode(CodableColor.self, forKey: .color)
            self = .color(c)
        case "dominant":
            self = .dominantColor
        case "gradient_linear":
            self = .gradientLinear
        case "gradient_radial":
            self = .gradientRadial
        default:
            self = .color(try! CodableColor(hex: "#FFFFFF"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let c):
            try container.encode("color", forKey: .type)
            try container.encode(c, forKey: .color)
        case .dominantColor:
            try container.encode("dominant", forKey: .type)
        case .gradientLinear:
            try container.encode("gradient_linear", forKey: .type)
        case .gradientRadial:
            try container.encode("gradient_radial", forKey: .type)
        }
    }
}

// MARK: - Layer Params

public struct BorderLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var thickness: BorderSize
    public var color: CodableColor

    public init(
        id: UUID = UUID(),
        thickness: BorderSize = .pixels(20),
        color: CodableColor = try! CodableColor(hex: "#FFFFFF")
    ) {
        self.id = id
        self.thickness = thickness
        self.color = color
    }
}

public struct PaddingLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var thickness: Int
    public var fill: LayerFill

    public init(
        id: UUID = UUID(),
        thickness: Int = 150,
        fill: LayerFill = .color(try! CodableColor(hex: "#FFFFFF"))
    ) {
        self.id = id
        self.thickness = thickness
        self.fill = fill
    }
}

public struct CanvasLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var width: Int
    public var height: Int
    public var fill: LayerFill

    public init(
        id: UUID = UUID(),
        width: Int = 1080,
        height: Int = 1350,
        fill: LayerFill = .color(try! CodableColor(hex: "#FFFFFF"))
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.fill = fill
    }
}

public struct ResizeLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var maxWidth: Int
    public var maxHeight: Int

    public init(
        id: UUID = UUID(),
        maxWidth: Int = 1000,
        maxHeight: Int = 1000
    ) {
        self.id = id
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }
}

// MARK: - CompositionLayer

public enum CompositionLayer: Identifiable, Codable, Equatable, Sendable {
    case border(BorderLayerParams)
    case padding(PaddingLayerParams)
    case canvas(CanvasLayerParams)
    case resize(ResizeLayerParams)

    public var id: UUID {
        switch self {
        case .border(let p): return p.id
        case .padding(let p): return p.id
        case .canvas(let p): return p.id
        case .resize(let p): return p.id
        }
    }

    public var label: String {
        switch self {
        case .border: return "Border"
        case .padding: return "Padding"
        case .canvas: return "Canvas"
        case .resize: return "Resize"
        }
    }

    public var iconName: String {
        switch self {
        case .border: return "square.dashed"
        case .padding: return "arrow.up.left.and.arrow.down.right"
        case .canvas: return "rectangle.on.rectangle"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "border":
            self = .border(try container.decode(BorderLayerParams.self, forKey: .params))
        case "padding":
            self = .padding(try container.decode(PaddingLayerParams.self, forKey: .params))
        case "canvas":
            self = .canvas(try container.decode(CanvasLayerParams.self, forKey: .params))
        case "resize":
            self = .resize(try container.decode(ResizeLayerParams.self, forKey: .params))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown layer type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .border(let p):
            try container.encode("border", forKey: .type)
            try container.encode(p, forKey: .params)
        case .padding(let p):
            try container.encode("padding", forKey: .type)
            try container.encode(p, forKey: .params)
        case .canvas(let p):
            try container.encode("canvas", forKey: .type)
            try container.encode(p, forKey: .params)
        case .resize(let p):
            try container.encode("resize", forKey: .type)
            try container.encode(p, forKey: .params)
        }
    }

    // MARK: - Legacy Conversion

    public static func fromLegacyConfig(_ config: ProcessingConfig) -> [CompositionLayer] {
        switch config.borderStyle {
        case .solid:
            return solidLayers(config)
        case .instagram:
            return instagramLayers(config)
        case .print(let format):
            return printLayers(config, format: format)
        }
    }

    public static func defaultLayers() -> [CompositionLayer] {
        [
            .border(BorderLayerParams(thickness: .pixels(20), color: try! CodableColor(hex: "#FFFFFF"))),
            .padding(PaddingLayerParams(thickness: 150, fill: .color(try! CodableColor(hex: "#FFFFFF"))))
        ]
    }

    // MARK: - Legacy Helpers

    private static func fillFromBackgroundMode(_ mode: BackgroundMode, color: CodableColor) -> LayerFill {
        switch mode {
        case .color: return .color(color)
        case .dominant: return .dominantColor
        case .gradientLinear: return .gradientLinear
        case .gradientRadial: return .gradientRadial
        }
    }

    private static func solidLayers(_ config: ProcessingConfig) -> [CompositionLayer] {
        let bgFill = fillFromBackgroundMode(config.backgroundMode, color: config.backgroundColor)
        return [
            .border(BorderLayerParams(thickness: config.borderThickness, color: config.borderColor)),
            .padding(PaddingLayerParams(thickness: config.padding, fill: bgFill))
        ]
    }

    private static func instagramLayers(_ config: ProcessingConfig) -> [CompositionLayer] {
        let bgFill = fillFromBackgroundMode(config.backgroundMode, color: config.backgroundColor)
        return [
            .resize(ResizeLayerParams(maxWidth: config.instagramMaxSize, maxHeight: config.instagramMaxSize)),
            .padding(PaddingLayerParams(thickness: config.padding, fill: .color(try! CodableColor(hex: "#FFFFFF")))),
            .border(BorderLayerParams(thickness: config.borderThickness, color: config.borderColor)),
            .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: bgFill))
        ]
    }

    private static func printLayers(_ config: ProcessingConfig, format: PrintFormat) -> [CompositionLayer] {
        let bgFill = fillFromBackgroundMode(config.backgroundMode, color: config.backgroundColor)
        return [
            .resize(ResizeLayerParams(
                maxWidth: format.widthPixels - 2 * config.outerPadding,
                maxHeight: format.heightPixels - 2 * config.outerPadding
            )),
            .border(BorderLayerParams(thickness: config.borderThickness, color: config.borderColor)),
            .canvas(CanvasLayerParams(width: format.widthPixels, height: format.heightPixels, fill: bgFill))
        ]
    }
}
