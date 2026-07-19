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
    // Added in the dither-extensions pass — see grainrad/notes/dithering.md.
    // All Codable raw values match the `case` name so old YAML keeps loading
    // and new YAML can opt in without a migration.
    case sierra
    case sierraTwoRow
    case sierraLite
    case jarvisJudiceNinke
    case burkes
    case interleavedGradientNoise
    case cmykHalftone

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
        case .sierra: return "Sierra"
        case .sierraTwoRow: return "Sierra Two-Row"
        case .sierraLite: return "Sierra Lite"
        case .jarvisJudiceNinke: return "Jarvis-Judice-Ninke"
        case .burkes: return "Burkes"
        case .interleavedGradientNoise: return "Interleaved Gradient Noise"
        case .cmykHalftone: return "CMYK Halftone"
        }
    }

    /// Whether this algorithm uses error diffusion (benefits from serpentine scanning).
    public var isErrorDiffusion: Bool {
        switch self {
        case .floydSteinberg, .atkinson, .artisticDrip, .stucki, .riemersma,
             .sierra, .sierraTwoRow, .sierraLite, .jarvisJudiceNinke, .burkes:
            return true
        default:
            return false
        }
    }
}

public enum DitherColorMode: Codable, Equatable, Sendable {
    case bw
    case twoTone(foreground: CodableColor, background: CodableColor)
    /// Two-tone using the two most dominant high-contrast colors from the image.
    case dominantTwoTone(flipped: Bool, saturationShift: Double = 0, lightnessShift: Double = 0)
    case color(levels: Int)
    /// Quantize against an arbitrary palette (e.g. GameBoy / NES / C64 looks).
    /// Capped at MAX_PALETTE_COLORS to fit in a single uniform upload.
    case palette([CodableColor])

    public static let MAX_PALETTE_COLORS = 16

    private enum CodingKeys: String, CodingKey {
        case type, foreground, background, levels, flipped, saturationShift, lightnessShift
        case palette
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
        case "palette":
            let raw = try container.decodeIfPresent([CodableColor].self, forKey: .palette) ?? []
            // Drop empty palettes silently (back to bw) so a malformed YAML
            // doesn't bring down the renderer; truncate too-long palettes to
            // the uniform's hard cap.
            if raw.isEmpty {
                self = .bw
            } else {
                let capped = raw.prefix(DitherColorMode.MAX_PALETTE_COLORS).map { $0 }
                self = .palette(capped)
            }
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
        case .palette(let colors):
            try container.encode("palette", forKey: .type)
            try container.encode(colors, forKey: .palette)
        }
    }
}

/// Canonical retro / vintage palettes for `DitherColorMode.palette`. UI can
/// surface these as named presets so users don't have to enter colours by hand.
/// Sources cited inline.
public enum VintagePalette {
    /// Original Game Boy DMG-01 LCD greens, as documented in the Pan Docs.
    /// Source: <https://gbdev.io/pandocs/Color.html>.
    public static let gameBoy: [CodableColor] = [
        CodableColor(unchecked: "#0F380F"),
        CodableColor(unchecked: "#306230"),
        CodableColor(unchecked: "#8BAC0F"),
        CodableColor(unchecked: "#9BBC0F"),
    ]

    /// NES system palette — the 4 most-used colours from the standard NTSC
    /// palette. Source: <https://www.nesdev.org/wiki/PPU_palettes>.
    public static let nes: [CodableColor] = [
        CodableColor(unchecked: "#000000"),
        CodableColor(unchecked: "#7C7C7C"),
        CodableColor(unchecked: "#FCFCFC"),
        CodableColor(unchecked: "#A4E4FC"),
    ]

    /// Commodore 64 16-colour palette (Pepto's calibration).
    /// Source: <https://www.pepto.de/projects/colorvic/>.
    public static let c64: [CodableColor] = [
        CodableColor(unchecked: "#000000"), CodableColor(unchecked: "#FFFFFF"),
        CodableColor(unchecked: "#883932"), CodableColor(unchecked: "#67B6BD"),
        CodableColor(unchecked: "#8B3F96"), CodableColor(unchecked: "#55A049"),
        CodableColor(unchecked: "#40318D"), CodableColor(unchecked: "#BFCE72"),
        CodableColor(unchecked: "#8B5429"), CodableColor(unchecked: "#574200"),
        CodableColor(unchecked: "#B86962"), CodableColor(unchecked: "#505050"),
        CodableColor(unchecked: "#787878"), CodableColor(unchecked: "#94E089"),
        CodableColor(unchecked: "#7869C4"), CodableColor(unchecked: "#9F9F9F"),
    ]

