// Sources/FramerCore/EXIF/MetadataWriter.swift
import Foundation
import CoreGraphics
import ImageIO

public enum MetadataWriter {
    /// Encodes image to URL, preserving metadata from source and adding IPTC keywords.
    public static func encode(
        _ image: CGImage,
        to url: URL,
        format: OutputFormat,
        sourceURL: URL,
        borderStyle: BorderStyle,
        preserveMetadata: Bool
    ) throws {
        let utType: CFString

        // Start with compression options
        var properties: [String: Any] = [:]

        switch format {
        case .jpeg(let quality):
            utType = "public.jpeg" as CFString
            properties[kCGImageDestinationLossyCompressionQuality as String] = Double(quality) / 100.0
        case .png:
            utType = "public.png" as CFString
        case .mp4:
            // Video metadata is handled separately by VideoProcessor
            return
        }

        if preserveMetadata {
            // Read metadata from source image
            if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
               let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                // Merge source metadata into properties (source metadata first, then compression opts override)
                let compressionOpts = properties
                properties = sourceProps
                for (key, value) in compressionOpts {
                    properties[key] = value
                }
            }

            // Reset orientation to normal since we apply rotation manually
            properties[kCGImagePropertyOrientation as String] = 1
            if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                properties[kCGImagePropertyTIFFDictionary as String] = tiff
            }

            // Add IPTC keywords
            let style = styleName(borderStyle)
            let keywords: [String] = ["framer", "framer - \(style)"]

            let iptcKey = kCGImagePropertyIPTCDictionary as String
            let keywordsKey = kCGImagePropertyIPTCKeywords as String

            var iptc = (properties[iptcKey] as? [String: Any]) ?? [:]
            iptc[keywordsKey] = keywords
            properties[iptcKey] = iptc
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw FramerError.encodingFailed(url)
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FramerError.encodingFailed(url)
        }
    }

    private static func styleName(_ style: BorderStyle) -> String {
        switch style {
        case .solid: return "solid"
        case .instagram: return "instagram"
        case .print: return "print"
        }
    }
}
