import Foundation
import CoreGraphics

// MARK: - PrintFormat

public struct PrintFormat: Codable, Equatable, Sendable {
    public var widthMM: Double
    public var heightMM: Double
    public var dpi: Int

    public var widthPixels: Int {
        Int((widthMM / 25.4) * Double(dpi))
    }

    public var heightPixels: Int {
        Int((heightMM / 25.4) * Double(dpi))
    }

    public init(widthMM: Double = 148, heightMM: Double = 100, dpi: Int = 300) {
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.dpi = dpi
    }

    public static let print10x15 = PrintFormat()
}

// MARK: - BorderStyle

public enum BorderStyle: Equatable, Sendable {
    case solid
    case instagram
    case print(PrintFormat)
}

extension BorderStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, print
    }

    public init(from decoder: Decoder) throws {
        // Try decoding as a simple string first (solid, instagram, print10x15)
        if let container = try? decoder.singleValueContainer(),
           let str = try? container.decode(String.self) {
            switch str {
            case "solid": self = .solid
            case "instagram": self = .instagram
            case "print10x15", "print": self = .print(.print10x15)
            default: self = .solid
            }
            return
        }

        // Try decoding as keyed container: {"print": {...}}
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let format = try container.decodeIfPresent(PrintFormat.self, forKey: .print) {
            self = .print(format)
            return
        }

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "solid": self = .solid
        case "instagram": self = .instagram
        case "print10x15": self = .print(.print10x15)
        default: self = .solid
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .solid:
            var container = encoder.singleValueContainer()
            try container.encode("solid")
        case .instagram:
            var container = encoder.singleValueContainer()
            try container.encode("instagram")
        case .print(let format):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(format, forKey: .print)
        }
    }
}

// MARK: - BorderSize

public enum BorderSize: Codable, Equatable, Sendable {
    case pixels(Int)
    case percent(Double)

    /// Parse from YAML/CLI string: "50" → .pixels(50), "5%" → .percent(5.0)
    public init(string: String) {
        if string.hasSuffix("%"), let v = Double(string.dropLast()) {
            self = .percent(v)
        } else if let v = Int(string) {
            self = .pixels(v)
        } else {
            self = .pixels(20)
        }
    }

    public func resolved(relativeTo dimension: Int) -> Int {
        switch self {
        case .pixels(let px): return px
        case .percent(let pct): return Int(Double(dimension) * pct / 100.0)
        }
    }
}

// MARK: - CodableColor

public struct CodableColor: Codable, Equatable, Sendable {
    public let hex: String

    public init(hex: String) throws {
        let cleaned = hex.hasPrefix("#") ? hex : "#" + hex
        guard cleaned.count == 7,
              cleaned.dropFirst().allSatisfy({ $0.isHexDigit }) else {
            throw FramerError.invalidColor(hex)
        }
        self.hex = cleaned.uppercased()
    }

