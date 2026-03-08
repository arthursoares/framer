// Sources/FramerCore/Processing/CaptionRenderer.swift
import Foundation
import CoreGraphics
import CoreText

public enum CaptionRenderer {
    public static func renderCaption(
        on image: CGImage,
        params: CaptionLayerParams,
        exif: ExifData,
        sourceImage: CGImage? = nil
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

        // Build attributed string using CoreText APIs (safe on background actors)
        var font: CTFont = CTFontCreateWithName(params.fontName as CFString, fontSize, nil)

        // Verify the font resolved to the requested family; fall back to system monospace if not
        let resolvedName = CTFontCopyPostScriptName(font) as String
        if resolvedName.lowercased() == "lastresort" || resolvedName.lowercased().hasPrefix(".") {
            font = CTFontCreateUIFontForLanguage(.userFixedPitch, fontSize, nil)
                ?? CTFontCreateWithName("Courier New" as CFString, fontSize, nil)
        }

        // Apply bold/italic traits — CTFontCreateCopyWithSymbolicTraits returns nil when the
        // face is not available, so fall back to the original font in that case.
        if params.fontStyle.contains(.bold) {
            font = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .boldTrait, .boldTrait) ?? font
        }
        if params.fontStyle.contains(.italic) {
            font = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .italicTrait, .italicTrait) ?? font
        }

        // NSAttributedString is toll-free bridged to CFAttributedString, making it
        // compatible with CTLineCreateWithAttributedString. NSAttributedString itself
        // is in Foundation, not AppKit — safe to use on any thread.
        // Resolve font color from mode
        let resolvedColor: CGColor
        switch params.fontColorMode {
        case .fixed(let c):
            resolvedColor = c.cgColor
        case .dominant:
            let img = sourceImage ?? image
            let dominant = ColorExtractor.extractDominantColor(from: img)
            resolvedColor = dominant.cgColor
        case .dominantInverted:
            let img = sourceImage ?? image
            let dominant = ColorExtractor.extractDominantColor(from: img)
            // Invert: shift hue 180°, invert lightness
            let inverted = HSLColor(
                h: dominant.h + 180 > 360 ? dominant.h - 180 : dominant.h + 180,
                s: dominant.s,
                l: 100 - dominant.l
            )
            resolvedColor = inverted.cgColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): resolvedColor,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)

        // Measure text
        let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
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
