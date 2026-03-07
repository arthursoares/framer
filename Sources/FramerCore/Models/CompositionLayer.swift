import Foundation
import CoreGraphics

// MARK: - LayerFill

public struct GradientParams: Codable, Equatable, Sendable {
    public var saturationShift: Double  // -50...+50, default 0
    public var lightnessShift: Double   // -50...+50, default 0

    public init(saturationShift: Double = 0, lightnessShift: Double = 0) {
        self.saturationShift = saturationShift
        self.lightnessShift = lightnessShift
    }
}

public enum LayerFill: Codable, Equatable, Sendable {
    case color(CodableColor)
    case dominantColor
    case gradientLinear(GradientParams = GradientParams())
    case gradientRadial(GradientParams = GradientParams())

    private enum CodingKeys: String, CodingKey {
        case type, color, gradientParams
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
            let params = try container.decodeIfPresent(GradientParams.self, forKey: .gradientParams) ?? GradientParams()
            self = .gradientLinear(params)
        case "gradient_radial":
            let params = try container.decodeIfPresent(GradientParams.self, forKey: .gradientParams) ?? GradientParams()
            self = .gradientRadial(params)
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
        case .gradientLinear(let params):
            try container.encode("gradient_linear", forKey: .type)
            try container.encode(params, forKey: .gradientParams)
        case .gradientRadial(let params):
            try container.encode("gradient_radial", forKey: .type)
            try container.encode(params, forKey: .gradientParams)
        }
    }

    /// Whether this fill is a gradient variant (linear or radial).
    public var isGradient: Bool {
        switch self {
        case .gradientLinear, .gradientRadial: return true
        default: return false
        }
    }

    /// The gradient parameters, if this is a gradient fill.
    public var gradientParams: GradientParams? {
        switch self {
        case .gradientLinear(let p), .gradientRadial(let p): return p
        default: return nil
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

/// Categories for texture overlays, distinguishing border frames from surface textures.
public enum OverlayKind: String, Codable, CaseIterable, Sendable {
    case frame      // Film edges, Polaroid borders, darkroom frames
    case dust       // Scratches, film dust, surface grime
    case lightLeak  // Light leak effects
    case wetPlate   // Tintype / wet plate collodion

    public var label: String {
        switch self {
        case .frame: return "Frame"
        case .dust: return "Dust & Scratches"
        case .lightLeak: return "Light Leak"
        case .wetPlate: return "Wet Plate"
        }
    }

    /// File name prefix used to auto-categorize discovered overlays.
    public var filePrefix: String {
        switch self {
        case .frame: return "frame"
        case .dust: return "dirt"
        case .lightLeak: return "leak"
        case .wetPlate: return "plate"
        }
    }

    /// Categorize a filename stem into an overlay kind.
    public static func from(filename: String) -> OverlayKind {
        let lower = filename.lowercased()
        if lower.hasPrefix("dirt") { return .dust }
        if lower.hasPrefix("leak") { return .lightLeak }
        if lower.hasPrefix("plate") { return .wetPlate }
        return .frame
    }
}

/// Blend mode for compositing overlays onto the photo.
public enum OverlayBlendMode: String, Codable, CaseIterable, Sendable {
    case normal     // Luminance-deviation alpha composite (default for frames, dust)
    case screen     // Additive: 1-(1-base)(1-overlay) — only lightens (light leaks)
    case softLight  // Subtle contrast shift (wet plate, film grain)
    case multiply   // Darkening: base × overlay (vignettes, burn edges)

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .screen: return "Screen"
        case .softLight: return "Soft Light"
        case .multiply: return "Multiply"
        }
    }

    /// Recommended default blend mode for each overlay kind.
    public static func defaultFor(_ kind: OverlayKind) -> OverlayBlendMode {
        switch kind {
        case .frame: return .normal
        case .dust: return .normal
        case .lightLeak: return .screen
        case .wetPlate: return .softLight
        }
    }
}

