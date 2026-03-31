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

    public static let none = GradientParams()
}

public enum LayerFill: Codable, Equatable, Sendable {
    case color(CodableColor)
    case dominantColor(GradientParams = GradientParams())
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
            let params = try container.decodeIfPresent(GradientParams.self, forKey: .gradientParams) ?? GradientParams()
            self = .dominantColor(params)
        case "gradient_linear":
            let params = try container.decodeIfPresent(GradientParams.self, forKey: .gradientParams) ?? GradientParams()
            self = .gradientLinear(params)
        case "gradient_radial":
            let params = try container.decodeIfPresent(GradientParams.self, forKey: .gradientParams) ?? GradientParams()
            self = .gradientRadial(params)
        default:
            self = .color(.white)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let c):
            try container.encode("color", forKey: .type)
            try container.encode(c, forKey: .color)
        case .dominantColor(let params):
            try container.encode("dominant", forKey: .type)
            try container.encode(params, forKey: .gradientParams)
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

    /// Whether this fill uses dominant color extraction.
    public var isDominant: Bool {
        switch self {
        case .dominantColor, .gradientLinear, .gradientRadial: return true
        default: return false
        }
    }

    /// The color adjustment parameters, if available.
    public var gradientParams: GradientParams? {
        switch self {
        case .dominantColor(let p), .gradientLinear(let p), .gradientRadial(let p): return p
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
        color: CodableColor = .white
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
        fill: LayerFill = .color(.white)
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
        fill: LayerFill = .color(.white)
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

public enum CaptionColorMode: Codable, Equatable, Sendable {
    case fixed(CodableColor)
    case dominant
    case dominantInverted

    private enum CodingKeys: String, CodingKey {
        case type, color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "fixed":
            let c = try container.decode(CodableColor.self, forKey: .color)
            self = .fixed(c)
        case "dominant":
            self = .dominant
        case "dominantInverted":
            self = .dominantInverted
        default:
            self = .fixed(.black)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixed(let c):
            try container.encode("fixed", forKey: .type)
            try container.encode(c, forKey: .color)
        case .dominant:
            try container.encode("dominant", forKey: .type)
        case .dominantInverted:
            try container.encode("dominantInverted", forKey: .type)
        }
    }
}

public struct CaptionLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var mode: CaptionMode
    public var fontName: String
    public var fontSize: FontSize
    public var fontStyle: FontStyle
    public var fontColorMode: CaptionColorMode
    public var alignment: CaptionAlignment
    public var position: CaptionPosition
    public var offsetX: Int
    public var offsetY: Int

    /// Convenience accessor for backward compatibility.
    public var fontColor: CodableColor {
        get {
            if case .fixed(let c) = fontColorMode { return c }
            return .black
        }
        set { fontColorMode = .fixed(newValue) }
    }

    public init(
        id: UUID = UUID(),
        mode: CaptionMode = .template(" - {{mon}} '{{year2}} -"),
        fontName: String = "Courier New",
        fontSize: FontSize = .auto,
        fontStyle: FontStyle = [],
        fontColor: CodableColor = .black,
        fontColorMode: CaptionColorMode? = nil,
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
        self.fontColorMode = fontColorMode ?? .fixed(fontColor)
        self.alignment = alignment
        self.position = position
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, fontName, fontSize, fontStyle, fontColor, fontColorMode
        case alignment, position, offsetX, offsetY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mode = try container.decode(CaptionMode.self, forKey: .mode)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSize = try container.decode(FontSize.self, forKey: .fontSize)
        fontStyle = try container.decode(FontStyle.self, forKey: .fontStyle)
        alignment = try container.decode(CaptionAlignment.self, forKey: .alignment)
        position = try container.decode(CaptionPosition.self, forKey: .position)
        offsetX = try container.decodeIfPresent(Int.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(Int.self, forKey: .offsetY) ?? 0

        // Prefer new fontColorMode; fall back to legacy fontColor field
        if let fcm = try? container.decode(CaptionColorMode.self, forKey: .fontColorMode) {
            fontColorMode = fcm
        } else {
            let c = try container.decodeIfPresent(CodableColor.self, forKey: .fontColor) ?? .black
            fontColorMode = .fixed(c)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontStyle, forKey: .fontStyle)
        try container.encode(fontColorMode, forKey: .fontColorMode)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(position, forKey: .position)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
    }
}

// MARK: - Dither

public enum DitherAlgorithm: String, Codable, Sendable, CaseIterable {
    case bayer
    case floydSteinberg
    case atkinson
    case blueNoise
    case artisticDrip
    case halftone
    case stucki
    case whiteNoise
    case riemersma

    public var label: String {
        switch self {
        case .bayer: return "Bayer"
        case .floydSteinberg: return "Floyd-Steinberg"
        case .atkinson: return "Atkinson"
        case .blueNoise: return "Blue Noise"
        case .artisticDrip: return "Artistic Drip"
        case .halftone: return "Halftone"
        case .stucki: return "Stucki"
        case .whiteNoise: return "White Noise"
        case .riemersma: return "Riemersma"
        }
    }

    /// Whether this algorithm uses error diffusion (benefits from serpentine scanning).
    public var isErrorDiffusion: Bool {
        switch self {
        case .floydSteinberg, .atkinson, .artisticDrip, .stucki, .riemersma: return true
        default: return false
        }
    }
}

public enum DitherColorMode: Codable, Equatable, Sendable {
    case bw
    case twoTone(foreground: CodableColor, background: CodableColor)
    /// Two-tone using the two most dominant high-contrast colors from the image.
    /// When `flipped` is true, foreground and background are swapped.
    case dominantTwoTone(flipped: Bool)
    case color(levels: Int)

    private enum CodingKeys: String, CodingKey {
        case type, foreground, background, levels, flipped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "bw": self = .bw
        case "twoTone":
            let fg = try container.decode(CodableColor.self, forKey: .foreground)
            let bg = try container.decode(CodableColor.self, forKey: .background)
            self = .twoTone(foreground: fg, background: bg)
        case "dominantTwoTone":
            let flipped = try container.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
            self = .dominantTwoTone(flipped: flipped)
        case "color":
            let levels = try container.decode(Int.self, forKey: .levels)
            self = .color(levels: levels)
        default: self = .bw
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bw: try container.encode("bw", forKey: .type)
        case .twoTone(let fg, let bg):
            try container.encode("twoTone", forKey: .type)
            try container.encode(fg, forKey: .foreground)
            try container.encode(bg, forKey: .background)
        case .dominantTwoTone(let flipped):
            try container.encode("dominantTwoTone", forKey: .type)
            if flipped { try container.encode(true, forKey: .flipped) }
        case .color(let levels):
            try container.encode("color", forKey: .type)
            try container.encode(levels, forKey: .levels)
        }
    }
}

