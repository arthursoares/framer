// Sources/FramerCore/Processing/BorderRenderer.swift
import Foundation
import CoreGraphics

// MARK: - BorderResult

public struct BorderResult {
    public let image: CGImage
    /// Position where the photo was drawn on the canvas (nil for solid/instagram).
    public let imageOrigin: CGPoint?
    /// Size of the photo as drawn on the canvas (nil for solid/instagram).
    public let imageSize: CGSize?
}

public enum BorderRenderer {
    // Instagram frame constants (4:5)
    static let instagramWidth = 1080
    static let instagramHeight = 1350

    public static func applyBorder(
        to image: CGImage,
        config: ProcessingConfig,
        style: BorderStyle
    ) throws -> BorderResult {
        switch style {
        case .solid:
            let result = try applySolidBorder(to: image, config: config)
            return BorderResult(image: result, imageOrigin: nil, imageSize: nil)
        case .instagram:
            let result = try applyInstagramBorder(to: image, config: config)
            return BorderResult(image: result, imageOrigin: nil, imageSize: nil)
        case .print(let format):
            return try applyPrintBorder(to: image, config: config, format: format)
        }
    }

    // MARK: - Solid Border

    private static func applySolidBorder(to image: CGImage, config: ProcessingConfig) throws -> CGImage {
        let borderPx = config.borderThickness.resolved(relativeTo: min(image.width, image.height))
        let totalW = image.width + 2 * borderPx + 2 * config.padding
        let totalH = image.height + 2 * borderPx + 2 * config.padding

        let bgColor = config.borderColor.cgColor

        guard let ctx = CGContext(data: nil,
                                  width: totalW,
                                  height: totalH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Fill background
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: totalH))

        // Draw image centered
        let imageX = borderPx + config.padding
        let imageY = borderPx + config.padding
        ctx.draw(image, in: CGRect(x: imageX, y: imageY, width: image.width, height: image.height))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Instagram Border

    private static func applyInstagramBorder(to image: CGImage, config: ProcessingConfig) throws -> CGImage {
        let maxSize = config.instagramMaxSize

        // Scale image to fit within maxSize
        let scale = min(Double(maxSize) / Double(image.width), Double(maxSize) / Double(image.height))
        let scaledW = Int(Double(image.width) * scale)
        let scaledH = Int(Double(image.height) * scale)

        // Canvas is Instagram 4:5 ratio, scaled to fit maxSize
        let canvasScale = Double(maxSize) / Double(max(instagramWidth, instagramHeight))
        let canvasW = Int(Double(instagramWidth) * canvasScale)
        let canvasH = Int(Double(instagramHeight) * canvasScale)

        let bgColor = config.borderColor.cgColor

        guard let ctx = CGContext(data: nil,
                                  width: canvasW,
                                  height: canvasH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Fill background
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        // Center image with border inset
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        let drawW = scaledW - 2 * borderPx
        let drawH = scaledH - 2 * borderPx
        let drawX = (canvasW - drawW) / 2
        let drawY = (canvasH - drawH) / 2

        ctx.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Print Border

    private static func applyPrintBorder(
        to image: CGImage,
        config: ProcessingConfig,
        format: PrintFormat
    ) throws -> BorderResult {
        let frameW = format.widthPixels
        let frameH = format.heightPixels

        // Auto-rotate vertical images 90° clockwise so they fill landscape print
        let img: CGImage
        if image.height > image.width {
            img = rotate90Clockwise(image)
        } else {
            img = image
        }

        // Available area after outer padding
        let availableW = frameW - 2 * config.outerPadding
        let availableH = frameH - 2 * config.outerPadding

        // Scale image to fit available area, maintaining aspect ratio
        let scale = min(
            Double(availableW) / Double(img.width),
            Double(availableH) / Double(img.height)
        )
        let scaledW = Int(Double(img.width) * scale)
        let scaledH = Int(Double(img.height) * scale)

        // Center image on canvas
        let imageX = (frameW - scaledW) / 2
        let imageY = (frameH - scaledH) / 2

        guard let ctx = CGContext(data: nil,
                                  width: frameW,
                                  height: frameH,
                                  bitsPerComponent: img.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: img.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: img.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Fill canvas with background color
        ctx.setFillColor(config.backgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: frameW, height: frameH))

        // Draw the scaled image centered
        ctx.draw(img, in: CGRect(x: imageX, y: imageY, width: scaledW, height: scaledH))

        // Draw border overlay rectangles on the image edges
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        ctx.setFillColor(config.borderColor.cgColor)

        // Bottom edge
        ctx.fill(CGRect(x: imageX, y: imageY, width: scaledW, height: borderPx))
        // Top edge
        ctx.fill(CGRect(x: imageX, y: imageY + scaledH - borderPx, width: scaledW, height: borderPx))
        // Left edge
        ctx.fill(CGRect(x: imageX, y: imageY, width: borderPx, height: scaledH))
        // Right edge
        ctx.fill(CGRect(x: imageX + scaledW - borderPx, y: imageY, width: borderPx, height: scaledH))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        return BorderResult(
            image: result,
            imageOrigin: CGPoint(x: imageX, y: imageY),
            imageSize: CGSize(width: scaledW, height: scaledH)
        )
    }

    // MARK: - Rotation Helper

    /// Rotates a CGImage 90° clockwise.
    private static func rotate90Clockwise(_ image: CGImage) -> CGImage {
        let newWidth = image.height
        let newHeight = image.width

        guard let ctx = CGContext(data: nil,
                                  width: newWidth,
                                  height: newHeight,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            return image
        }

        // Translate and rotate: move origin to bottom-right corner, then rotate -90°
        ctx.translateBy(x: CGFloat(newWidth), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return ctx.makeImage() ?? image
    }
}
