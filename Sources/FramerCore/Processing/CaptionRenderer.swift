// Sources/FramerCore/Processing/CaptionRenderer.swift
import Foundation
import CoreGraphics
import CoreText
import AppKit

public enum CaptionRenderer {
    public static func renderCaption(
        on image: CGImage,
        config: ProcessingConfig,
        exif: ExifData
    ) throws -> CGImage {
        // Resolve caption text
        let text: String
        switch config.captionMode {
        case .none:
            return image
        case .custom(let s):
            text = s
        case .template(let t):
            text = exif.resolve(template: t)
        }

        guard let ctx = CGContext(data: nil,
                                  width: image.width,
                                  height: image.height,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Draw base image
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // Resolve font size
        let borderPx = config.borderThickness.resolved(relativeTo: min(image.width, image.height))
        let fontSize: CGFloat
        switch config.fontSize {
        case .fixed(let pts):
            fontSize = CGFloat(pts)
        case .auto:
            fontSize = autoFontSize(borderPx: borderPx)
        }

        // Build attributed string
        let font = NSFont(name: config.fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: config.fontColor.cgColor) ?? .black,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        // Measure text
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        // Position: centered horizontally, in bottom border area
        let x = (CGFloat(image.width) - bounds.width) / 2
        let y = (CGFloat(borderPx) - bounds.height) / 2

        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    private static func autoFontSize(borderPx: Int) -> CGFloat {
        switch borderPx {
        case ..<40: return CGFloat(borderPx) * 0.5
        case 40..<80: return CGFloat(borderPx) * 0.7
        default: return CGFloat(borderPx) * 0.9
        }
    }
}