public struct DitherLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var algorithm: DitherAlgorithm
    public var colorMode: DitherColorMode
    public var bayerLevel: Int
    public var pixelScale: Int
    /// Controls the black/white decision point (0.1–0.9, default 0.5).
    /// Lower = darker output (more black), higher = brighter output (more white).
    public var threshold: Double
    /// Pre-sharpen amount before dithering (0–1, default 0 = off).
    /// Enhances edge detail that would otherwise be lost during quantization.
    public var sharpen: Double
    /// Contrast boost before dithering (0–1, default 0 = no change).
    /// Applies an S-curve to expand tonal range before quantization.
    public var contrast: Double

    public init(
        id: UUID = UUID(),
        algorithm: DitherAlgorithm = .atkinson,
        colorMode: DitherColorMode = .bw,
        bayerLevel: Int = 2,
        pixelScale: Int = 1,
        threshold: Double = 0.5,
        sharpen: Double = 0,
        contrast: Double = 0
    ) {
        self.id = id
        self.algorithm = algorithm
        self.colorMode = colorMode
        self.bayerLevel = max(1, min(4, bayerLevel))
        self.pixelScale = max(1, min(8, pixelScale))
        self.threshold = max(0.1, min(0.9, threshold))
        self.sharpen = max(0, min(1, sharpen))
        self.contrast = max(0, min(1, contrast))
    }
}

// MARK: - Aspect Ratio

public struct AspectRatioLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var ratioWidth: Int
    public var ratioHeight: Int
    public var offsetX: Double  // -1.0 (left) to 1.0 (right), 0 = center
    public var offsetY: Double  // -1.0 (bottom) to 1.0 (top), 0 = center

    public init(
        id: UUID = UUID(),
        ratioWidth: Int = 1,
        ratioHeight: Int = 1,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.id = id
        self.ratioWidth = max(1, ratioWidth)
        self.ratioHeight = max(1, ratioHeight)
        self.offsetX = max(-1, min(1, offsetX))
        self.offsetY = max(-1, min(1, offsetY))
    }

    /// Compute the crop rect for a given image size.
    public func cropRect(for imageSize: CGSize) -> CGRect {
        let targetRatio = CGFloat(ratioWidth) / CGFloat(ratioHeight)
        let imageRatio = imageSize.width / imageSize.height

        let cropW: CGFloat
        let cropH: CGFloat

        if targetRatio > imageRatio {
            cropW = imageSize.width
            cropH = imageSize.width / targetRatio
        } else {
            cropW = imageSize.height * targetRatio
            cropH = imageSize.height
        }

        let maxOffsetX = (imageSize.width - cropW) / 2
        let maxOffsetY = (imageSize.height - cropH) / 2

        let cropX = maxOffsetX + offsetX * maxOffsetX
        let cropY = maxOffsetY + offsetY * maxOffsetY

        return CGRect(
            x: cropX.rounded(.down),
            y: cropY.rounded(.down),
            width: cropW.rounded(.down),
            height: cropH.rounded(.down)
        )
    }

    /// Compute output size after cropping.
    public func croppedSize(for imageSize: CGSize) -> CGSize {
        let rect = cropRect(for: imageSize)
        return CGSize(width: rect.width, height: rect.height)
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
    case dither(DitherLayerParams)
    case aspectRatio(AspectRatioLayerParams)

    public var id: UUID {
        switch self {
        case .border(let p): return p.id
        case .padding(let p): return p.id
        case .canvas(let p): return p.id
        case .resize(let p): return p.id
        case .overlay(let p): return p.id
        case .orientation(let p): return p.id
        case .caption(let p): return p.id
        case .dither(let p): return p.id
        case .aspectRatio(let p): return p.id
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
        case .dither: return "Dither"
        case .aspectRatio: return "Aspect Ratio"
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
        case .dither: return "circle.dotted"
        case .aspectRatio: return "crop"
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
        case "dither":
            self = .dither(try container.decode(DitherLayerParams.self, forKey: .params))
        case "aspectRatio":
            self = .aspectRatio(try container.decode(AspectRatioLayerParams.self, forKey: .params))
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
        case .dither(let p):
            try container.encode("dither", forKey: .type)
            try container.encode(p, forKey: .params)
        case .aspectRatio(let p):
            try container.encode("aspectRatio", forKey: .type)
            try container.encode(p, forKey: .params)
        }
    }

    public static func defaultLayers() -> [CompositionLayer] {
        [
            .border(BorderLayerParams(thickness: .pixels(20), color: .white)),
            .padding(PaddingLayerParams(thickness: 150, fill: .color(.white))),
            .caption(CaptionLayerParams())
        ]
    }

}