    /// IBM CGA palette 1 high-intensity (the cyan/magenta/white colour set
    /// every 1980s game seemed to use). Source: IBM 6322508 Color Graphics
    /// Adapter manual.
    public static let cga: [CodableColor] = [
        CodableColor(unchecked: "#000000"),
        CodableColor(unchecked: "#55FFFF"),
        CodableColor(unchecked: "#FF55FF"),
        CodableColor(unchecked: "#FFFFFF"),
    ]

    /// PICO-8 fantasy console — the full fixed 16-colour palette.
    /// Source: <https://pico-8.fandom.com/wiki/Palette>.
    public static let pico8: [CodableColor] = [
        CodableColor(unchecked: "#000000"), CodableColor(unchecked: "#1D2B53"),
        CodableColor(unchecked: "#7E2553"), CodableColor(unchecked: "#008751"),
        CodableColor(unchecked: "#AB5236"), CodableColor(unchecked: "#5F574F"),
        CodableColor(unchecked: "#C2C3C7"), CodableColor(unchecked: "#FFF1E8"),
        CodableColor(unchecked: "#FF004D"), CodableColor(unchecked: "#FFA300"),
        CodableColor(unchecked: "#FFEC27"), CodableColor(unchecked: "#00E436"),
        CodableColor(unchecked: "#29ADFF"), CodableColor(unchecked: "#83769C"),
        CodableColor(unchecked: "#FF77A8"), CodableColor(unchecked: "#FFCCAA"),
    ]

    /// ZX Spectrum — 8 basic colours at normal (0xD7) and bright (0xFF)
    /// levels; black has no bright variant, so 15 unique entries.
    /// Source: <https://en.wikipedia.org/wiki/ZX_Spectrum_graphic_modes>.
    public static let zxSpectrum: [CodableColor] = [
        CodableColor(unchecked: "#000000"),
        CodableColor(unchecked: "#0000D7"), CodableColor(unchecked: "#D70000"),
        CodableColor(unchecked: "#D700D7"), CodableColor(unchecked: "#00D700"),
        CodableColor(unchecked: "#00D7D7"), CodableColor(unchecked: "#D7D700"),
        CodableColor(unchecked: "#D7D7D7"),
        CodableColor(unchecked: "#0000FF"), CodableColor(unchecked: "#FF0000"),
        CodableColor(unchecked: "#FF00FF"), CodableColor(unchecked: "#00FF00"),
        CodableColor(unchecked: "#00FFFF"), CodableColor(unchecked: "#FFFF00"),
        CodableColor(unchecked: "#FFFFFF"),
    ]

    /// IBM EGA — the canonical 16-colour default palette (6-bit RGB,
    /// 0x55/0xAA component levels). Source: IBM Enhanced Graphics Adapter
    /// manual.
    public static let ega: [CodableColor] = [
        CodableColor(unchecked: "#000000"), CodableColor(unchecked: "#0000AA"),
        CodableColor(unchecked: "#00AA00"), CodableColor(unchecked: "#00AAAA"),
        CodableColor(unchecked: "#AA0000"), CodableColor(unchecked: "#AA00AA"),
        CodableColor(unchecked: "#AA5500"), CodableColor(unchecked: "#AAAAAA"),
        CodableColor(unchecked: "#555555"), CodableColor(unchecked: "#5555FF"),
        CodableColor(unchecked: "#55FF55"), CodableColor(unchecked: "#55FFFF"),
        CodableColor(unchecked: "#FF5555"), CodableColor(unchecked: "#FF55FF"),
        CodableColor(unchecked: "#FFFF55"), CodableColor(unchecked: "#FFFFFF"),
    ]

    /// Original Macintosh 1-bit black & white.
    public static let mac1Bit: [CodableColor] = [
        CodableColor(unchecked: "#000000"),
        CodableColor(unchecked: "#FFFFFF"),
    ]

    /// UI-facing preset selector. Not persisted directly — the UI translates
    /// presets to / from `DitherColorMode.palette([CodableColor])` by
    /// comparing colour arrays: if the stored palette matches one of the
    /// presets exactly, the picker selects that preset; otherwise it falls
    /// back to `.custom` and lets the user edit individual swatches.
    public enum Preset: String, CaseIterable, Hashable, Sendable {
        case gameBoy    = "Game Boy"
        case nes        = "NES"
        case c64        = "C64"
        case cga        = "CGA"
        case pico8      = "PICO-8"
        case zxSpectrum = "ZX Spectrum"
        case ega        = "EGA"
        case mac1Bit    = "Mac 1-bit"
        case custom     = "Custom"

