// Sources/FramerCore/Processing/BorderRenderer.swift
import Foundation
import CoreGraphics

// MARK: - BorderResult

public struct BorderResult {
    public let image: CGImage
    /// Position where the photo was drawn on the final canvas.
    public let imageOrigin: CGPoint?
    /// Size of the photo as drawn on the final canvas.
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

    // MARK: - Layer-Based Composition

    /// Evaluates a layer stack inside-out, folding each layer over the current image.
    public static func applyLayers(
        _ layers: [CompositionLayer],
        to image: CGImage,
        sourceImage: CGImage
    ) throws -> BorderResult {
        var current = image
        var imageOrigin: CGPoint?
        var imageSize: CGSize?

        for layer in layers {
            switch layer {
            case .resize(let params):
                let maxW = params.maxWidth
                let maxH = params.maxHeight
                guard maxW > 0, maxH > 0 else { continue }
                let scale = min(Double(maxW) / Double(current.width), Double(maxH) / Double(current.height))
                if scale < 1.0 {
                    let newW = Int(Double(current.width) * scale)
                    let newH = Int(Double(current.height) * scale)
                    current = try resize(current, width: newW, height: newH)
                }

            case .border(let params):
                let thickness = params.thickness.resolved(relativeTo: min(current.width, current.height))
                guard thickness > 0 else { continue }
                current = try addBorder(to: current, thickness: thickness, color: params.color.cgColor)

            case .padding(let params):
                guard params.thickness > 0 else { continue }
                let fillColor = resolveLayerFillColor(params.fill, sourceImage: sourceImage)
                current = try addBorder(to: current, thickness: params.thickness, color: fillColor)

            case .canvas(let params):
                guard params.width > 0, params.height > 0 else { continue }
                let bgFill = resolveLayerFill(params.fill, sourceImage: sourceImage)
                let (canvas, ox, oy) = try centerOnCanvas(
                    current, width: params.width, height: params.height, background: bgFill
                )
                current = canvas
                imageOrigin = CGPoint(x: ox, y: oy)
                imageSize = CGSize(width: current.width, height: current.height)
            }
        }

        return BorderResult(image: current, imageOrigin: imageOrigin, imageSize: imageSize)
    }

    // MARK: - Layer Fill Resolution

    static func resolveLayerFillColor(_ fill: LayerFill, sourceImage: CGImage) -> CGColor {
        switch fill {
        case .color(let c):
            return c.cgColor
        case .dominantColor:
            return ColorExtractor.extractDominantColor(from: sourceImage).cgColor
        case .gradientLinear, .gradientRadial:
            // For solid-color contexts (addBorder), fall back to dominant
            return ColorExtractor.extractDominantColor(from: sourceImage).cgColor
        }
    }

