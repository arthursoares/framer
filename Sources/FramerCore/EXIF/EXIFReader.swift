// Sources/FramerCore/EXIF/EXIFReader.swift
import Foundation
import ImageIO

public enum EXIFReader {
    public static func read(from url: URL) throws -> ExifData {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw FramerError.exifReadFailed(url)
        }

        var data = ExifData()
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        _ = gps // reserved for future use

        // Date
        if let dateStr = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            data.dateTime = Self.parseDate(dateStr)
        } else if let dateStr = tiff?[kCGImagePropertyTIFFDateTime as String] as? String {
            data.dateTime = Self.parseDate(dateStr)
        }

        // Camera
        data.camera = tiff?[kCGImagePropertyTIFFModel as String] as? String

        // Lens
        data.lens = exif?[kCGImagePropertyExifLensModel as String] as? String

        // ISO
        if let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
           let iso = isoArray.first {
            data.iso = String(iso)
        }

        // Aperture
        if let fn = exif?[kCGImagePropertyExifFNumber as String] as? Double {
            data.aperture = String(format: "%.1f", fn)
        }

        // Shutter speed
        if let exp = exif?[kCGImagePropertyExifExposureTime as String] as? Double {
            if exp >= 1 {
                data.shutterSpeed = "\(Int(exp))s"
            } else {
                let denom = Int(round(1.0 / exp))
                data.shutterSpeed = "1/\(denom)"
            }
        }

        // Focal length
        if let fl = exif?[kCGImagePropertyExifFocalLength as String] as? Double {
            data.focalLength = String(format: "%.0f", fl)
        }

        return data
    }

    private static func parseDate(_ string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: string)
    }
}