        /// Concrete palette for the preset. `.custom` returns an empty list
        /// — callers preserve the user's current colours when switching TO
        /// custom rather than overwriting them.
        public var colors: [CodableColor] {
            switch self {
            case .gameBoy:    return VintagePalette.gameBoy
            case .nes:        return VintagePalette.nes
            case .c64:        return VintagePalette.c64
            case .cga:        return VintagePalette.cga
            case .pico8:      return VintagePalette.pico8
            case .zxSpectrum: return VintagePalette.zxSpectrum
            case .ega:        return VintagePalette.ega
            case .mac1Bit:    return VintagePalette.mac1Bit
            case .custom:     return []
            }
        }

        /// Identify which preset (if any) a stored palette matches. Used to
        /// drive the UI picker so loading a preset round-trips cleanly. Any
        /// user edit that diverges from all presets flips the picker to
        /// `.custom` automatically.
        public static func matching(_ palette: [CodableColor]) -> Preset {
            for preset in Preset.allCases where preset != .custom {
                if preset.colors == palette { return preset }
            }
            return .custom
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
    /// Layer-stack opacity for the final compose. 0 = no layer contribution,
    /// 1 = fully applied. Consumed by `LayerCompositor.compose`. Defaults
    /// to 1 so existing presets without this field behave identically.
    public var opacity: Double
    /// Blend mode used by `LayerCompositor.compose` when layering the
    /// dithered output onto the current pipeline buffer. `.normal`
    /// preserves the pre-blend-modes behaviour.
    public var blendMode: LayerBlendMode

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        algorithm: DitherAlgorithm = .atkinson,
        colorMode: DitherColorMode = .bw,
        bayerLevel: Int = 2,
        pixelScale: Int = 1,
        threshold: Double = 0.5,
        sharpen: Double = 0,
        contrast: Double = 0,
        opacity: Double = 1.0,
        blendMode: LayerBlendMode = .normal
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
        self.opacity = max(0, min(1, opacity))
        self.blendMode = blendMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, algorithm, colorMode, bayerLevel, pixelScale, threshold, sharpen, contrast
        case opacity, blendMode
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
            contrast: try container.decode(Double.self, forKey: .contrast),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0,
            blendMode: try container.decodeIfPresent(LayerBlendMode.self, forKey: .blendMode) ?? .normal
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(algorithm, forKey: .algorithm)
        try c.encode(colorMode, forKey: .colorMode)
        try c.encode(bayerLevel, forKey: .bayerLevel)
        try c.encode(pixelScale, forKey: .pixelScale)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(sharpen, forKey: .sharpen)
        try c.encode(contrast, forKey: .contrast)
        // Skip defaults so existing-style YAML stays clean.
        if opacity != 1.0 { try c.encode(opacity, forKey: .opacity) }
        if blendMode != .normal { try c.encode(blendMode, forKey: .blendMode) }
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
    /// Per-effect "fill": how much of the LUT-transformed colour to keep
    /// vs. the straight source. `LUTRenderer.apply` consumes this as a
    /// lerp factor before the layer-level compose step.
    public var intensity: Double
    /// Layer-stack opacity consumed by `LayerCompositor.compose` when
    /// laying the LUT-applied image over the current pipeline buffer.
    /// Orthogonal to `intensity` (which controls internal mix). Default
    /// 1.0 preserves pre-blend-modes behaviour.
    public var opacity: Double
    /// Blend mode used by the final compose. `.normal` at opacity 1.0
    /// matches the pre-blend-modes pipeline exactly.
    public var blendMode: LayerBlendMode

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        lutName: String = "",
        lutFileName: String = "",
        intensity: Double = 1.0,
        opacity: Double = 1.0,
        blendMode: LayerBlendMode = .normal
    ) {
        self.id = id
        self.enabled = enabled
        self.lutName = lutName
        self.lutFileName = lutFileName
        self.intensity = max(0, min(1, intensity))
        self.opacity = max(0, min(1, opacity))
        self.blendMode = blendMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, lutName, lutFileName, intensity, opacity, blendMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            lutName: try container.decodeIfPresent(String.self, forKey: .lutName) ?? "",
            lutFileName: try container.decodeIfPresent(String.self, forKey: .lutFileName) ?? "",
            intensity: try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0,
            blendMode: try container.decodeIfPresent(LayerBlendMode.self, forKey: .blendMode) ?? .normal
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(lutName, forKey: .lutName)
        try c.encode(lutFileName, forKey: .lutFileName)
        try c.encode(intensity, forKey: .intensity)
        if opacity != 1.0 { try c.encode(opacity, forKey: .opacity) }
        if blendMode != .normal { try c.encode(blendMode, forKey: .blendMode) }
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
    case crt
    case halftone
    case kuwahara
    case roughBorder

    public var label: String {
        switch self {
        case .ascii: return "ASCII"
        case .crimewave: return "Crimewave"
        case .narc: return "Narc"
        case .shiba: return "Shiba"
        case .pixelSort: return "Pixel Sort"
        case .distantPast: return "Distant Past"
        case .crt: return "CRT"
        case .halftone: return "Halftone"
        case .kuwahara: return "Kuwahara"
        case .roughBorder: return "Rough Border"
        }
    }

    /// SF Symbol name for the "+ Add Layer" menu entry. Mirrors the per-
    /// variant `GPUEffectKind.menuIcon` pattern so each shader surfaces as
    /// its own first-class filter in the add-layer picker rather than being
    /// hidden under an umbrella "+ Shader" button.
    public var menuIcon: String {
        switch self {
        case .ascii:       return "textformat"
        case .crimewave:   return "flame"
        case .narc:        return "moon.stars"
        case .shiba:       return "pawprint"
        case .pixelSort:   return "rectangle.split.3x1"
        case .distantPast: return "hourglass"
        case .crt:         return "tv"
        case .halftone:    return "circle.dotted"
        case .kuwahara:    return "paintbrush.pointed"
        case .roughBorder: return "square.dashed"
        }
    }

    /// Constructs a `.shader` CompositionLayer pre-scoped to this style
    /// with default parameters. Used by the add-layer menu so clicking
    /// "+ ASCII" lands the user on a ready-to-tune ASCII layer.
    public func makeDefaultLayer() -> CompositionLayer {
        .shader(ShaderLayerParams(style: self))
    }
}

public enum ASCIIColorMode: Codable, Equatable, Sendable {
    case manual(foreground: CodableColor, background: CodableColor)
    case dominantTwoTone(flipped: Bool = false, saturationShift: Double = 0, lightnessShift: Double = 0)
    case source(background: CodableColor = .black)
    case gradient(color1: CodableColor, color2: CodableColor, background: CodableColor = .black)

