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
            return try applySolidBorder(to: image, config: config)
        case .instagram:
            return try applyInstagramBorder(to: image, config: config)
        case .print(let format):
            return try applyPrintBorder(to: image, config: config, format: format)
        }
    }

    // MARK: - Solid Border

    private static func applySolidBorder(to image: CGImage, config: ProcessingConfig) throws -> BorderResult {
        let borderPx = config.borderThickness.resolved(relativeTo: min(image.width, image.height))
        let padding = config.padding

        // Go layout: image → borderColor → white padding (outside)
        // Inner layer: bordered image
        let borderedW = image.width + 2 * borderPx
        let borderedH = image.height + 2 * borderPx
        // Outer layer: padding outside the border
        let totalW = borderedW + 2 * padding
        let totalH = borderedH + 2 * padding

        guard let ctx = CGContext(data: nil,
                                  width: totalW,
                                  height: totalH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // 1. Fill entire canvas with padding color (white / background mode)
        let bg = resolveBackground(mode: config.backgroundMode, fallbackColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), sourceImage: image)
        fillBackground(bg, in: ctx, width: totalW, height: totalH)

        // 2. Fill bordered area with border color (inside the padding)
        ctx.setFillColor(config.borderColor.cgColor)
        ctx.fill(CGRect(x: padding, y: padding, width: borderedW, height: borderedH))

        // 3. Draw image centered inside the border
        let imageX = padding + borderPx
        let imageY = padding + borderPx
        ctx.draw(image, in: CGRect(x: imageX, y: imageY, width: image.width, height: image.height))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return BorderResult(image: result, imageOrigin: nil, imageSize: nil)
    }

    // MARK: - Instagram Border

    private static func applyInstagramBorder(to image: CGImage, config: ProcessingConfig) throws -> BorderResult {
        let maxSize = config.instagramMaxSize

        // 1. Scale image to fit within maxSize (aspect-ratio preserving)
        let scale = min(Double(maxSize) / Double(image.width), Double(maxSize) / Double(image.height))
        let scaledW = Int(Double(image.width) * scale)
        let scaledH = Int(Double(image.height) * scale)

        // 2. Calculate layered dimensions: image → padding → border (additive)
        let padding = config.padding
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        let borderedW = scaledW + 2 * padding + 2 * borderPx
        let borderedH = scaledH + 2 * padding + 2 * borderPx

        // 3. Fixed 4:5 canvas (matching Go implementation)
        let canvasW = instagramWidth   // 1080
        let canvasH = instagramHeight  // 1350

        guard let ctx = CGContext(data: nil,
                                  width: canvasW,
                                  height: canvasH,
                                  bitsPerComponent: image.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: image.bitmapInfo.rawValue) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // 4. Fill canvas with background
        let bg = resolveBackground(mode: config.backgroundMode, fallbackColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), sourceImage: image)
        fillBackground(bg, in: ctx, width: canvasW, height: canvasH)

        // 5. Center bordered area on canvas, fill with border color
        let bx = (canvasW - borderedW) / 2
        let by = (canvasH - borderedH) / 2
        ctx.setFillColor(config.borderColor.cgColor)
        ctx.fill(CGRect(x: bx, y: by, width: borderedW, height: borderedH))

        // 6. Fill padding area with white (inside border)
        if padding > 0 {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: bx + borderPx, y: by + borderPx,
                            width: borderedW - 2 * borderPx, height: borderedH - 2 * borderPx))
        }

        // 7. Draw image at correct aspect-ratio-preserving dimensions
        let imageX = bx + borderPx + padding
        let imageY = by + borderPx + padding
        ctx.draw(image, in: CGRect(x: imageX, y: imageY, width: scaledW, height: scaledH))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return BorderResult(
            image: result,
            imageOrigin: CGPoint(x: imageX, y: imageY),
            imageSize: CGSize(width: scaledW, height: scaledH)
        )
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

        // Fill canvas with background
        let bg = resolveBackground(mode: config.backgroundMode, fallbackColor: config.backgroundColor.cgColor, sourceImage: img)
        fillBackground(bg, in: ctx, width: frameW, height: frameH)

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

    // MARK: - Background Resolution

    private enum BackgroundFill {
        case solid(CGColor)
        case linearGradient(start: CGColor, end: CGColor)
        case radialGradient(center: CGColor, edge: CGColor)
    }

    private static func resolveBackground(
        mode: BackgroundMode,
        fallbackColor: CGColor,
        sourceImage: CGImage
    ) -> BackgroundFill {
        switch mode {
        case .color:
            return .solid(fallbackColor)
        case .dominant:
            let dominant = ColorExtractor.extractDominantColor(from: sourceImage)
            return .solid(dominant.cgColor)
        case .gradientLinear:
            let dominant = ColorExtractor.extractDominantColor(from: sourceImage)
            let (center, edge) = ColorExtractor.generateGradientColors(dominant: dominant)
            return .linearGradient(start: center, end: edge)
        case .gradientRadial:
            let dominant = ColorExtractor.extractDominantColor(from: sourceImage)
            let (center, edge) = ColorExtractor.generateGradientColors(dominant: dominant)
            return .radialGradient(center: center, edge: edge)
        }
    }

    private static func fillBackground(_ fill: BackgroundFill, in ctx: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        switch fill {
        case .solid(let color):
            ctx.setFillColor(color)
            ctx.fill(rect)

        case .linearGradient(let startColor, let endColor):
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace,
                                            colors: [startColor, endColor] as CFArray,
                                            locations: [0.0, 1.0]) else {
                ctx.setFillColor(startColor)
                ctx.fill(rect)
                return
            }
            // Top-to-bottom (CGContext has flipped Y: 0 is bottom)
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height)),
                                   end: CGPoint(x: CGFloat(width) / 2, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        case .radialGradient(let centerColor, let edgeColor):
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace,
                                            colors: [centerColor, edgeColor] as CFArray,
                                            locations: [0.0, 1.0]) else {
                ctx.setFillColor(centerColor)
                ctx.fill(rect)
                return
            }
            let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            let radius = sqrt(CGFloat(width * width + height * height)) / 2
            ctx.drawRadialGradient(gradient,
                                    startCenter: center, startRadius: 0,
                                    endCenter: center, endRadius: radius,
                                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
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
