import Foundation

public struct ExifData: Sendable {
    public var dateTime: Date?
    public var camera: String?
    public var lens: String?
    public var iso: String?
    public var aperture: String?
    public var shutterSpeed: String?
    public var focalLength: String?

    public init(
        dateTime: Date? = nil,
        camera: String? = nil,
        lens: String? = nil,
        iso: String? = nil,
        aperture: String? = nil,
        shutterSpeed: String? = nil,
        focalLength: String? = nil
    ) {
        self.dateTime = dateTime
        self.camera = camera
        self.lens = lens
        self.iso = iso
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.focalLength = focalLength
    }

    /// Resolves a caption template, replacing {{field}} placeholders with EXIF values.
    public func resolve(template: String) -> String {
        var result = template
        let cal = Calendar.current
        let date = dateTime ?? Date()
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN",
                          "JUL","AUG","SEP","OCT","NOV","DEC"]
        let fullMonthNames = ["January","February","March","April","May","June",
                              "July","August","September","October","November","December"]
        let mon = month >= 1 && month <= 12 ? monthNames[month-1] : "???"
        let fullMonth = month >= 1 && month <= 12 ? fullMonthNames[month-1] : "???"

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        let isoDate = isoFormatter.string(from: date)

        result = result.replacingOccurrences(of: "{{year}}", with: String(year))
        result = result.replacingOccurrences(of: "{{year2}}", with: String(format: "%02d", year % 100))
        result = result.replacingOccurrences(of: "{{month}}", with: fullMonth)
        result = result.replacingOccurrences(of: "{{mon}}", with: mon)
        result = result.replacingOccurrences(of: "{{day}}", with: String(format: "%02d", day))
        result = result.replacingOccurrences(of: "{{date}}", with: isoDate)
        result = result.replacingOccurrences(of: "{{camera}}", with: camera ?? "")
        result = result.replacingOccurrences(of: "{{lens}}", with: lens ?? "")
        result = result.replacingOccurrences(of: "{{iso}}", with: iso.map { "ISO \($0)" } ?? "")
        result = result.replacingOccurrences(of: "{{aperture}}", with: aperture.map { "f/\($0)" } ?? "")
        result = result.replacingOccurrences(of: "{{shutter}}", with: shutterSpeed ?? "")
        result = result.replacingOccurrences(of: "{{focal}}", with: focalLength.map { "\($0)mm" } ?? "")
        return result
    }
}
