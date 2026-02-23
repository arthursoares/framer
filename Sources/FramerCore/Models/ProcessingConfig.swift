import Foundation
import CoreGraphics

public enum BorderStyle: String, Codable, Equatable, Sendable {
    case solid
    case instagram
}

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

public enum CaptionMode: Codable, Equatable, Sendable {
    case template(String)
    case custom(String)
    case none
}

public enum FontSize: Codable, Equatable, Sendable {
    case auto
    case fixed(Int)
}

public enum OutputFormat: Codable, Equatable, Sendable {
    case jpeg(quality: Int)
    case png
}

public struct ProcessingConfig: Codable, Equatable, Sendable {
    public var borderStyle: BorderStyle
    public var borderThickness: BorderSize
    public var borderColor: CodableColor
    public var padding: Int
    public var captionMode: CaptionMode
    public var fontName: String
    public var fontSize: FontSize
    public var fontColor: CodableColor
    public var outputFormat: OutputFormat
    public var instagramMaxSize: Int
    public var postProcess: String?

    public init(
        borderStyle: BorderStyle = .solid,
        borderThickness: BorderSize = .pixels(20),
        borderColor: CodableColor = try! CodableColor(hex: "#FFFFFF"),
        padding: Int = 150,
        captionMode: CaptionMode = .template(" - {{mon}} '{{year2}} -"),
        fontName: String = "Courier New Bold",
        fontSize: FontSize = .auto,
        fontColor: CodableColor = try! CodableColor(hex: "#000000"),
        outputFormat: OutputFormat = .jpeg(quality: 100),
        instagramMaxSize: Int = 1000,
        postProcess: String? = nil
    ) {
        self.borderStyle = borderStyle
        self.borderThickness = borderThickness
        self.borderColor = borderColor
        self.padding = padding
        self.captionMode = captionMode
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.outputFormat = outputFormat
        self.instagramMaxSize = instagramMaxSize
        self.postProcess = postProcess
    }

    public static let `default` = ProcessingConfig()
}

public enum FramerError: LocalizedError {
    case invalidColor(String)
    case invalidImage(URL)
    case exifReadFailed(URL)
    case unsupportedFormat(String)
    case encodingFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidColor(let s): return "Invalid color: \(s)"
        case .invalidImage(let u): return "Cannot load image: \(u.path)"
        case .exifReadFailed(let u): return "Cannot read EXIF: \(u.path)"
        case .unsupportedFormat(let s): return "Unsupported format: \(s)"
        case .encodingFailed(let u): return "Failed to encode image: \(u.path)"
        }
    }
}