    static func resolveLayerFill(_ fill: LayerFill, sourceImage: CGImage) -> BackgroundFill {
        switch fill {
        case .color(let c):
            return .solid(c.cgColor)
        case .dominantColor:
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

    // MARK: - Solid Border (matches Go createSolidBorder)

    private static func applySolidBorder(to image: CGImage, config: ProcessingConfig) throws -> BorderResult {
        let borderPx = config.borderThickness.resolved(relativeTo: min(image.width, image.height))
        let padding = config.padding

        // Step 1: Wrap image with border color
        let bordered = try addBorder(to: image, thickness: borderPx, color: config.borderColor.cgColor)

        // Step 2: Wrap bordered image with padding (white / background)
        let bgColor = resolveBackgroundColor(mode: config.backgroundMode, fallbackColor: .white, sourceImage: image)
        let final: CGImage
        if padding > 0 {
            final = try addBorder(to: bordered, thickness: padding, color: bgColor)
        } else {
            final = bordered
        }

        return BorderResult(image: final, imageOrigin: nil, imageSize: nil)
    }

    // MARK: - Instagram Border (matches Go createInstagramFrame)

    private static func applyInstagramBorder(to image: CGImage, config: ProcessingConfig) throws -> BorderResult {
        let maxSize = config.instagramMaxSize

        // Step 1: Resize image to fit within maxSize (aspect-ratio preserving)
        let scale = min(Double(maxSize) / Double(image.width), Double(maxSize) / Double(image.height))
        let scaledW = Int(Double(image.width) * scale)
        let scaledH = Int(Double(image.height) * scale)
        let resized = try resize(image, width: scaledW, height: scaledH)

        // Step 2: Add padding (white) around resized image
        let padding = config.padding
        let padded: CGImage
        if padding > 0 {
            padded = try addBorder(to: resized, thickness: padding, color: .white)
        } else {
            padded = resized
        }

        // Step 3: Add border color around padded image
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        let bordered = try addBorder(to: padded, thickness: borderPx, color: config.borderColor.cgColor)

        // Step 4: Center on fixed 1080×1350 canvas
        let bgFill = resolveBackground(mode: config.backgroundMode, fallbackColor: .white, sourceImage: image)
        let (final, originX, originY) = try centerOnCanvas(
            bordered, width: instagramWidth, height: instagramHeight, background: bgFill
        )

        // Calculate where the actual photo sits on the final canvas
        let imageX = originX + borderPx + padding
        let imageY = originY + borderPx + padding

        return BorderResult(
            image: final,
            imageOrigin: CGPoint(x: imageX, y: imageY),
            imageSize: CGSize(width: scaledW, height: scaledH)
        )
    }

    // MARK: - Print Border (matches Go createPrint10x15Frame)

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

        // Step 1: Resize image to fit available area, maintaining aspect ratio
        let scale = min(
            Double(availableW) / Double(img.width),
            Double(availableH) / Double(img.height)
        )
        let scaledW = Int(Double(img.width) * scale)
        let scaledH = Int(Double(img.height) * scale)
        let resized = try resize(img, width: scaledW, height: scaledH)

        // Step 2: Center resized image on fixed-size canvas with background
        let bgFill = resolveBackground(mode: config.backgroundMode, fallbackColor: config.backgroundColor.cgColor, sourceImage: img)
        let (canvas, imageX, imageY) = try centerOnCanvas(
            resized, width: frameW, height: frameH, background: bgFill
        )

        // Step 3: Draw border overlay rectangles on the image edges
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        let final: CGImage
        if borderPx > 0 {
            final = try drawBorderOverlay(
                on: canvas, at: CGPoint(x: imageX, y: imageY),
                size: CGSize(width: scaledW, height: scaledH),
                thickness: borderPx, color: config.borderColor.cgColor
            )
        } else {
            final = canvas
        }

        return BorderResult(
            image: final,
            imageOrigin: CGPoint(x: imageX, y: imageY),
            imageSize: CGSize(width: scaledW, height: scaledH)
        )
    }

    // MARK: - Image Primitives

    /// Resize an image to exact dimensions (like Go's imaging.Resize).
    private static func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else { return image }
        guard let ctx = createContext(width: width, height: height, template: image) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    /// Wrap an image with a uniform-colored border of given thickness.
    /// Creates a new image that is (w + 2*thickness) × (h + 2*thickness).
    /// (Like Go's: newRGBA(bordered size) → fill with color → paste image at offset)
    private static func addBorder(to image: CGImage, thickness: Int, color: CGColor) throws -> CGImage {
        guard thickness > 0 else { return image }
        let newW = image.width + 2 * thickness
        let newH = image.height + 2 * thickness
        guard let ctx = createContext(width: newW, height: newH, template: image) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        // Fill with border color
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
        // Paste image centered
        ctx.draw(image, in: CGRect(x: thickness, y: thickness, width: image.width, height: image.height))
        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    /// Center an image on a fixed-size canvas with a background fill.
    /// Returns the final image and the (x, y) origin where the source image was placed.
    private static func centerOnCanvas(
        _ image: CGImage,
        width: Int,
        height: Int,
        background: BackgroundFill
    ) throws -> (CGImage, Int, Int) {
        guard let ctx = createContext(width: width, height: height, template: image) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        // Fill background
        fillBackground(background, in: ctx, width: width, height: height)
        // Center image
        let x = (width - image.width) / 2
        let y = (height - image.height) / 2
        ctx.draw(image, in: CGRect(x: x, y: y, width: image.width, height: image.height))
        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return (result, x, y)
    }

    /// Draw 4 border-overlay rectangles on the edges of an image region (for print style).
    private static func drawBorderOverlay(
        on canvas: CGImage,
        at origin: CGPoint,
        size: CGSize,
        thickness: Int,
        color: CGColor
    ) throws -> CGImage {
        guard let ctx = createContext(width: canvas.width, height: canvas.height, template: canvas) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        // Draw existing canvas
        ctx.draw(canvas, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        ctx.setFillColor(color)

        let x = Int(origin.x)
        let y = Int(origin.y)
        let w = Int(size.width)
        let h = Int(size.height)

        // Bottom edge
        ctx.fill(CGRect(x: x, y: y, width: w, height: thickness))
        // Top edge
        ctx.fill(CGRect(x: x, y: y + h - thickness, width: w, height: thickness))
        // Left edge
        ctx.fill(CGRect(x: x, y: y, width: thickness, height: h))
        // Right edge
        ctx.fill(CGRect(x: x + w - thickness, y: y, width: thickness, height: h))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Context Helper

    private static func createContext(width: Int, height: Int, template: CGImage) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: template.bitsPerComponent,
            bytesPerRow: 0,
            space: template.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: template.bitmapInfo.rawValue
        )
    }

    // MARK: - Background Resolution

    enum BackgroundFill {
        case solid(CGColor)
        case linearGradient(start: CGColor, end: CGColor)
        case radialGradient(center: CGColor, edge: CGColor)
    }

    /// Resolve background mode to a single solid color (for addBorder/padding).
    private static func resolveBackgroundColor(
        mode: BackgroundMode,
        fallbackColor: CGColor,
        sourceImage: CGImage
    ) -> CGColor {
        switch mode {
        case .color:
            return fallbackColor
        case .dominant:
            return ColorExtractor.extractDominantColor(from: sourceImage).cgColor
        case .gradientLinear, .gradientRadial:
            // For wrapping borders, use dominant as solid fallback
            return ColorExtractor.extractDominantColor(from: sourceImage).cgColor
        }
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
            // Top-to-bottom (CGContext Y: 0 is bottom)
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

        guard let ctx = createContext(width: newWidth, height: newHeight, template: image) else {
            return image
        }

        ctx.translateBy(x: CGFloat(newWidth), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return ctx.makeImage() ?? image
    }

    // MARK: - CGColor Constants

    private static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
}
