// Sources/FramerCore/Processing/BorderRenderer.swift
import Foundation
import CoreGraphics

public enum BorderRenderer {
    // Instagram frame constants (4:5)
    static let instagramWidth = 1080
    static let instagramHeight = 1350

    public static func applyBorder(
        to image: CGImage,
        config: ProcessingConfig,
        style: BorderStyle
    ) throws -> CGImage {
        switch style {
        case .solid:
            return try applySolidBorder(to: image, config: config)
        case .instagram:
            return try applyInstagramBorder(to: image, config: config)
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
}