    private enum CodingKeys: String, CodingKey {
        case type, foreground, background, flipped, saturationShift, lightnessShift
        case color1, color2
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "manual"
        switch type {
        case "manual":
            self = .manual(
                foreground: try container.decodeIfPresent(CodableColor.self, forKey: .foreground) ?? .white,
                background: try container.decodeIfPresent(CodableColor.self, forKey: .background) ?? .black
            )
        case "dominantTwoTone":
            self = .dominantTwoTone(
                flipped: try container.decodeIfPresent(Bool.self, forKey: .flipped) ?? false,
                saturationShift: try container.decodeIfPresent(Double.self, forKey: .saturationShift) ?? 0,
                lightnessShift: try container.decodeIfPresent(Double.self, forKey: .lightnessShift) ?? 0
            )
        case "source":
            self = .source(
                background: try container.decodeIfPresent(CodableColor.self, forKey: .background) ?? .black
            )
        case "gradient":
            self = .gradient(
                color1: try container.decodeIfPresent(CodableColor.self, forKey: .color1) ?? .black,
                color2: try container.decodeIfPresent(CodableColor.self, forKey: .color2) ?? .white,
                background: try container.decodeIfPresent(CodableColor.self, forKey: .background) ?? .black
            )
        default:
            self = .manual(foreground: .white, background: .black)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual(let foreground, let background):
            try container.encode("manual", forKey: .type)
            try container.encode(foreground, forKey: .foreground)
            try container.encode(background, forKey: .background)
        case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift):
            try container.encode("dominantTwoTone", forKey: .type)
            if flipped { try container.encode(true, forKey: .flipped) }
            if saturationShift != 0 { try container.encode(saturationShift, forKey: .saturationShift) }
            if lightnessShift != 0 { try container.encode(lightnessShift, forKey: .lightnessShift) }
        case .source(let background):
            try container.encode("source", forKey: .type)
            try container.encode(background, forKey: .background)
        case .gradient(let color1, let color2, let background):
            try container.encode("gradient", forKey: .type)
            try container.encode(color1, forKey: .color1)
            try container.encode(color2, forKey: .color2)
            try container.encode(background, forKey: .background)
        }
    }
}

public struct ASCIIShaderParams: Codable, Equatable, Sendable {
    public var cellSize: Int
    public var edgeBias: Double
    public var colorMode: ASCIIColorMode
    public var invert: Bool
    public var exposure: Double
    public var attenuation: Double
    public var blackLevel: Double
    /// Custom character palette, ordered dim → bright. `nil` uses the baked
    /// `fillASCII.png` / `edgesASCII.png` atlases. Non-nil triggers runtime
    /// atlas generation via `ASCIIAtlasGenerator`.
    public var characters: String?
    /// PostScript font name for runtime glyph rasterisation. `nil` picks
    /// Menlo. Any installed system font name is accepted.
    public var fontName: String?
    /// Orthogonal to `characters` / `fontName`. Controls the atlas cell
    /// size independently:
    ///   - false (default): 8×8 atlas. Pure-default case (no chars, no
    ///     font, no hi-res) reads the baked `fillASCII.png` pixel-art PNG;
    ///     anything customised rasterises through Core Text at 8×8.
    ///   - true: 16×16 atlas, always Core Text. Sharper serif / antialias
    ///     edge at 4× the atlas bytes.
    ///
    /// The toggle was previously coupled to "whether we rasterise at all",
    /// which made flipping it also swap the glyph *source* (baked PNG →
    /// Core Text). That was the UX trap the user flagged. Now the toggle
    /// only controls resolution; glyph source changes only with
    /// characters/font edits.
    public var highDetail: Bool

