// Sources/FramerCore/Processing/CaptionRenderer.swift
import Foundation
import CoreGraphics
import CoreText
import AppKit

public enum CaptionRenderer {
    public static func renderCaption(
        on image: CGImage,
        params: CaptionLayerParams,
        exif: ExifData
    ) throws -> CGImage {
        // Resolve caption text
        let text: String
        switch params.mode {
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
        let fontSize: CGFloat
        switch params.fontSize {
        case .fixed(let pts):
            fontSize = CGFloat(pts)
        case .auto:
            fontSize = max(CGFloat(min(image.width, image.height)) * 0.02, 10)
        }

        // Build attributed string
        var font = NSFont(name: params.fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Apply bold/italic traits via NSFontManager
        if params.fontStyle.contains(.bold) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if params.fontStyle.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: params.fontColor.cgColor) ?? .black,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        // Measure text
        let line = CTLineCreateWithAttributedString(attrStr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // Position caption using CTLineGetPenOffsetForFlush for correct alignment
        let x: CGFloat
        let y: CGFloat
        let imageW = CGFloat(image.width)
        let imageH = CGFloat(image.height)
        // Small margin for left/right alignment (proportional to font size)
        let textMargin: CGFloat = fontSize * 0.4

        switch params.alignment {
        case .left:
            x = textMargin
        case .center:
            x = CTLineGetPenOffsetForFlush(line, 0.5, Double(imageW))
        case .right:
            x = CTLineGetPenOffsetForFlush(line, 1.0, Double(imageW)) - textMargin
        }

        switch params.position {
        case .bottom:
            y = fontSize * 1.5 + descent
        case .top:
            y = imageH - fontSize * 1.5
        }

        // Apply user offsets
        let finalX = x + CGFloat(params.offsetX)
        let finalY = y + CGFloat(params.offsetY)

        ctx.textPosition = CGPoint(x: finalX, y: finalY)
        CTLineDraw(line, ctx)

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }
}
