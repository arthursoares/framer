// Sources/FramerCore/Processing/BorderRenderer.swift
import Foundation
import CoreGraphics
import ImageIO
import Accelerate

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

    // Scaled overlay cache: avoids re-resizing overlays when dimensions haven't changed
    private final class _CGImageBox: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    private static let _scaledOverlayCache: NSCache<NSString, _CGImageBox> = {
        let cache = NSCache<NSString, _CGImageBox>()
        cache.countLimit = 5
        return cache
    }()

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

        // Memoize dominant color: extract once if any layer needs it
        let needsDominant = layers.contains { layer in
            switch layer {
            case .padding(let p):
                return p.fill == .dominantColor || p.fill == .gradientLinear || p.fill == .gradientRadial
            case .canvas(let p):
                return p.fill == .dominantColor || p.fill == .gradientLinear || p.fill == .gradientRadial
            default:
                return false
            }
        }
        let cachedDominant: HSLColor? = needsDominant
            ? ColorExtractor.extractDominantColor(from: sourceImage)
            : nil

        var i = 0
        while i < layers.count {
            let layer = layers[i]

            // Phase 4A: coalesce consecutive border/padding layers into single context
            if case .border = layer, canCoalesce(layers, from: i) {
                let (coalesced, consumed) = try coalesceRun(
                    layers, from: i, image: current, sourceImage: sourceImage, cachedDominant: cachedDominant
                )
                current = coalesced
                i += consumed
                continue
            }
            if case .padding = layer, canCoalesce(layers, from: i) {
                let (coalesced, consumed) = try coalesceRun(
                    layers, from: i, image: current, sourceImage: sourceImage, cachedDominant: cachedDominant
                )
                current = coalesced
                i += consumed
                continue
            }

            switch layer {
            case .resize(let params):
                let maxW = params.maxWidth
                let maxH = params.maxHeight
                guard maxW > 0, maxH > 0 else { i += 1; continue }
                let scale = min(Double(maxW) / Double(current.width), Double(maxH) / Double(current.height))
                if scale < 1.0 {
                    let newW = Int(Double(current.width) * scale)
                    let newH = Int(Double(current.height) * scale)
                    current = try resize(current, width: newW, height: newH)
                }

            case .border(let params):
                let thickness = params.thickness.resolved(relativeTo: min(current.width, current.height))
                guard thickness > 0 else { i += 1; continue }
                current = try addBorder(to: current, thickness: thickness, color: params.color.cgColor)

            case .padding(let params):
                guard params.thickness > 0 else { i += 1; continue }
                let fillColor = resolveLayerFillColor(params.fill, sourceImage: sourceImage, cachedDominant: cachedDominant)
                current = try addBorder(to: current, thickness: params.thickness, color: fillColor)

            case .canvas(let params):
                guard params.width > 0, params.height > 0 else { i += 1; continue }
                let bgFill = resolveLayerFill(params.fill, sourceImage: sourceImage, cachedDominant: cachedDominant)
                let photoSize = CGSize(width: current.width, height: current.height)
                let (canvas, ox, oy) = try centerOnCanvas(
                    current, width: params.width, height: params.height, background: bgFill
                )
                current = canvas
                imageOrigin = CGPoint(x: ox, y: oy)
                imageSize = photoSize

            case .overlay(let params):
                guard !params.overlayName.isEmpty,
                      let overlayURL = TextureFrameProvider.overlayURL(forName: params.overlayName),
                      let overlayImage = TextureFrameProvider.loadFullImage(for: overlayURL) else {
                    i += 1; continue
                }
                let cacheKey = "\(params.overlayName)_\(current.width)x\(current.height)"
                current = try applyOverlay(
                    to: current,
                    overlayImage: overlayImage,
                    blendMode: params.blendMode,
                    opacity: params.opacity / 100.0,
                    scaledCacheKey: cacheKey
                )

            case .orientation(let params):
                let isLandscape = current.width >= current.height
                let wantsLandscape = params.target == .landscape
                if isLandscape != wantsLandscape {
                    current = rotate90Clockwise(current)
                }
            }
            i += 1
        }

        return BorderResult(image: current, imageOrigin: imageOrigin, imageSize: imageSize)
    }

    // MARK: - Layer Fill Resolution

    static func resolveLayerFillColor(_ fill: LayerFill, sourceImage: CGImage, cachedDominant: HSLColor? = nil) -> CGColor {
        switch fill {
        case .color(let c):
            return c.cgColor
        case .dominantColor:
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            return dominant.cgColor
        case .gradientLinear, .gradientRadial:
            // For solid-color contexts (addBorder), fall back to dominant
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            return dominant.cgColor
        }
    }

    static func resolveLayerFill(_ fill: LayerFill, sourceImage: CGImage, cachedDominant: HSLColor? = nil) -> BackgroundFill {
        switch fill {
        case .color(let c):
            return .solid(c.cgColor)
        case .dominantColor:
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            return .solid(dominant.cgColor)
        case .gradientLinear:
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            let (center, edge) = ColorExtractor.generateGradientColors(dominant: dominant)
            return .linearGradient(start: center, end: edge)
        case .gradientRadial:
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            let (center, edge) = ColorExtractor.generateGradientColors(dominant: dominant)
            return .radialGradient(center: center, edge: edge)
        }
    }

    // MARK: - Layer Coalescing

    /// Returns true if there are ≥2 consecutive border/padding layers starting at `from`.
    private static func canCoalesce(_ layers: [CompositionLayer], from start: Int) -> Bool {
        guard start + 1 < layers.count else { return false }
        for j in start..<min(start + 2, layers.count) {
            switch layers[j] {
            case .border, .padding: continue
            default: return false
            }
        }
        return true
    }

    /// Merges a run of consecutive border/padding layers into a single CGContext.
    /// Returns the composited image and the number of layers consumed.
    private static func coalesceRun(
        _ layers: [CompositionLayer],
        from start: Int,
        image: CGImage,
        sourceImage: CGImage,
        cachedDominant: HSLColor?
    ) throws -> (CGImage, Int) {
        // Collect the run of border/padding layers with their resolved thicknesses + colors
        struct Ring {
            let thickness: Int
            let color: CGColor
        }
        var rings: [Ring] = []
        var j = start
        while j < layers.count {
            switch layers[j] {
            case .border(let p):
                // Use the *original* image size for resolving relative sizes — each ring
                // wraps the one inside it, but BorderSize is resolved relative to the
                // innermost image (same as the non-coalesced path where `current` is
                // the image before this run started).
                let t = p.thickness.resolved(relativeTo: min(image.width, image.height))
                if t > 0 { rings.append(Ring(thickness: t, color: p.color.cgColor)) }
            case .padding(let p):
                if p.thickness > 0 {
                    let c = resolveLayerFillColor(p.fill, sourceImage: sourceImage, cachedDominant: cachedDominant)
                    rings.append(Ring(thickness: p.thickness, color: c))
                }
            default:
                break
            }
            // Check if next layer continues the run
            if j + 1 < layers.count {
                switch layers[j + 1] {
                case .border, .padding: j += 1; continue
                default: break
                }
            }
            j += 1
            break
        }

        let consumed = j - start

        // If only zero-thickness rings remain, return image unchanged
        guard !rings.isEmpty else { return (image, consumed) }

        // Compute total thickness
        let totalThickness = rings.reduce(0) { $0 + $1.thickness }
        let newW = image.width + 2 * totalThickness
        let newH = image.height + 2 * totalThickness

        guard let ctx = createContext(width: newW, height: newH, template: image) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        // Fill rings from outside-in
        var inset = 0
        for ring in rings.reversed() {
            ctx.setFillColor(ring.color)
            ctx.fill(CGRect(x: inset, y: inset, width: newW - 2 * inset, height: newH - 2 * inset))
            inset += ring.thickness
        }

        // Draw original image at center
        ctx.draw(image, in: CGRect(x: totalThickness, y: totalThickness, width: image.width, height: image.height))

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return (result, consumed)
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

    // MARK: - Overlay Blending
    //
    // Composites a texture overlay onto the photo using one of four blend modes:
    //
    // Normal:    Luminance-deviation alpha. Mid-gray (L=0.5) → transparent.
    //            Good for frames and dust — the overlay replaces the photo where it deviates from gray.
    //
    // Screen:    Additive: result = 1 - (1-base)(1-overlay). Only lightens, never darkens.
    //            Good for light leaks — simulates light being added to the exposure.
    //
    // Soft Light: Subtle contrast: brightens where overlay > 0.5, darkens where < 0.5.
    //            Good for wet plate and film grain — natural tonal shifts.
    //
    // Multiply:  Darkening: result = base × overlay. Only darkens, never lightens.
    //            Good for burn edges and vignettes.
    //
    // All modes use luminance-deviation from gray as the strength mask:
    //   α = |luminance - 0.5| × 2.0 × opacity
    // This ensures gray areas remain transparent regardless of blend mode.

    private static func applyOverlay(
        to image: CGImage,
        overlayImage: CGImage,
        blendMode: OverlayBlendMode,
        opacity: Double,
        scaledCacheKey: String? = nil
    ) throws -> CGImage {
        let width = image.width
        let height = image.height

        // Scale overlay to match image dimensions (with caching)
        let scaledOverlay: CGImage
        if overlayImage.width == width && overlayImage.height == height {
            scaledOverlay = overlayImage
        } else if let key = scaledCacheKey,
                  let cached = _scaledOverlayCache.object(forKey: key as NSString) {
            scaledOverlay = cached.image
        } else {
            let resized = try resize(overlayImage, width: width, height: height)
            if let key = scaledCacheKey {
                _scaledOverlayCache.setObject(_CGImageBox(resized), forKey: key as NSString)
            }
            scaledOverlay = resized
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let pixelCount = width * height

        // Rasterize both images into RGBA8 buffers
        guard let baseCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        baseCtx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let overlayCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        overlayCtx.draw(scaledOverlay, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let baseData = baseCtx.data, let overlayData = overlayCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let base = baseData.bindMemory(to: UInt8.self, capacity: pixelCount * 4)
        let over = overlayData.bindMemory(to: UInt8.self, capacity: pixelCount * 4)
        let clampedOpacity = min(max(opacity, 0), 1.0)

        // For normal mode, we can skip reading base pixels (just alpha-composite)
        if blendMode == .normal {
            // Fast path: modify overlay alpha in-place, then composite via CG
            for i in 0..<pixelCount {
                let offset = i * 4
                let r = Double(over[offset]) / 255.0
                let g = Double(over[offset + 1]) / 255.0
                let b = Double(over[offset + 2]) / 255.0
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                let alpha = min(abs(luminance - 0.5) * 2.0 * clampedOpacity, 1.0)
                over[offset]     = UInt8(min(r * alpha * 255.0, 255))
                over[offset + 1] = UInt8(min(g * alpha * 255.0, 255))
                over[offset + 2] = UInt8(min(b * alpha * 255.0, 255))
                over[offset + 3] = UInt8(alpha * 255.0)
            }
            guard let maskedOverlay = overlayCtx.makeImage() else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            baseCtx.draw(maskedOverlay, in: CGRect(x: 0, y: 0, width: width, height: height))

        } else {
            // vDSP-accelerated blend for screen/softLight/multiply
            try blendWithAccelerate(
                base: base, over: over,
                pixelCount: pixelCount,
                blendMode: blendMode,
                opacity: clampedOpacity
            )
        }

        guard let result = baseCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Accelerated Blend

    /// Vectorized per-pixel blend using Accelerate/vDSP.
    /// Operates on interleaved RGBA UInt8 buffers in-place (writes result to `base`).
    private static func blendWithAccelerate(
        base: UnsafeMutablePointer<UInt8>,
        over: UnsafeMutablePointer<UInt8>,
        pixelCount: Int,
        blendMode: OverlayBlendMode,
        opacity: Double
    ) throws {
        let totalBytes = pixelCount * 4

        // Convert interleaved RGBA UInt8 → Float32 normalized to 0–1
        var baseF = [Float](repeating: 0, count: totalBytes)
        var overF = [Float](repeating: 0, count: totalBytes)
        vDSP_vfltu8(base, 1, &baseF, 1, vDSP_Length(totalBytes))
        vDSP_vfltu8(over, 1, &overF, 1, vDSP_Length(totalBytes))
        var scale: Float = 1.0 / 255.0
        vDSP_vsmul(baseF, 1, &scale, &baseF, 1, vDSP_Length(totalBytes))
        vDSP_vsmul(overF, 1, &scale, &overF, 1, vDSP_Length(totalBytes))

        // De-interleave overlay into R, G, B channels (stride 4)
        var oR = [Float](repeating: 0, count: pixelCount)
        var oG = [Float](repeating: 0, count: pixelCount)
        var oB = [Float](repeating: 0, count: pixelCount)
        deinterleaveRGB(overF, r: &oR, g: &oG, b: &oB, pixelCount: pixelCount)

        // Compute luminance: L = 0.299*R + 0.587*G + 0.114*B
        var luminance = [Float](repeating: 0, count: pixelCount)
        var wr: Float = 0.299, wg: Float = 0.587, wb: Float = 0.114
        // luminance = wr * oR
        vDSP_vsmul(oR, 1, &wr, &luminance, 1, vDSP_Length(pixelCount))
        // luminance += wg * oG
        vDSP_vsma(oG, 1, &wg, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))
        // luminance += wb * oB
        vDSP_vsma(oB, 1, &wb, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))

        // Strength mask: strength = clamp(|luminance - 0.5| * 2.0 * opacity, 0, 1)
        var negHalf: Float = -0.5
        vDSP_vsadd(luminance, 1, &negHalf, &luminance, 1, vDSP_Length(pixelCount))
        vDSP_vabs(luminance, 1, &luminance, 1, vDSP_Length(pixelCount))
        var strengthScale: Float = 2.0 * Float(opacity)
        vDSP_vsmul(luminance, 1, &strengthScale, &luminance, 1, vDSP_Length(pixelCount))
        var lo: Float = 0, hi: Float = 1
        vDSP_vclip(luminance, 1, &lo, &hi, &luminance, 1, vDSP_Length(pixelCount))

        // De-interleave base R, G, B
        var bR = [Float](repeating: 0, count: pixelCount)
        var bG = [Float](repeating: 0, count: pixelCount)
        var bB = [Float](repeating: 0, count: pixelCount)
        deinterleaveRGB(baseF, r: &bR, g: &bG, b: &bB, pixelCount: pixelCount)

        // Blend per mode
        var rR = [Float](repeating: 0, count: pixelCount)
        var rG = [Float](repeating: 0, count: pixelCount)
        var rB = [Float](repeating: 0, count: pixelCount)
        let n = vDSP_Length(pixelCount)

        switch blendMode {
        case .screen:
            // Screen: 1 - (1-base)*(1-overlay)
            let ones = [Float](repeating: 1, count: pixelCount)
            var t1 = [Float](repeating: 0, count: pixelCount)
            var t2 = [Float](repeating: 0, count: pixelCount)
            // R channel
            vDSP_vsub(bR, 1, ones, 1, &t1, 1, n) // t1 = 1 - bR
            vDSP_vsub(oR, 1, ones, 1, &t2, 1, n) // t2 = 1 - oR
            vDSP_vmul(t1, 1, t2, 1, &rR, 1, n)
            vDSP_vsub(rR, 1, ones, 1, &rR, 1, n) // rR = 1 - t1*t2
            // G channel
            vDSP_vsub(bG, 1, ones, 1, &t1, 1, n)
            vDSP_vsub(oG, 1, ones, 1, &t2, 1, n)
            vDSP_vmul(t1, 1, t2, 1, &rG, 1, n)
            vDSP_vsub(rG, 1, ones, 1, &rG, 1, n)
            // B channel
            vDSP_vsub(bB, 1, ones, 1, &t1, 1, n)
            vDSP_vsub(oB, 1, ones, 1, &t2, 1, n)
            vDSP_vmul(t1, 1, t2, 1, &rB, 1, n)
            vDSP_vsub(rB, 1, ones, 1, &rB, 1, n)

        case .softLight:
            // Pegtop: (1 - 2*overlay) * base^2 + 2*overlay*base
            var two: Float = 2.0
            var t1 = [Float](repeating: 0, count: pixelCount)
            var t2 = [Float](repeating: 0, count: pixelCount)
            var t3 = [Float](repeating: 0, count: pixelCount)
            // R channel
            vDSP_vmul(bR, 1, bR, 1, &t1, 1, n)       // t1 = bR^2
            vDSP_vsmul(oR, 1, &two, &t2, 1, n)        // t2 = 2*oR
            let ones = [Float](repeating: 1, count: pixelCount)
            vDSP_vsub(t2, 1, ones, 1, &t3, 1, n)      // t3 = 1 - 2*oR
            vDSP_vmul(t3, 1, t1, 1, &rR, 1, n)        // rR = (1-2*oR)*bR^2
            vDSP_vmul(t2, 1, bR, 1, &t1, 1, n)        // t1 = 2*oR*bR
            vDSP_vadd(rR, 1, t1, 1, &rR, 1, n)        // rR += 2*oR*bR
            // G channel
            vDSP_vmul(bG, 1, bG, 1, &t1, 1, n)
            vDSP_vsmul(oG, 1, &two, &t2, 1, n)
            vDSP_vsub(t2, 1, ones, 1, &t3, 1, n)
            vDSP_vmul(t3, 1, t1, 1, &rG, 1, n)
            vDSP_vmul(t2, 1, bG, 1, &t1, 1, n)
            vDSP_vadd(rG, 1, t1, 1, &rG, 1, n)
            // B channel
            vDSP_vmul(bB, 1, bB, 1, &t1, 1, n)
            vDSP_vsmul(oB, 1, &two, &t2, 1, n)
            vDSP_vsub(t2, 1, ones, 1, &t3, 1, n)
            vDSP_vmul(t3, 1, t1, 1, &rB, 1, n)
            vDSP_vmul(t2, 1, bB, 1, &t1, 1, n)
            vDSP_vadd(rB, 1, t1, 1, &rB, 1, n)

        case .multiply:
            // Multiply: base * overlay
            vDSP_vmul(bR, 1, oR, 1, &rR, 1, n)
            vDSP_vmul(bG, 1, oG, 1, &rG, 1, n)
            vDSP_vmul(bB, 1, oB, 1, &rB, 1, n)

        case .normal:
            // Already handled in fast path; copy base if we somehow get here
            rR = bR; rG = bG; rB = bB
        }

        // Lerp: final = base + (blended - base) * strength
        var diffR = [Float](repeating: 0, count: pixelCount)
        var diffG = [Float](repeating: 0, count: pixelCount)
        var diffB = [Float](repeating: 0, count: pixelCount)
        vDSP_vsub(bR, 1, rR, 1, &diffR, 1, n) // diffR = rR - bR
        vDSP_vsub(bG, 1, rG, 1, &diffG, 1, n)
        vDSP_vsub(bB, 1, rB, 1, &diffB, 1, n)
        vDSP_vma(diffR, 1, luminance, 1, bR, 1, &rR, 1, n) // rR = diffR*strength + bR
        vDSP_vma(diffG, 1, luminance, 1, bG, 1, &rG, 1, n)
        vDSP_vma(diffB, 1, luminance, 1, bB, 1, &rB, 1, n)

        // Clamp to 0-1
        vDSP_vclip(rR, 1, &lo, &hi, &rR, 1, n)
        vDSP_vclip(rG, 1, &lo, &hi, &rG, 1, n)
        vDSP_vclip(rB, 1, &lo, &hi, &rB, 1, n)

        // Scale to 0-255 and re-interleave back into base buffer
        var s255: Float = 255.0
        vDSP_vsmul(rR, 1, &s255, &rR, 1, n)
        vDSP_vsmul(rG, 1, &s255, &rG, 1, n)
        vDSP_vsmul(rB, 1, &s255, &rB, 1, n)

        for i in 0..<pixelCount {
            let off = i * 4
            base[off]     = UInt8(min(max(rR[i], 0), 255))
            base[off + 1] = UInt8(min(max(rG[i], 0), 255))
            base[off + 2] = UInt8(min(max(rB[i], 0), 255))
            // alpha stays unchanged
        }
    }

    /// De-interleaves RGBA float buffer into separate R, G, B channel arrays using strided copy.
    private static func deinterleaveRGB(
        _ rgba: [Float],
        r: inout [Float], g: inout [Float], b: inout [Float],
        pixelCount: Int
    ) {
        rgba.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!
            // vDSP strided gather: source stride 4, dest stride 1
            let src0 = ptr
            let src1 = ptr + 1
            let src2 = ptr + 2
            r.withUnsafeMutableBufferPointer { rBuf in
                vDSP_mmov(src0, rBuf.baseAddress!, 1, vDSP_Length(pixelCount), 4, 1)
            }
            g.withUnsafeMutableBufferPointer { gBuf in
                vDSP_mmov(src1, gBuf.baseAddress!, 1, vDSP_Length(pixelCount), 4, 1)
            }
            b.withUnsafeMutableBufferPointer { bBuf in
                vDSP_mmov(src2, bBuf.baseAddress!, 1, vDSP_Length(pixelCount), 4, 1)
            }
        }
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