    public var red: Double { Double(UInt8(hex.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255 }
    public var green: Double { Double(UInt8(hex.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255 }
    public var blue: Double { Double(UInt8(hex.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255 }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

public extension CodableColor {
    /// Pre-validated color constants — no throwing needed.
    static let white = CodableColor(unchecked: "#FFFFFF")
    static let black = CodableColor(unchecked: "#000000")

    /// Internal initializer for compile-time-known hex values.
    init(unchecked hex: String) {
        self.hex = hex.hasPrefix("#") ? hex.uppercased() : "#" + hex.uppercased()
    }
}

// MARK: - Other Enums

public enum CaptionMode: Codable, Equatable, Sendable {
    case template(String)
    case custom(String)
    case none
}

public enum CaptionAlignment: String, Codable, Equatable, Sendable, CaseIterable {
    case left
    case center
    case right
}

public enum CaptionPosition: String, Codable, Equatable, Sendable, CaseIterable {
    case bottom
    case top
}

public struct FontStyle: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold   = FontStyle(rawValue: 1 << 0)
    public static let italic = FontStyle(rawValue: 1 << 1)
}

public enum FontSize: Codable, Equatable, Sendable {
    case auto
    case fixed(Int)
}

public enum OutputFormat: Codable, Equatable, Sendable {
    case jpeg(quality: Int)
    case png
    case mp4(VideoExportConfig)
}

// MARK: - BackgroundMode

public enum BackgroundMode: String, Codable, Equatable, Sendable, CaseIterable {
    case color = "color"
    case dominant = "dominant"
    case gradientLinear = "gradient_linear"
    case gradientRadial = "gradient_radial"
}

// MARK: - ProcessingConfig

public struct ProcessingConfig: Equatable, Sendable {
    public var borderStyle: BorderStyle
    public var borderThickness: BorderSize
    public var borderColor: CodableColor
    public var padding: Int
    public var outputFormat: OutputFormat
    public var instagramMaxSize: Int
    public var postProcess: String?
    public var backgroundColor: CodableColor
    public var outerPadding: Int
    public var noMetadata: Bool
    public var backgroundMode: BackgroundMode
    public var layers: [CompositionLayer]?
    public var videoExport: VideoExportConfig?

    public init(
        borderStyle: BorderStyle = .solid,
        borderThickness: BorderSize = .pixels(20),
        borderColor: CodableColor = .white,
        padding: Int = 150,
        outputFormat: OutputFormat = .jpeg(quality: 100),
        instagramMaxSize: Int = 1000,
        postProcess: String? = nil,
        backgroundColor: CodableColor = .white,
        outerPadding: Int = 0,
        noMetadata: Bool = false,
        backgroundMode: BackgroundMode = .color,
        layers: [CompositionLayer]? = nil,
        videoExport: VideoExportConfig? = nil
    ) {
        self.borderStyle = borderStyle
        self.borderThickness = borderThickness
        self.borderColor = borderColor
        self.padding = padding
        self.outputFormat = outputFormat
        self.instagramMaxSize = instagramMaxSize
        self.postProcess = postProcess
        self.backgroundColor = backgroundColor
        self.outerPadding = outerPadding
        self.noMetadata = noMetadata
        self.backgroundMode = backgroundMode
        self.layers = layers
        self.videoExport = videoExport
    }

    public static let `default` = ProcessingConfig()
}

// Manual Codable for backward compatibility with saved presets missing new fields
extension ProcessingConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case borderStyle, borderThickness, borderColor, padding
        case outputFormat, instagramMaxSize, postProcess
        case backgroundColor, outerPadding, noMetadata
        case backgroundMode, layers, videoExport
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        borderStyle = try container.decode(BorderStyle.self, forKey: .borderStyle)
        borderThickness = try container.decode(BorderSize.self, forKey: .borderThickness)
        borderColor = try container.decode(CodableColor.self, forKey: .borderColor)
        padding = try container.decode(Int.self, forKey: .padding)
        outputFormat = try container.decode(OutputFormat.self, forKey: .outputFormat)
        instagramMaxSize = try container.decode(Int.self, forKey: .instagramMaxSize)
        postProcess = try container.decodeIfPresent(String.self, forKey: .postProcess)
        // Fields with defaults for backward compat
        backgroundColor = (try? container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor)) ?? .white
        outerPadding = (try? container.decodeIfPresent(Int.self, forKey: .outerPadding)) ?? 0
        noMetadata = (try? container.decodeIfPresent(Bool.self, forKey: .noMetadata)) ?? false
        backgroundMode = (try? container.decodeIfPresent(BackgroundMode.self, forKey: .backgroundMode)) ?? .color
        layers = try? container.decodeIfPresent([CompositionLayer].self, forKey: .layers)
        videoExport = try? container.decodeIfPresent(VideoExportConfig.self, forKey: .videoExport)
    }
}

// MARK: - Errors

public enum FramerError: LocalizedError {
    case invalidColor(String)
    case invalidImage(URL)
    case exifReadFailed(URL)
    case unsupportedFormat(String)
    case encodingFailed(URL)
    case invalidTrimRange(String)

    public var errorDescription: String? {
        switch self {
        case .invalidColor(let s): return "Invalid color: \(s)"
        case .invalidImage(let u): return "Cannot load image: \(u.path)"
        case .exifReadFailed(let u): return "Cannot read EXIF: \(u.path)"
        case .unsupportedFormat(let s): return "Unsupported format: \(s)"
        case .encodingFailed(let u): return "Failed to encode image: \(u.path)"
        case .invalidTrimRange(let s): return "Invalid trim range: \(s)"
        }
    }
}
