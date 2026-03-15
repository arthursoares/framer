import Foundation

// MARK: - VideoCodec

/// Video codec selection for export
public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264
    case h265
}

// MARK: - TrimRange

/// Timecode-based trim range for video clips
public struct TrimRange: Codable, Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) throws {
        guard start < end else {
            throw FramerError.invalidTrimRange("Start time must be before end time")
        }
        self.start = start
        self.end = end
    }

    /// Parse from timecode string: "HH:MM:SS.mmm-HH:MM:SS.mmm"
    public init(from timecode: String) throws {
        let parts = timecode.split(separator: "-")
        guard parts.count == 2 else {
            throw FramerError.invalidTrimRange("Expected format: HH:MM:SS.mmm-HH:MM:SS.mmm")
        }
        let startTime = try Self.parseTimecode(String(parts[0]))
        let endTime = try Self.parseTimecode(String(parts[1]))
        try self.init(start: startTime, end: endTime)
    }

    private static func parseTimecode(_ tc: String) throws -> TimeInterval {
        let segments = tc.split(separator: ":")
        guard segments.count == 3 else {
            throw FramerError.invalidTrimRange("Invalid timecode: \(tc)")
        }
        guard let hours = Double(segments[0]),
              let minutes = Double(segments[1]),
              let seconds = Double(segments[2]) else {
            throw FramerError.invalidTrimRange("Non-numeric timecode: \(tc)")
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - VideoExportConfig

/// Configuration for video export including codec and optional trim range
public struct VideoExportConfig: Codable, Sendable, Equatable {
    public var codec: VideoCodec
    public var trim: TrimRange?

    public init(codec: VideoCodec = .h264, trim: TrimRange? = nil) {
        self.codec = codec
        self.trim = trim
    }
}