    public init(
        cellSize: Int = 10,
        edgeBias: Double = 0.5,
        colorMode: ASCIIColorMode? = nil,
        foreground: CodableColor = .white,
        background: CodableColor = .black,
        invert: Bool = false,
        exposure: Double = 1.0,
        attenuation: Double = 1.0,
        blackLevel: Double = 0.0,
        characters: String? = nil,
        fontName: String? = nil,
        highDetail: Bool = false
    ) {
        self.cellSize = cellSize
        self.edgeBias = edgeBias
        self.colorMode = colorMode ?? .manual(foreground: foreground, background: background)
        self.invert = invert
        self.exposure = exposure
        self.attenuation = attenuation
        self.blackLevel = blackLevel
        self.characters = characters
        self.fontName = fontName
        self.highDetail = highDetail
    }

    private enum CodingKeys: String, CodingKey {
        case cellSize, edgeBias, colorMode, foreground, background, invert
        case exposure, attenuation, blackLevel, characters, fontName, highDetail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedColorMode: ASCIIColorMode
        if let explicitMode = try container.decodeIfPresent(ASCIIColorMode.self, forKey: .colorMode) {
            decodedColorMode = explicitMode
        } else {
            decodedColorMode = .manual(
                foreground: try container.decodeIfPresent(CodableColor.self, forKey: .foreground) ?? .white,
                background: try container.decodeIfPresent(CodableColor.self, forKey: .background) ?? .black
            )
        }

        self.init(
            cellSize: try container.decodeIfPresent(Int.self, forKey: .cellSize) ?? 10,
            edgeBias: try container.decodeIfPresent(Double.self, forKey: .edgeBias) ?? 0.5,
            colorMode: decodedColorMode,
            invert: try container.decodeIfPresent(Bool.self, forKey: .invert) ?? false,
            exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 1.0,
            attenuation: try container.decodeIfPresent(Double.self, forKey: .attenuation) ?? 1.0,
            blackLevel: try container.decodeIfPresent(Double.self, forKey: .blackLevel) ?? 0.0,
            characters: try container.decodeIfPresent(String.self, forKey: .characters),
            fontName: try container.decodeIfPresent(String.self, forKey: .fontName),
            highDetail: try container.decodeIfPresent(Bool.self, forKey: .highDetail) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cellSize, forKey: .cellSize)
        try container.encode(edgeBias, forKey: .edgeBias)
        try container.encode(colorMode, forKey: .colorMode)
        try container.encode(invert, forKey: .invert)
        if exposure != 1.0 { try container.encode(exposure, forKey: .exposure) }
        if attenuation != 1.0 { try container.encode(attenuation, forKey: .attenuation) }
        if blackLevel != 0.0 { try container.encode(blackLevel, forKey: .blackLevel) }
        if let characters, !characters.isEmpty {
            try container.encode(characters, forKey: .characters)
        }
        if let fontName, !fontName.isEmpty {
            try container.encode(fontName, forKey: .fontName)
        }
        if highDetail { try container.encode(highDetail, forKey: .highDetail) }
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
    /// Anti-diagonal sweep — `dir = normalize(1, 1)` along lines of constant
    /// `floor(pixel.x - pixel.y)`. Lifted directly from Kim Asendorf's
    /// original 2010 Processing sketch.
    case diagonal
}

/// Span-detection criterion. Determines which pixels belong to a single
/// sort-able run. The classic Framer behaviour is `.luminance`, retained as
/// the default. The other four options are Kim Asendorf's original modes
/// (Black / White / Bright / Dark) — see grainrad/notes/pixel-sort.md.
public enum PixelSortSpanMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Default Framer behaviour: span continues while `luminance >= threshold`.
    /// Existing presets that don't carry a `spanMode` field decode to this
    /// case so legacy behaviour is preserved.
    case luminance
    /// Kim Asendorf "Black": span starts when `luminance > threshold * 0.25`,
    /// ends when it drops below — sorts emerge from shadow regions.
    case kimBlack
    /// Kim Asendorf "White": span starts when `luminance < 1 - threshold * 0.25`,
    /// ends when it rises above — sorts emerge from highlights.
    case kimWhite
    /// Kim Asendorf "Bright": span uses `max(r,g,b) > threshold`. Stays in
    /// well-lit, saturated regions.
    case kimBright
    /// Kim Asendorf "Dark": span uses `max(r,g,b) < threshold`. Stays in
    /// shadow / desaturated regions.
    case kimDark
}

/// What value each pixel is ranked by when sorting inside a span. Orthogonal
/// to `PixelSortSpanMode` (which decides what counts as a span): span mode
/// picks the *region*, sort criterion picks the *ordering*. Reusing the
/// existing `PixelSortMode` enum from the `.gpuEffect.glitch.pixelSort`
/// bucket — same semantics (brightness = max(r,g,b), luminance = Rec.601,
/// hue = HSV angle), just now reachable from the `.shader.pixelSort` path
/// too.
public typealias PixelSortCriterion = PixelSortMode

public struct PixelSortShaderParams: Codable, Equatable, Sendable {
    public var threshold: Double
    public var direction: PixelSortDirection
    public var span: Int
    public var amount: Double
    /// Span detection criterion. Defaults to `.luminance` so existing presets
    /// behave identically to before this knob existed.
    public var spanMode: PixelSortSpanMode
    /// Sort criterion — what value each pixel contributes to the ordering
    /// inside a span. Orthogonal to `spanMode`. Default `.luminance` keeps
    /// the classic behaviour (sort streaks by perceived intensity).
    public var sortBy: PixelSortCriterion
    /// Per-line threshold jitter (0 = uniform, 1 = ±25% per row/column/diagonal).
    /// Each line gets a deterministic hash of its `lineCoord` modulating the
    /// effective threshold — adjacent lines get different span lengths,
    /// breaking up the mechanical look. Stable frame-to-frame for stills.
    public var randomness: Double
    /// Sort descending by the chosen criterion instead of ascending.
    public var reverse: Bool

