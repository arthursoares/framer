// Sources/FramerCore/Processing/CaptionRenderer.swift
import Foundation
import CoreGraphics
import CoreText
import AppKit

public enum CaptionRenderer {
    public static func renderCaption(
        on image: CGImage,
        config: ProcessingConfig,
        exif: ExifData,
        imageOrigin: CGPoint? = nil,
        imageSize: CGSize? = nil
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

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return image }

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
        var font = NSFont(name: config.fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Apply bold/italic traits via NSFontManager
        if config.fontStyle.contains(.bold) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if config.fontStyle.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: config.fontColor.cgColor) ?? .black,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        // Measure text
        let line = CTLineCreateWithAttributedString(attrStr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let textHeight = ascent + descent

        // Position caption using CTLineGetPenOffsetForFlush for correct alignment
        let x: CGFloat
        let y: CGFloat
        let imageW = CGFloat(image.width)
        let imageH = CGFloat(image.height)
        let captionSpacing = CGFloat(config.captionPadding)
        // Small margin for left/right alignment (proportional to font size)
        let textMargin: CGFloat = fontSize * 0.4

        if let origin = imageOrigin, let imgSize = imageSize {
            // Canvas style (print/instagram with origin): position relative to image region
            let regionStart = origin.x
            let regionWidth = Double(imgSize.width)

            switch config.captionAlignment {
            case .left:
                x = regionStart + textMargin
            case .center:
                x = regionStart + CTLineGetPenOffsetForFlush(line, 0.5, regionWidth)
            case .right:
                x = regionStart + CTLineGetPenOffsetForFlush(line, 1.0, regionWidth) - textMargin
            }

            switch config.captionPosition {
            case .bottom:
                y = origin.y - captionSpacing - fontSize
            case .top:
                y = origin.y + imgSize.height + captionSpacing
            }
        } else {
            // Solid/layer style: position in border area
            switch config.captionAlignment {
            case .left:
                x = textMargin
            case .center:
                x = CTLineGetPenOffsetForFlush(line, 0.5, Double(imageW))
            case .right:
                x = CTLineGetPenOffsetForFlush(line, 1.0, Double(imageW)) - textMargin
            }

            switch config.captionPosition {
            case .bottom:
                y = (CGFloat(borderPx) - textHeight) / 2 + descent
            case .top:
                y = imageH - CGFloat(borderPx) + (CGFloat(borderPx) - textHeight) / 2 + descent
            }
        }

        // Apply user offsets
        let finalX = x + CGFloat(config.captionOffsetX)
        let finalY = y + CGFloat(config.captionOffsetY)

        ctx.textPosition = CGPoint(x: finalX, y: finalY)
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