public struct OverlayLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var overlayName: String
    public var kind: OverlayKind
    public var blendMode: OverlayBlendMode
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        overlayName: String = "",
        kind: OverlayKind = .frame,
        blendMode: OverlayBlendMode? = nil,
        opacity: Double = 100
    ) {
        self.id = id
        self.overlayName = overlayName
        self.kind = kind
        self.blendMode = blendMode ?? OverlayBlendMode.defaultFor(kind)
        self.opacity = opacity
    }
}

// MARK: - Orientation

public enum OrientationTarget: String, Codable, CaseIterable, Sendable {
    case landscape
    case portrait
}

public struct OrientationLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var target: OrientationTarget

    public init(
        id: UUID = UUID(),
        target: OrientationTarget = .landscape
    ) {
        self.id = id
        self.target = target
    }
}

// MARK: - Caption

public struct CaptionLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var mode: CaptionMode
    public var fontName: String
    public var fontSize: FontSize
    public var fontStyle: FontStyle
    public var fontColor: CodableColor
    public var alignment: CaptionAlignment
    public var position: CaptionPosition
    public var offsetX: Int
    public var offsetY: Int

    public init(
        id: UUID = UUID(),
        mode: CaptionMode = .template(" - {{mon}} '{{year2}} -"),
        fontName: String = "Courier New",
        fontSize: FontSize = .auto,
        fontStyle: FontStyle = [],
        fontColor: CodableColor = try! CodableColor(hex: "#000000"),
        alignment: CaptionAlignment = .center,
        position: CaptionPosition = .bottom,
        offsetX: Int = 0,
        offsetY: Int = 0
    ) {
        self.id = id
        self.mode = mode
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontStyle = fontStyle
        self.fontColor = fontColor
        self.alignment = alignment
        self.position = position
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

// MARK: - CompositionLayer

public enum CompositionLayer: Identifiable, Codable, Equatable, Sendable {
    case border(BorderLayerParams)
    case padding(PaddingLayerParams)
    case canvas(CanvasLayerParams)
    case resize(ResizeLayerParams)
    case overlay(OverlayLayerParams)
    case orientation(OrientationLayerParams)
    case caption(CaptionLayerParams)

    public var id: UUID {
        switch self {
        case .border(let p): return p.id
        case .padding(let p): return p.id
        case .canvas(let p): return p.id
        case .resize(let p): return p.id
        case .overlay(let p): return p.id
        case .orientation(let p): return p.id
        case .caption(let p): return p.id
        }
    }

    public var label: String {
        switch self {
        case .border: return "Border"
        case .padding: return "Padding"
        case .canvas: return "Canvas"
        case .resize: return "Resize"
        case .overlay(let p): return p.kind == .frame ? "Frame" : "Texture"
        case .orientation: return "Orientation"
        case .caption: return "Caption"
        }
    }

    public var iconName: String {
        switch self {
        case .border: return "square.dashed"
        case .padding: return "arrow.up.left.and.arrow.down.right"
        case .canvas: return "rectangle.on.rectangle"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        case .overlay(let p): return p.kind == .frame ? "photo.artframe" : "sparkles"
        case .orientation: return "rotate.right"
        case .caption: return "textformat"
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
        case "overlay":
            self = .overlay(try container.decode(OverlayLayerParams.self, forKey: .params))
        case "orientation":
            self = .orientation(try container.decode(OrientationLayerParams.self, forKey: .params))
        case "caption":
            self = .caption(try container.decode(CaptionLayerParams.self, forKey: .params))
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
        case .overlay(let p):
            try container.encode("overlay", forKey: .type)
            try container.encode(p, forKey: .params)
        case .orientation(let p):
            try container.encode("orientation", forKey: .type)
            try container.encode(p, forKey: .params)
        case .caption(let p):
            try container.encode("caption", forKey: .type)
            try container.encode(p, forKey: .params)
        }
    }

    public static func defaultLayers() -> [CompositionLayer] {
        [
            .border(BorderLayerParams(thickness: .pixels(20), color: try! CodableColor(hex: "#FFFFFF"))),
            .padding(PaddingLayerParams(thickness: 150, fill: .color(try! CodableColor(hex: "#FFFFFF")))),
            .caption(CaptionLayerParams())
        ]
    }

}