    public init(
        threshold: Double = 0.65,
        direction: PixelSortDirection = .horizontal,
        span: Int = 24,
        amount: Double = 1.0,
        spanMode: PixelSortSpanMode = .luminance,
        sortBy: PixelSortCriterion = .luminance,
        randomness: Double = 0.0,
        reverse: Bool = false
    ) {
        self.threshold = threshold
        self.direction = direction
        self.span = span
        self.amount = amount
        self.spanMode = spanMode
        self.sortBy = sortBy
        self.randomness = randomness
        self.reverse = reverse
    }

    private enum CodingKeys: String, CodingKey {
        case threshold, direction, span, amount, spanMode, sortBy, randomness, reverse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // All new fields decode optionally with sensible defaults so old YAML
        // and presets continue to load and behave identically.
        self.init(
            threshold: try container.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.65,
            direction: try container.decodeIfPresent(PixelSortDirection.self, forKey: .direction) ?? .horizontal,
            span: try container.decodeIfPresent(Int.self, forKey: .span) ?? 24,
            amount: try container.decodeIfPresent(Double.self, forKey: .amount) ?? 1.0,
            spanMode: try container.decodeIfPresent(PixelSortSpanMode.self, forKey: .spanMode) ?? .luminance,
            sortBy: try container.decodeIfPresent(PixelSortCriterion.self, forKey: .sortBy) ?? .luminance,
            randomness: try container.decodeIfPresent(Double.self, forKey: .randomness) ?? 0.0,
            reverse: try container.decodeIfPresent(Bool.self, forKey: .reverse) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(direction, forKey: .direction)
        try container.encode(span, forKey: .span)
        try container.encode(amount, forKey: .amount)
        // Skip emitting defaults so existing-style YAML stays clean.
        if spanMode != .luminance { try container.encode(spanMode, forKey: .spanMode) }
        if sortBy != .luminance { try container.encode(sortBy, forKey: .sortBy) }
        if randomness != 0 { try container.encode(randomness, forKey: .randomness) }
        if reverse { try container.encode(reverse, forKey: .reverse) }
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

public struct CRTShaderParams: Codable, Equatable, Sendable {
    public var curvature: Double
    public var lineSize: Int
    public var lineStrength: Double
    public var brightness: Double
    public var vignette: Double

    public init(
        curvature: Double = 6.0,
        lineSize: Int = 1,
        lineStrength: Double = 1.0,
        brightness: Double = 0.0,
        vignette: Double = 30.0
    ) {
        self.curvature = curvature
        self.lineSize = lineSize
        self.lineStrength = lineStrength
        self.brightness = brightness
        self.vignette = vignette
    }
}

public struct HalftoneShaderParams: Codable, Equatable, Sendable {
    public var dotSize: Double
    public var contrast: Double
    public var monochrome: Bool

    public init(
        dotSize: Double = 1.0,
        contrast: Double = 1.0,
        monochrome: Bool = false
    ) {
        self.dotSize = dotSize
        self.contrast = contrast
        self.monochrome = monochrome
    }
}

public struct KuwaharaShaderParams: Codable, Equatable, Sendable {
    public var kernelSize: Int
    /// How much of the Kuwahara-filtered colour to keep. 1.0 = full effect
    /// (default), 0.0 = pass-through to the source. Internally the shader
    /// computes `mix(srcOrig, bestColor, softness)`.
    ///
    /// Replaces a legacy `sharpness` field that ran 0..8 with inverted
    /// semantics (`bestColor + (srcOrig - bestColor) * (sharpness / 8.0)`,
    /// where higher meant *less* effect). Decoding accepts either field —
    /// legacy `sharpness` is mapped via `softness = 1 - sharpness/8`.
    public var softness: Double

    public init(
        kernelSize: Int = 4,
        softness: Double = 1.0
    ) {
        self.kernelSize = kernelSize
        self.softness = softness
    }

    private enum CodingKeys: String, CodingKey {
        case kernelSize
        case softness
        case sharpness  // legacy — read-only
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kernelSize = try c.decodeIfPresent(Int.self, forKey: .kernelSize) ?? 4
        if let s = try c.decodeIfPresent(Double.self, forKey: .softness) {
            self.softness = s
        } else if let legacy = try c.decodeIfPresent(Double.self, forKey: .sharpness) {
            // Legacy: sharpness 0..8 (0 = full effect, 8 = pass-through).
            self.softness = max(0.0, min(1.0, 1.0 - legacy / 8.0))
        } else {
            self.softness = 1.0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kernelSize, forKey: .kernelSize)
        try c.encode(softness, forKey: .softness)
    }
}

/// Seeded procedural darkroom border (RoughBorder.metal). Behavior modeled
/// on Silver Efex Pro 3's Image Borders: thickness and noise are computed
/// in units of min(width, height), so the border stays proportional across
/// resolutions and aspect ratios, and `seed` makes each variation exactly
/// reproducible (SEP3's "Vary Border" number).
public struct RoughBorderShaderParams: Codable, Equatable, Sendable {
    /// Border thickness as a fraction of min(width, height). 0..0.25.
    public var size: Double
    /// How far the boundary wanders, as a fraction of `size`. 0..1.
    public var spread: Double
    /// Clean (long smooth undulation) .. rough (dense jagged grain). 0..1.
    public var roughness: Double
    /// Vary-border seed — same seed reproduces the identical border.
    public var seed: Int
    /// When true, each image derives its own seed from a stable hash of the
    /// source filename (combined with `seed`): every image in a batch gets a
    /// different border, but re-rendering the same image — preview, export,
    /// or a re-run — always reproduces the identical edge.
    public var varyPerImage: Bool
    public var borderColor: CodableColor

    public init(
        size: Double = 0.01,
        spread: Double = 0.5,
        roughness: Double = 0.5,
        seed: Int = 1,
        varyPerImage: Bool = false,
        borderColor: CodableColor = .black
    ) {
        self.size = max(0, min(0.25, size))
        self.spread = max(0, min(1, spread))
        self.roughness = max(0, min(1, roughness))
        self.seed = seed
        self.varyPerImage = varyPerImage
        self.borderColor = borderColor
    }

    private enum CodingKeys: String, CodingKey {
        case size, spread, roughness, seed, varyPerImage, borderColor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            size: try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.01,
            spread: try c.decodeIfPresent(Double.self, forKey: .spread) ?? 0.5,
            roughness: try c.decodeIfPresent(Double.self, forKey: .roughness) ?? 0.5,
            seed: try c.decodeIfPresent(Int.self, forKey: .seed) ?? 1,
            varyPerImage: try c.decodeIfPresent(Bool.self, forKey: .varyPerImage) ?? false,
            borderColor: try c.decodeIfPresent(CodableColor.self, forKey: .borderColor) ?? .black
        )
    }
}

public enum ShaderStyleParams: Codable, Equatable, Sendable {
    case ascii(ASCIIShaderParams)
    case crimewave(CrimewaveShaderParams)
    case narc(NarcShaderParams)
    case shiba(ShibaShaderParams)
    case pixelSort(PixelSortShaderParams)
    case distantPast(DistantPastShaderParams)
    case crt(CRTShaderParams)
    case halftone(HalftoneShaderParams)
    case kuwahara(KuwaharaShaderParams)
    case roughBorder(RoughBorderShaderParams)

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
        case .crt: return .crt
        case .halftone: return .halftone
        case .kuwahara: return .kuwahara
        case .roughBorder: return .roughBorder
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
        case .crt: return .crt(CRTShaderParams())
        case .halftone: return .halftone(HalftoneShaderParams())
        case .kuwahara: return .kuwahara(KuwaharaShaderParams())
        case .roughBorder: return .roughBorder(RoughBorderShaderParams())
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
        case "crt":
            self = .crt(try container.decode(CRTShaderParams.self, forKey: .params))
        case "halftone":
            self = .halftone(try container.decode(HalftoneShaderParams.self, forKey: .params))
        case "kuwahara":
            self = .kuwahara(try container.decode(KuwaharaShaderParams.self, forKey: .params))
        case "roughBorder":
            self = .roughBorder(try container.decode(RoughBorderShaderParams.self, forKey: .params))
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
        case .crt(let params):
            try container.encode("crt", forKey: .type)
            try container.encode(params, forKey: .params)
        case .halftone(let params):
            try container.encode("halftone", forKey: .type)
            try container.encode(params, forKey: .params)
        case .kuwahara(let params):
            try container.encode("kuwahara", forKey: .type)
            try container.encode(params, forKey: .params)
        case .roughBorder(let params):
            try container.encode("roughBorder", forKey: .type)
            try container.encode(params, forKey: .params)
        }
    }
}

public struct ShaderLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var style: ShaderStyle
    /// Per-effect "fill": how much the shader transformation bleeds through
    /// vs. the pass-through source, consumed internally by each shader
    /// (e.g. `ShaderRenderer.applyASCII` lerps with this). Orthogonal to
    /// `opacity` which controls the final compose step onto the pipeline.
    public var intensity: Double
    public var params: ShaderStyleParams
    /// Layer-stack opacity consumed by `LayerCompositor.compose` when
    /// laying the shader's rendered output onto the current pipeline
    /// buffer. Default 1.0 preserves pre-blend-modes behaviour.
    public var opacity: Double
    /// Blend mode used by the final compose. `.normal` at opacity 1.0
    /// matches the pre-blend-modes pipeline exactly.
    public var blendMode: LayerBlendMode

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        style: ShaderStyle = .ascii,
        intensity: Double = 1.0,
        params: ShaderStyleParams? = nil,
        opacity: Double = 1.0,
        blendMode: LayerBlendMode = .normal
    ) {
        self.id = id
        self.enabled = enabled
        self.style = style
        if let params {
            if params.style == style {
                self.params = params
            } else {
                assertionFailure("ShaderLayerParams params must match style")
                self.params = ShaderStyleParams.default(for: style)
            }
        } else {
            self.params = ShaderStyleParams.default(for: style)
        }
        self.intensity = max(0, min(1, intensity))
        self.opacity = max(0, min(1, opacity))
        self.blendMode = blendMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, style, intensity, params, opacity, blendMode
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
            params: decodedParams,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0,
            blendMode: try container.decodeIfPresent(LayerBlendMode.self, forKey: .blendMode) ?? .normal
        )
    }

    public func withStyle(_ style: ShaderStyle) -> ShaderLayerParams {
        ShaderLayerParams(
            id: id,
            enabled: enabled,
            style: style,
            intensity: intensity,
            params: style == self.style ? params : ShaderStyleParams.default(for: style),
            opacity: opacity,
            blendMode: blendMode
        )
    }

    public func withParams(_ params: ShaderStyleParams) -> ShaderLayerParams {
        ShaderLayerParams(
            id: id,
            enabled: enabled,
            style: params.style,
            intensity: intensity,
            params: params,
            opacity: opacity,
            blendMode: blendMode
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
    case gpuEffect(GPUEffectLayerParams)

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
        case .gpuEffect(let p): return p.id
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
        case .gpuEffect(let p): return p.kind.label
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
            case .gpuEffect(let p): return p.enabled
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
            case .gpuEffect(var p):
                p.enabled = newValue
                self = .gpuEffect(p)
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
        case .gpuEffect: return "sparkles.rectangle.stack"
        }
    }

    public var layerSummary: String {
        switch self {
        case .lut(let p): return p.lutName.isEmpty ? "None" : p.lutName
        case .shader(let p): return p.style.label
        case .gpuEffect(let p): return p.kind.label
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
        case "gpuEffect":
            self = .gpuEffect(try container.decode(GPUEffectLayerParams.self, forKey: .params))
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
        case .gpuEffect(let p):
            try container.encode("gpuEffect", forKey: .type)
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
