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
        sourceImage: CGImage,
        exif: ExifData,
        previewBaseDimension: Int? = nil
    ) throws -> BorderResult {
        var current = image
        var imageOrigin: CGPoint?
        var imageSize: CGSize?

        // Memoize dominant color: extract once if any layer needs it
        let needsDominant = layers.contains { layer in
            guard layer.isEnabled else { return false }
            switch layer {
            case .padding(let p):
                return p.fill.isDominant
            case .canvas(let p):
                return p.fill.isDominant
            default:
                return false
            }
        }
        let cachedDominant: HSLColor? = needsDominant
            ? ColorExtractor.extractDominantColor(from: sourceImage)
            : nil

        var i = 0
        while i < layers.count {
            try Task.checkCancellation()
            let layer = layers[i]

            guard layer.isEnabled else {
                i += 1
                continue
            }

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
                if abs(scale - 1.0) > 0.001 {
                    let newW = max(1, Int(Double(current.width) * scale))
                    let newH = max(1, Int(Double(current.height) * scale))
                    current = try resize(current, width: newW, height: newH)
                }

            case .border(let params):
                let thickness = params.thickness.resolved(relativeTo: min(current.width, current.height))
                guard thickness > 0 else { i += 1; continue }
                current = try addBorder(to: current, thickness: thickness, color: params.color.cgColor)

            case .padding(let params):
                guard params.thickness > 0 else { i += 1; continue }
                let fill = resolveLayerFill(params.fill, sourceImage: sourceImage, cachedDominant: cachedDominant)
                if case .solid(let color) = fill {
                    current = try addBorder(to: current, thickness: params.thickness, color: color)
                } else {
                    // Gradient fills: create a larger canvas with gradient background
                    let newW = current.width + params.thickness * 2
                    let newH = current.height + params.thickness * 2
                    guard let ctx = createContext(width: newW, height: newH, template: current) else {
                        i += 1; continue
                    }
                    fillBackground(fill, in: ctx, width: newW, height: newH)
                    ctx.draw(current, in: CGRect(x: params.thickness, y: params.thickness,
                                                  width: current.width, height: current.height))
                    if let result = ctx.makeImage() {
                        current = result
                    }
                }

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

            case .caption(let params):
                current = try CaptionRenderer.renderCaption(on: current, params: params, exif: exif, sourceImage: sourceImage)

            case .dither(let params):
                let rendered = try DitherRenderer.apply(to: current, params: params, previewBaseDimension: previewBaseDimension, sourceImage: sourceImage)
                current = try LayerCompositor.compose(
                    base: current, over: rendered,
                    mode: params.blendMode, opacity: params.opacity
                )

            case .aspectRatio(let params):
                let currentSize = CGSize(width: current.width, height: current.height)
                let cropRect = params.cropRect(for: currentSize)
                guard cropRect.width > 0, cropRect.height > 0,
                      let cropped = current.cropping(to: cropRect) else {
                    i += 1; continue
                }
                current = cropped

            case .lut(let params):
                guard !params.lutFileName.isEmpty,
                      let lut = LUTProvider.loadLUT(named: params.lutFileName) else {
                    i += 1; continue
                }
                let rendered = try LUTRenderer.apply(
                    to: current,
                    lut: lut,
                    intensity: params.intensity,
                    previewBaseDimension: previewBaseDimension
                )
                current = try LayerCompositor.compose(
                    base: current, over: rendered,
                    mode: params.blendMode, opacity: params.opacity
                )

            case .shader(let params):
                let rendered = try ShaderRenderer.apply(
                    to: current,
                    params: params,
                    previewBaseDimension: previewBaseDimension,
                    sourceImage: sourceImage
                )
                current = try LayerCompositor.compose(
                    base: current, over: rendered,
                    mode: params.blendMode, opacity: params.opacity
                )

            case .gpuEffect:
                break
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
        case .dominantColor(let params):
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            let adjusted = HSLColor(
                h: dominant.h,
                s: max(0, min(100, dominant.s + params.saturationShift)),
                l: max(0, min(100, dominant.l + params.lightnessShift))
            )
            return adjusted.cgColor
        case .gradientLinear, .gradientRadial:
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            return dominant.cgColor
        }
    }

    static func resolveLayerFill(_ fill: LayerFill, sourceImage: CGImage, cachedDominant: HSLColor? = nil) -> BackgroundFill {
        switch fill {
        case .color(let c):
            return .solid(c.cgColor)
        case .dominantColor(let params):
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            let adjusted = HSLColor(
                h: dominant.h,
                s: max(0, min(100, dominant.s + params.saturationShift)),
                l: max(0, min(100, dominant.l + params.lightnessShift))
            )
            return .solid(adjusted.cgColor)
        case .gradientLinear(let params):
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            let (center, edge) = ColorExtractor.generateGradientColors(
                dominant: dominant,
                saturationShift: params.saturationShift,
                lightnessShift: params.lightnessShift
            )
            return .linearGradient(start: center, end: edge)
        case .gradientRadial(let params):
            let dominant = cachedDominant ?? ColorExtractor.extractDominantColor(from: sourceImage)
            let (center, edge) = ColorExtractor.generateGradientColors(
                dominant: dominant,
                saturationShift: params.saturationShift,
                lightnessShift: params.lightnessShift
            )
            return .radialGradient(center: center, edge: edge)
        }
    }

    // MARK: - Layer Coalescing

    /// Returns true if there are ≥2 consecutive border/padding layers starting at `from`,
    /// and none of them use gradient fills (which need per-layer rendering).
    private static func canCoalesce(_ layers: [CompositionLayer], from start: Int) -> Bool {
        guard start + 1 < layers.count else { return false }
        var count = 0
        for j in start..<layers.count {
            guard layers[j].isEnabled else { return count >= 2 }
            switch layers[j] {
            case .border:
                count += 1
                continue
            case .padding(let p):
                if p.fill.isGradient { return count >= 2 }
                count += 1
                continue
            default:
                return count >= 2
            }
        }
        return count >= 2
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
        // Track a running virtual size so percent-based thicknesses resolve against
        // the same dimensions they would in the non-coalesced path (where `current`
        // grows after each border/padding layer).
        var virtualW = image.width
        var virtualH = image.height
        while j < layers.count {
            guard layers[j].isEnabled else { break }
            switch layers[j] {
            case .border(let p):
                let t = p.thickness.resolved(relativeTo: min(virtualW, virtualH))
                if t > 0 {
                    rings.append(Ring(thickness: t, color: p.color.cgColor))
                    virtualW += t * 2
                    virtualH += t * 2
                }
            case .padding(let p):
                if p.thickness > 0 {
                    let c = resolveLayerFillColor(p.fill, sourceImage: sourceImage, cachedDominant: cachedDominant)
                    rings.append(Ring(thickness: p.thickness, color: c))
                    virtualW += p.thickness * 2
                    virtualH += p.thickness * 2
                }
            default:
                break
            }
            // Check if next layer continues the run
            if j + 1 < layers.count {
                guard layers[j + 1].isEnabled else { break }
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
        let bgColor = resolveBackgroundColor(mode: config.backgroundMode, fallbackColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), sourceImage: image)
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
            padded = try addBorder(to: resized, thickness: padding, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        } else {
            padded = resized
        }

        // Step 3: Add border color around padded image
        let borderPx = config.borderThickness.resolved(relativeTo: min(scaledW, scaledH))
        let bordered = try addBorder(to: padded, thickness: borderPx, color: config.borderColor.cgColor)

        // Step 4: Center on fixed 1080×1350 canvas
        let bgFill = resolveBackground(mode: config.backgroundMode, fallbackColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), sourceImage: image)
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

        // All blend modes go through the vDSP-accelerated path.
        // The .normal path previously used a scalar Double loop over 12M+ pixels;
        // it is now vectorized inside blendWithAccelerate using the same lerp formula:
        //   result = base*(1-alpha) + over*alpha  ≡  base + (over-base)*alpha
        // which is the standard lerp used for the other modes as well.
        try blendWithAccelerate(
            base: base, over: over,
            pixelCount: pixelCount,
            blendMode: blendMode,
            opacity: clampedOpacity
        )

        guard let result = baseCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        return result
    }

    // MARK: - Accelerated Blend

    /// Vectorized per-pixel blend using Accelerate/vDSP for all blend modes.
    ///
    /// All temporary arrays are allocated as raw `UnsafeMutablePointer<Float>` rather than
    /// Swift `[Float]` values. This avoids ~300–400 MB of transient heap pressure on 12 MP
    /// images: `UnsafeMutablePointer.allocate` skips Swift Array's reference-counting and
    /// copy-on-write bookkeeping, reducing allocator round-trips from 15+ objects to a
    /// handful of contiguous slabs that are freed together at scope exit.
    ///
    /// The `.normal` blend mode is fully vectorized here. It was previously a scalar
    /// `Double` loop (`for i in 0..<pixelCount`). Now it uses the same lerp formula as
    /// the other modes — `result = base + (over - base) * alpha` — which is mathematically
    /// identical to `base*(1-alpha) + over*alpha`. The alpha (strength) mask is the
    /// luminance-deviation value already computed for every mode.
    ///
    /// The write-back step uses `vDSP_vfixu8` (vectorized float-to-UInt8 conversion)
    /// instead of a scalar loop with redundant `min`/`max` clamping. The values are already
    /// clamped to [0, 1] by the preceding `vDSP_vclip` calls before being scaled to [0, 255].
    ///
    /// - Parameters:
    ///   - base: Interleaved RGBA UInt8 input; result is written back in-place.
    ///   - over: Interleaved RGBA UInt8 overlay pixels (read-only after conversion).
    ///   - pixelCount: Number of pixels (width × height).
    ///   - blendMode: Blend equation to apply.
    ///   - opacity: Pre-clamped opacity in [0, 1].
    private static func blendWithAccelerate(
        base: UnsafeMutablePointer<UInt8>,
        over: UnsafeMutablePointer<UInt8>,
        pixelCount: Int,
        blendMode: OverlayBlendMode,
        opacity: Double
    ) throws {
        let totalBytes = pixelCount * 4
        let n = vDSP_Length(pixelCount)

        // ── Allocate all temporaries as raw Float slabs ──────────────────────────
        // Using UnsafeMutablePointer.allocate avoids Swift Array's COW metadata and
        // ARC overhead. All pointers are freed in the single defer block below.
        let baseF = UnsafeMutablePointer<Float>.allocate(capacity: totalBytes)
        let overF = UnsafeMutablePointer<Float>.allocate(capacity: totalBytes)
        let oR    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let oG    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let oB    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        // Overlay alpha channel. Frame Overlay PNGs carry real transparency
        // (alpha=0 in the centre window); without gating the strength mask
        // by this, those "transparent" pixels still darken the base because
        // CGBitmapContext rasterises them as premultiplied black (rgb=0,
        // alpha=0) and the luminance-deviation mask reads lum=0 as full
        // opacity. Multiplying `lum` by `oA` below zeroes out contributions
        // from genuinely-transparent overlay pixels. Grayscale overlays
        // (dust / light leak / wet plate) always ship with alpha=1 so the
        // factor is a no-op for them.
        let oA    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let lum   = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let bR    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let bG    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let bB    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let rR    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let rG    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let rB    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        // Temporaries shared by screen / softLight
        let t1    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let t2    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        let t3    = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)

        defer {
            baseF.deallocate(); overF.deallocate()
            oR.deallocate();    oG.deallocate();    oB.deallocate(); oA.deallocate()
            lum.deallocate()
            bR.deallocate();    bG.deallocate();    bB.deallocate()
            rR.deallocate();    rG.deallocate();    rB.deallocate()
            t1.deallocate();    t2.deallocate();    t3.deallocate()
        }

        // ── Convert interleaved RGBA UInt8 → Float32, normalised to 0–1 ──────────
        vDSP_vfltu8(base, 1, baseF, 1, vDSP_Length(totalBytes))
        vDSP_vfltu8(over, 1, overF, 1, vDSP_Length(totalBytes))
        var scale: Float = 1.0 / 255.0
        vDSP_vsmul(baseF, 1, &scale, baseF, 1, vDSP_Length(totalBytes))
        vDSP_vsmul(overF, 1, &scale, overF, 1, vDSP_Length(totalBytes))

        // ── De-interleave overlay into R, G, B, A (stride 4 → stride 1) ─────────
        deinterleaveRGB(overF, r: oR, g: oG, b: oB, pixelCount: pixelCount)
        vDSP_mmov(overF + 3, oA, 1, n, 4, 1)   // alpha channel (stride 4 starting at offset 3)

        // ── Compute luminance: L = 0.299*R + 0.587*G + 0.114*B ──────────────────
        var wr: Float = 0.299, wg: Float = 0.587, wb: Float = 0.114
        vDSP_vsmul(oR, 1, &wr, lum, 1, n)                  // lum  = 0.299 * oR
        vDSP_vsma(oG, 1, &wg, lum, 1, lum, 1, n)           // lum += 0.587 * oG
        vDSP_vsma(oB, 1, &wb, lum, 1, lum, 1, n)           // lum += 0.114 * oB

        // ── Strength mask: clamp(max(0, |lum - 0.5| - deadband) * 2 * opacity * overlay.alpha, 0, 1) ─
        // Deadband addresses JPEG-authored frame overlays where the
        // "transparent" centre is a mid-gray fill at byte 128 (lum ≈ 0.502)
        // rather than exactly 0.5 — without the deadband the 1-byte
        // deviation caused a visible darkening of every pixel in the frame's
        // window. The chosen 0.005 covers ~1/255 of luminance range; real
        // frame ink sits well outside this band so user-intended contributions
        // pass through essentially unchanged.
        var negHalf: Float = -0.5
        vDSP_vsadd(lum, 1, &negHalf, lum, 1, n)            // lum -= 0.5
        vDSP_vabs(lum, 1, lum, 1, n)                       // lum  = |lum|
        var negDeadband: Float = -0.005
        vDSP_vsadd(lum, 1, &negDeadband, lum, 1, n)        // lum -= deadband (negatives clip below)
        var strengthScale: Float = 2.0 * Float(opacity)
        vDSP_vsmul(lum, 1, &strengthScale, lum, 1, n)      // lum *= 2*opacity
        vDSP_vmul(lum, 1, oA, 1, lum, 1, n)                // lum *= overlay.alpha  ← Frame Overlay fix
        var lo: Float = 0, hi: Float = 1
        vDSP_vclip(lum, 1, &lo, &hi, lum, 1, n)            // lum  = clamp(lum, 0, 1)

        // ── De-interleave base R, G, B ────────────────────────────────────────────
        deinterleaveRGB(baseF, r: bR, g: bG, b: bB, pixelCount: pixelCount)

        // ── Blend per mode ────────────────────────────────────────────────────────
        switch blendMode {
        case .normal:
            // Normal uses the overlay pixel directly as the "blended" value.
            // The lerp below then computes: base*(1-alpha) + over*alpha — standard
            // alpha composite, where alpha is the luminance-deviation strength mask.
            // Equivalent to the removed scalar Double loop, but fully vectorized.
            vDSP_mmov(oR, rR, 1, n, 1, 1)
            vDSP_mmov(oG, rG, 1, n, 1, 1)
            vDSP_mmov(oB, rB, 1, n, 1, 1)

        case .screen:
            // Screen: result = 1 - (1-base)*(1-overlay)
            // vDSP_vsmsa(src, stride, &scalar, &addend, dst, stride, N)
            // computes dst[i] = src[i] * scalar + addend, so with scalar=-1, addend=1:
            //   dst[i] = src[i] * (-1) + 1 = 1 - src[i]
            var negOne: Float = -1.0
            var one: Float = 1.0
            // R
            vDSP_vsmsa(bR, 1, &negOne, &one, t1, 1, n)    // t1 = 1 - bR
            vDSP_vsmsa(oR, 1, &negOne, &one, t2, 1, n)    // t2 = 1 - oR
            vDSP_vmul(t1, 1, t2, 1, rR, 1, n)              // rR = (1-bR)*(1-oR)
            vDSP_vsmsa(rR, 1, &negOne, &one, rR, 1, n)     // rR = 1 - rR
            // G
            vDSP_vsmsa(bG, 1, &negOne, &one, t1, 1, n)
            vDSP_vsmsa(oG, 1, &negOne, &one, t2, 1, n)
            vDSP_vmul(t1, 1, t2, 1, rG, 1, n)
            vDSP_vsmsa(rG, 1, &negOne, &one, rG, 1, n)
            // B
            vDSP_vsmsa(bB, 1, &negOne, &one, t1, 1, n)
            vDSP_vsmsa(oB, 1, &negOne, &one, t2, 1, n)
            vDSP_vmul(t1, 1, t2, 1, rB, 1, n)
            vDSP_vsmsa(rB, 1, &negOne, &one, rB, 1, n)

        case .softLight:
            // Pegtop soft-light: (1 - 2*overlay)*base^2 + 2*overlay*base
            var two: Float = 2.0
            var negOne: Float = -1.0
            var one: Float = 1.0
            // R
            vDSP_vmul(bR, 1, bR, 1, t1, 1, n)            // t1 = bR^2
            vDSP_vsmul(oR, 1, &two, t2, 1, n)             // t2 = 2*oR
            vDSP_vsmsa(t2, 1, &negOne, &one, t3, 1, n)    // t3 = 1 - 2*oR
            vDSP_vmul(t3, 1, t1, 1, rR, 1, n)             // rR = (1-2*oR)*bR^2
            vDSP_vmul(t2, 1, bR, 1, t1, 1, n)             // t1 = 2*oR*bR
            vDSP_vadd(rR, 1, t1, 1, rR, 1, n)             // rR += 2*oR*bR
            // G
            vDSP_vmul(bG, 1, bG, 1, t1, 1, n)
            vDSP_vsmul(oG, 1, &two, t2, 1, n)
            vDSP_vsmsa(t2, 1, &negOne, &one, t3, 1, n)
            vDSP_vmul(t3, 1, t1, 1, rG, 1, n)
            vDSP_vmul(t2, 1, bG, 1, t1, 1, n)
            vDSP_vadd(rG, 1, t1, 1, rG, 1, n)
            // B
            vDSP_vmul(bB, 1, bB, 1, t1, 1, n)
            vDSP_vsmul(oB, 1, &two, t2, 1, n)
            vDSP_vsmsa(t2, 1, &negOne, &one, t3, 1, n)
            vDSP_vmul(t3, 1, t1, 1, rB, 1, n)
            vDSP_vmul(t2, 1, bB, 1, t1, 1, n)
            vDSP_vadd(rB, 1, t1, 1, rB, 1, n)

        case .multiply:
            // Multiply: base * overlay
            vDSP_vmul(bR, 1, oR, 1, rR, 1, n)
            vDSP_vmul(bG, 1, oG, 1, rG, 1, n)
            vDSP_vmul(bB, 1, oB, 1, rB, 1, n)
        }

        // ── Lerp: result = base + (blended - base) * strength ────────────────────
        // Reuse t1/t2/t3 as diff channels to avoid additional allocations.
        vDSP_vsub(bR, 1, rR, 1, t1, 1, n)                 // t1 = rR - bR
        vDSP_vsub(bG, 1, rG, 1, t2, 1, n)
        vDSP_vsub(bB, 1, rB, 1, t3, 1, n)
        vDSP_vma(t1, 1, lum, 1, bR, 1, rR, 1, n)          // rR = t1*lum + bR
        vDSP_vma(t2, 1, lum, 1, bG, 1, rG, 1, n)
        vDSP_vma(t3, 1, lum, 1, bB, 1, rB, 1, n)

        // ── Clamp to [0, 1] ───────────────────────────────────────────────────────
        vDSP_vclip(rR, 1, &lo, &hi, rR, 1, n)
        vDSP_vclip(rG, 1, &lo, &hi, rG, 1, n)
        vDSP_vclip(rB, 1, &lo, &hi, rB, 1, n)

        // ── Scale to [0, 255] and convert back to UInt8 using vDSP_vfixu8 ────────
        // vDSP_vfixu8 performs vectorized float-to-UInt8 truncation after rounding.
        // Values are already clamped to [0, 1] above, so multiplying by 255 produces
        // values in [0, 255] — no redundant scalar min/max clamping needed.
        // Re-interleave: write R/G/B directly into base[] with stride 4.
        var s255: Float = 255.0
        vDSP_vsmul(rR, 1, &s255, rR, 1, n)
        vDSP_vsmul(rG, 1, &s255, rG, 1, n)
        vDSP_vsmul(rB, 1, &s255, rB, 1, n)

        // Re-interleave R/G/B back into the strided base buffer using vDSP_vfixu8.
        // vDSP_vfixu8(src, srcStride, dst, dstStride, N) supports non-unit output
        // stride, so each channel can be written directly at offset 0/1/2 with
        // dstStride=4, scattering values into the correct byte lanes.
        // Alpha (base + 3) is left unchanged.
        vDSP_vfixu8(rR, 1, base + 0, 4, n)
        vDSP_vfixu8(rG, 1, base + 1, 4, n)
        vDSP_vfixu8(rB, 1, base + 2, 4, n)
    }

    /// De-interleaves an interleaved RGBA Float buffer into separate R, G, B channel buffers.
    ///
    /// Uses `vDSP_mmov` with a source stride of 4 (one element per RGBA group) and a
    /// destination stride of 1. The alpha channel is not extracted.
    ///
    /// - Parameters:
    ///   - rgba: Interleaved RGBA Float buffer with `pixelCount * 4` elements.
    ///   - r: Output buffer for the red channel; must have capacity `pixelCount`.
    ///   - g: Output buffer for the green channel; must have capacity `pixelCount`.
    ///   - b: Output buffer for the blue channel; must have capacity `pixelCount`.
    ///   - pixelCount: Number of pixels.
    private static func deinterleaveRGB(
        _ rgba: UnsafePointer<Float>,
        r: UnsafeMutablePointer<Float>,
        g: UnsafeMutablePointer<Float>,
        b: UnsafeMutablePointer<Float>,
        pixelCount: Int
    ) {
        // vDSP_mmov with M=1 row of N elements, source matrix stride 4, dest stride 1
        // effectively gathers every 4th element starting at the given offset.
        vDSP_mmov(rgba + 0, r, 1, vDSP_Length(pixelCount), 4, 1)
        vDSP_mmov(rgba + 1, g, 1, vDSP_Length(pixelCount), 4, 1)
        vDSP_mmov(rgba + 2, b, 1, vDSP_Length(pixelCount), 4, 1)
    }

    // MARK: - Context Helper

    private static func createContext(width: Int, height: Int, template: CGImage) -> CGContext? {
        // Ignore `template.bitmapInfo` — some ImageIO-decoded sources
        // carry flag combinations (e.g. `kCGImageAlphaLast | kCGImage-
        // PixelFormatPacked`) that `CGBitmapContextCreate` rejects.
        // Always allocate a canonical premultipliedLast RGBA8 context;
        // `ctx.draw(template, ...)` converts the source on the fly.
        _ = template
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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
