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
    public var enabled: Bool
    public var thickness: BorderSize
    public var color: CodableColor

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        thickness: BorderSize = .pixels(20),
        color: CodableColor = .white
    ) {
        self.id = id
        self.enabled = enabled
        self.thickness = thickness
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, thickness, color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            thickness: try container.decode(BorderSize.self, forKey: .thickness),
            color: try container.decode(CodableColor.self, forKey: .color)
        )
    }
}

public struct PaddingLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var thickness: Int
    public var fill: LayerFill

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        thickness: Int = 150,
        fill: LayerFill = .color(.white)
    ) {
        self.id = id
        self.enabled = enabled
        self.thickness = thickness
        self.fill = fill
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, thickness, fill
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            thickness: try container.decode(Int.self, forKey: .thickness),
            fill: try container.decode(LayerFill.self, forKey: .fill)
        )
    }
}

public struct CanvasLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var width: Int
    public var height: Int
    public var fill: LayerFill

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        width: Int = 1080,
        height: Int = 1350,
        fill: LayerFill = .color(.white)
    ) {
        self.id = id
        self.enabled = enabled
        self.width = width
        self.height = height
        self.fill = fill
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, width, height, fill
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height),
            fill: try container.decode(LayerFill.self, forKey: .fill)
        )
    }
}

public struct ResizeLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var maxWidth: Int
    public var maxHeight: Int

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        maxWidth: Int = 1000,
        maxHeight: Int = 1000
    ) {
        self.id = id
        self.enabled = enabled
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, maxWidth, maxHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            maxWidth: try container.decode(Int.self, forKey: .maxWidth),
            maxHeight: try container.decode(Int.self, forKey: .maxHeight)
        )
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
    public var enabled: Bool
    public var overlayName: String
    public var kind: OverlayKind
    public var blendMode: OverlayBlendMode
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        overlayName: String = "",
        kind: OverlayKind = .frame,
        blendMode: OverlayBlendMode? = nil,
        opacity: Double = 100
    ) {
        self.id = id
        self.enabled = enabled
        self.overlayName = overlayName
        self.kind = kind
        self.blendMode = blendMode ?? OverlayBlendMode.defaultFor(kind)
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, overlayName, kind, blendMode, opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            overlayName: try container.decode(String.self, forKey: .overlayName),
            kind: try container.decode(OverlayKind.self, forKey: .kind),
            blendMode: try container.decodeIfPresent(OverlayBlendMode.self, forKey: .blendMode),
            opacity: try container.decode(Double.self, forKey: .opacity)
        )
    }
}

// MARK: - Orientation

public enum OrientationTarget: String, Codable, CaseIterable, Sendable {
    case landscape
    case portrait
}

public struct OrientationLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var target: OrientationTarget

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        target: OrientationTarget = .landscape
    ) {
        self.id = id
        self.enabled = enabled
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            target: try container.decode(OrientationTarget.self, forKey: .target)
        )
    }
}

// MARK: - Caption

public enum CaptionColorMode: Codable, Equatable, Sendable {
    case fixed(CodableColor)
    case dominant(saturationShift: Double = 0, lightnessShift: Double = 0)
    case dominantInverted(saturationShift: Double = 0, lightnessShift: Double = 0)

    private enum CodingKeys: String, CodingKey {
        case type, color, saturationShift, lightnessShift
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "fixed":
            let c = try container.decode(CodableColor.self, forKey: .color)
            self = .fixed(c)
        case "dominant":
            let sat = try container.decodeIfPresent(Double.self, forKey: .saturationShift) ?? 0
            let light = try container.decodeIfPresent(Double.self, forKey: .lightnessShift) ?? 0
            self = .dominant(saturationShift: sat, lightnessShift: light)
        case "dominantInverted":
            let sat = try container.decodeIfPresent(Double.self, forKey: .saturationShift) ?? 0
            let light = try container.decodeIfPresent(Double.self, forKey: .lightnessShift) ?? 0
            self = .dominantInverted(saturationShift: sat, lightnessShift: light)
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
        case .dominant(let sat, let light):
            try container.encode("dominant", forKey: .type)
            if sat != 0 { try container.encode(sat, forKey: .saturationShift) }
            if light != 0 { try container.encode(light, forKey: .lightnessShift) }
        case .dominantInverted(let sat, let light):
            try container.encode("dominantInverted", forKey: .type)
            if sat != 0 { try container.encode(sat, forKey: .saturationShift) }
            if light != 0 { try container.encode(light, forKey: .lightnessShift) }
        }
    }
}

public struct CaptionLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
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
        enabled: Bool = true,
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
        self.enabled = enabled
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
        case id, enabled, mode, fontName, fontSize, fontStyle, fontColor, fontColorMode
        case alignment, position, offsetX, offsetY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
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
        try container.encode(enabled, forKey: .enabled)
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
    case dominantTwoTone(flipped: Bool, saturationShift: Double = 0, lightnessShift: Double = 0)
    case color(levels: Int)

    private enum CodingKeys: String, CodingKey {
        case type, foreground, background, levels, flipped, saturationShift, lightnessShift
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
            let sat = try container.decodeIfPresent(Double.self, forKey: .saturationShift) ?? 0
            let light = try container.decodeIfPresent(Double.self, forKey: .lightnessShift) ?? 0
            self = .dominantTwoTone(flipped: flipped, saturationShift: sat, lightnessShift: light)
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
        case .dominantTwoTone(let flipped, let sat, let light):
            try container.encode("dominantTwoTone", forKey: .type)
            if flipped { try container.encode(true, forKey: .flipped) }
            if sat != 0 { try container.encode(sat, forKey: .saturationShift) }
            if light != 0 { try container.encode(light, forKey: .lightnessShift) }
        case .color(let levels):
            try container.encode("color", forKey: .type)
            try container.encode(levels, forKey: .levels)
        }
    }
}

public struct DitherLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
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
        enabled: Bool = true,
        algorithm: DitherAlgorithm = .atkinson,
        colorMode: DitherColorMode = .bw,
        bayerLevel: Int = 2,
        pixelScale: Int = 1,
        threshold: Double = 0.5,
        sharpen: Double = 0,
        contrast: Double = 0
    ) {
        self.id = id
        self.enabled = enabled
        self.algorithm = algorithm
        self.colorMode = colorMode
        self.bayerLevel = max(1, min(4, bayerLevel))
        self.pixelScale = max(1, min(8, pixelScale))
        self.threshold = max(0.1, min(0.9, threshold))
        self.sharpen = max(0, min(1, sharpen))
        self.contrast = max(0, min(1, contrast))
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, algorithm, colorMode, bayerLevel, pixelScale, threshold, sharpen, contrast
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            algorithm: try container.decode(DitherAlgorithm.self, forKey: .algorithm),
            colorMode: try container.decode(DitherColorMode.self, forKey: .colorMode),
            bayerLevel: try container.decode(Int.self, forKey: .bayerLevel),
            pixelScale: try container.decode(Int.self, forKey: .pixelScale),
            threshold: try container.decode(Double.self, forKey: .threshold),
            sharpen: try container.decode(Double.self, forKey: .sharpen),
            contrast: try container.decode(Double.self, forKey: .contrast)
        )
    }
}

// MARK: - Aspect Ratio

public struct AspectRatioLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var ratioWidth: Int
    public var ratioHeight: Int
    public var offsetX: Double  // -1.0 (left) to 1.0 (right), 0 = center
    public var offsetY: Double  // -1.0 (bottom) to 1.0 (top), 0 = center

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        ratioWidth: Int = 1,
        ratioHeight: Int = 1,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.id = id
        self.enabled = enabled
        self.ratioWidth = max(1, ratioWidth)
        self.ratioHeight = max(1, ratioHeight)
        self.offsetX = max(-1, min(1, offsetX))
        self.offsetY = max(-1, min(1, offsetY))
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, ratioWidth, ratioHeight, offsetX, offsetY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            ratioWidth: try container.decode(Int.self, forKey: .ratioWidth),
            ratioHeight: try container.decode(Int.self, forKey: .ratioHeight),
            offsetX: try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0,
            offsetY: try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        )
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

// MARK: - LUT

public struct LUTLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var lutName: String
    public var lutFileName: String
    public var intensity: Double

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        lutName: String = "",
        lutFileName: String = "",
        intensity: Double = 1.0
    ) {
        self.id = id
        self.enabled = enabled
        self.lutName = lutName
        self.lutFileName = lutFileName
        self.intensity = max(0, min(1, intensity))
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, lutName, lutFileName, intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            lutName: try container.decodeIfPresent(String.self, forKey: .lutName) ?? "",
            lutFileName: try container.decodeIfPresent(String.self, forKey: .lutFileName) ?? "",
            intensity: try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0
        )
    }
}

// MARK: - Shader

public enum ShaderStyle: String, Codable, CaseIterable, Sendable {
    case ascii
    case crimewave
    case narc
    case shiba
    case pixelSort
    case distantPast

    public var label: String {
        switch self {
        case .ascii: return "ASCII"
        case .crimewave: return "Crimewave"
        case .narc: return "Narc"
        case .shiba: return "Shiba"
        case .pixelSort: return "Pixel Sort"
        case .distantPast: return "Distant Past"
        }
    }
}

public struct ASCIIShaderParams: Codable, Equatable, Sendable {
    public var cellSize: Int
    public var edgeBias: Double
    public var foreground: CodableColor
    public var background: CodableColor
    public var invert: Bool

    public init(
        cellSize: Int = 10,
        edgeBias: Double = 0.5,
        foreground: CodableColor = .white,
        background: CodableColor = .black,
        invert: Bool = false
    ) {
        self.cellSize = cellSize
        self.edgeBias = edgeBias
        self.foreground = foreground
        self.background = background
        self.invert = invert
    }
}

public struct CrimewaveShaderParams: Codable, Equatable, Sendable {
    public var neon: Double
    public var softness: Double
    public var contrast: Double
    public var grain: Double

    public init(
        neon: Double = 0.7,
        softness: Double = 0.4,
        contrast: Double = 1.15,
        grain: Double = 0.2
    ) {
        self.neon = neon
        self.softness = softness
        self.contrast = contrast
        self.grain = grain
    }
}

public struct NarcShaderParams: Codable, Equatable, Sendable {
    public var contrast: Double
    public var crush: Double
    public var temperature: Double
    public var grain: Double

    public init(
        contrast: Double = 1.25,
        crush: Double = 0.35,
        temperature: Double = -0.1,
        grain: Double = 0.25
    ) {
        self.contrast = contrast
        self.crush = crush
        self.temperature = temperature
        self.grain = grain
    }
}

public struct ShibaShaderParams: Codable, Equatable, Sendable {
    public var warmth: Double
    public var softness: Double
    public var saturation: Double
    public var grain: Double

    public init(
        warmth: Double = 0.2,
        softness: Double = 0.3,
        saturation: Double = 0.15,
        grain: Double = 0.1
    ) {
        self.warmth = warmth
        self.softness = softness
        self.saturation = saturation
        self.grain = grain
    }
}

public enum PixelSortDirection: String, Codable, Equatable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

public struct PixelSortShaderParams: Codable, Equatable, Sendable {
    public var threshold: Double
    public var direction: PixelSortDirection
    public var span: Int
    public var amount: Double

    public init(
        threshold: Double = 0.65,
        direction: PixelSortDirection = .horizontal,
        span: Int = 24,
        amount: Double = 1.0
    ) {
        self.threshold = threshold
        self.direction = direction
        self.span = span
        self.amount = amount
    }
}

public struct DistantPastShaderParams: Codable, Equatable, Sendable {
    public var paletteDepth: Int
    public var fade: Double
    public var softness: Double
    public var grain: Double

    public init(
        paletteDepth: Int = 6,
        fade: Double = 0.3,
        softness: Double = 0.2,
        grain: Double = 0.15
    ) {
        self.paletteDepth = paletteDepth
        self.fade = fade
        self.softness = softness
        self.grain = grain
    }
}

public enum ShaderStyleParams: Codable, Equatable, Sendable {
    case ascii(ASCIIShaderParams)
    case crimewave(CrimewaveShaderParams)
    case narc(NarcShaderParams)
    case shiba(ShibaShaderParams)
    case pixelSort(PixelSortShaderParams)
    case distantPast(DistantPastShaderParams)

    private enum CodingKeys: String, CodingKey {
        case type, params
    }

    public var style: ShaderStyle {
        switch self {
        case .ascii: return .ascii
        case .crimewave: return .crimewave
        case .narc: return .narc
        case .shiba: return .shiba
        case .pixelSort: return .pixelSort
        case .distantPast: return .distantPast
        }
    }

    public static func `default`(for style: ShaderStyle) -> ShaderStyleParams {
        switch style {
        case .ascii: return .ascii(ASCIIShaderParams())
        case .crimewave: return .crimewave(CrimewaveShaderParams())
        case .narc: return .narc(NarcShaderParams())
        case .shiba: return .shiba(ShibaShaderParams())
        case .pixelSort: return .pixelSort(PixelSortShaderParams())
        case .distantPast: return .distantPast(DistantPastShaderParams())
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ascii":
            self = .ascii(try container.decode(ASCIIShaderParams.self, forKey: .params))
        case "crimewave":
            self = .crimewave(try container.decode(CrimewaveShaderParams.self, forKey: .params))
        case "narc":
            self = .narc(try container.decode(NarcShaderParams.self, forKey: .params))
        case "shiba":
            self = .shiba(try container.decode(ShibaShaderParams.self, forKey: .params))
        case "pixelSort":
            self = .pixelSort(try container.decode(PixelSortShaderParams.self, forKey: .params))
        case "distantPast":
            self = .distantPast(try container.decode(DistantPastShaderParams.self, forKey: .params))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown shader style: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ascii(let params):
            try container.encode("ascii", forKey: .type)
            try container.encode(params, forKey: .params)
        case .crimewave(let params):
            try container.encode("crimewave", forKey: .type)
            try container.encode(params, forKey: .params)
        case .narc(let params):
            try container.encode("narc", forKey: .type)
            try container.encode(params, forKey: .params)
        case .shiba(let params):
            try container.encode("shiba", forKey: .type)
            try container.encode(params, forKey: .params)
        case .pixelSort(let params):
            try container.encode("pixelSort", forKey: .type)
            try container.encode(params, forKey: .params)
        case .distantPast(let params):
            try container.encode("distantPast", forKey: .type)
            try container.encode(params, forKey: .params)
        }
    }
}

public struct ShaderLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var style: ShaderStyle
    public var intensity: Double
    public var params: ShaderStyleParams

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        style: ShaderStyle = .ascii,
        intensity: Double = 1.0,
        params: ShaderStyleParams? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.style = style
        if let params, params.style == style {
            self.params = params
        } else {
            assertionFailure("ShaderLayerParams params must match style")
            self.params = ShaderStyleParams.default(for: style)
        }
        self.intensity = max(0, min(1, intensity))
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, style, intensity, params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStyle = try container.decode(ShaderStyle.self, forKey: .style)
        let decodedParams = try container.decodeIfPresent(ShaderStyleParams.self, forKey: .params)
            ?? ShaderStyleParams.default(for: decodedStyle)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            style: decodedStyle,
            intensity: try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0,
            params: decodedParams
        )
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
    case lut(LUTLayerParams)
    case shader(ShaderLayerParams)

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
        case .lut(let p): return p.id
        case .shader(let p): return p.id
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
        case .lut: return "LUT"
        case .shader(let p): return p.style.label
        }
    }

    public var isEnabled: Bool {
        get {
            switch self {
            case .border(let p): return p.enabled
            case .padding(let p): return p.enabled
            case .canvas(let p): return p.enabled
            case .resize(let p): return p.enabled
            case .overlay(let p): return p.enabled
            case .orientation(let p): return p.enabled
            case .caption(let p): return p.enabled
            case .dither(let p): return p.enabled
            case .aspectRatio(let p): return p.enabled
            case .lut(let p): return p.enabled
            case .shader(let p): return p.enabled
            }
        }
        set {
            switch self {
            case .border(var p):
                p.enabled = newValue
                self = .border(p)
            case .padding(var p):
                p.enabled = newValue
                self = .padding(p)
            case .canvas(var p):
                p.enabled = newValue
                self = .canvas(p)
            case .resize(var p):
                p.enabled = newValue
                self = .resize(p)
            case .overlay(var p):
                p.enabled = newValue
                self = .overlay(p)
            case .orientation(var p):
                p.enabled = newValue
                self = .orientation(p)
            case .caption(var p):
                p.enabled = newValue
                self = .caption(p)
            case .dither(var p):
                p.enabled = newValue
                self = .dither(p)
            case .aspectRatio(var p):
                p.enabled = newValue
                self = .aspectRatio(p)
            case .lut(var p):
                p.enabled = newValue
                self = .lut(p)
            case .shader(var p):
                p.enabled = newValue
                self = .shader(p)
            }
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
        case .lut: return "photo.artframe"
        case .shader: return "sparkles"
        }
    }

    public var layerSummary: String {
        switch self {
        case .lut(let p): return p.lutName.isEmpty ? "None" : p.lutName
        case .shader(let p): return p.style.label
        default: return ""
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
        case "lut":
            self = .lut(try container.decode(LUTLayerParams.self, forKey: .params))
        case "shader":
            self = .shader(try container.decode(ShaderLayerParams.self, forKey: .params))
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
        case .lut(let p):
            try container.encode("lut", forKey: .type)
            try container.encode(p, forKey: .params)
        case .shader(let p):
            try container.encode("shader", forKey: .type)
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
