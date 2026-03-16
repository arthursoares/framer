import Foundation
import CoreImage
import CoreGraphics

/// Converts a `[CompositionLayer]` stack into a Core Image filter chain,
/// producing a `CIImage` output.
public enum CIFilterPipeline {

    /// Whether a layer can be fully processed on the GPU via Core Image.
    /// Layers that return `false` need CPU fallback (BorderRenderer).
    public static func canProcessOnGPU(_ layer: CompositionLayer) -> Bool {
        switch layer {
        case .border, .padding, .canvas, .resize, .overlay:
            return true
        case .dither(let params):
            // Only B&W Bayer dithering is implemented on GPU
            switch params.colorMode {
            case .bw:
                return true
            default:
                return false
            }
        case .orientation, .caption:
            return false
        }
    }

    /// Split a layer stack into runs of GPU-capable and CPU-required layers.
    /// Returns an array of (isGPU: Bool, layers: [CompositionLayer]) tuples.
    public static func partitionLayers(_ layers: [CompositionLayer]) -> [(isGPU: Bool, layers: [CompositionLayer])] {
        guard !layers.isEmpty else { return [] }
        var result: [(isGPU: Bool, layers: [CompositionLayer])] = []
        var currentIsGPU = canProcessOnGPU(layers[0])
        var currentRun: [CompositionLayer] = [layers[0]]

        for layer in layers.dropFirst() {
            let gpu = canProcessOnGPU(layer)
            if gpu == currentIsGPU {
                currentRun.append(layer)
            } else {
                result.append((isGPU: currentIsGPU, layers: currentRun))
                currentIsGPU = gpu
                currentRun = [layer]
            }
        }
        result.append((isGPU: currentIsGPU, layers: currentRun))
        return result
    }

    /// Apply the full layer stack to a CIImage, returning the composited result.
    /// Only processes GPU-capable layers; CPU-only layers are skipped (no-op).
    public static func apply(
        layers: [CompositionLayer],
        to image: CIImage,
        sourceImage: CIImage,
        exif: ExifData
    ) -> CIImage {
        var current = image
        for layer in layers {
            current = applyLayer(layer, to: current, sourceImage: sourceImage, exif: exif)
        }
        return current
    }

    // MARK: - Private

    private static func applyLayer(
        _ layer: CompositionLayer,
        to image: CIImage,
        sourceImage: CIImage,
        exif: ExifData
    ) -> CIImage {
        switch layer {
        case .border(let params):
            return applyBorder(params, to: image)
        case .padding(let params):
            return applyPadding(params, to: image)
        case .canvas(let params):
            return applyCanvas(params, to: image)
        case .resize(let params):
            return applyResize(params, to: image)
        case .overlay(let params):
            return applyOverlay(params, to: image)
        case .orientation:
            // Known limitation: orientation not yet implemented in CI pipeline.
            // Video orientation is handled by AVAssetReader's preferredTrackTransform.
            return image
        case .caption:
            // Known limitation: caption rendering not yet implemented in CI pipeline.
            // Captions are applied via the existing CGImage-based CaptionRenderer for still images.
            return image
        case .dither(let params):
            return applyDither(params, to: image)
        }
    }

    // MARK: - Border

    private static func applyBorder(_ params: BorderLayerParams, to image: CIImage) -> CIImage {
        let extent = image.extent
        let shorterDimension = Int(min(extent.width, extent.height))
        let thickness = CGFloat(params.thickness.resolved(relativeTo: shorterDimension))

        let newWidth = extent.width + thickness * 2
        let newHeight = extent.height + thickness * 2

        let bgColor = CIColor(
            red: CGFloat(params.color.red),
            green: CGFloat(params.color.green),
            blue: CGFloat(params.color.blue),
            alpha: 1.0
        )
        let background = CIImage(color: bgColor)
            .cropped(to: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        let translated = image.transformed(by: CGAffineTransform(translationX: thickness, y: thickness))
        return translated.composited(over: background)
    }

    // MARK: - Padding

    private static func applyPadding(_ params: PaddingLayerParams, to image: CIImage) -> CIImage {
        let extent = image.extent
        let thickness = CGFloat(params.thickness)

        let newWidth = extent.width + thickness * 2
        let newHeight = extent.height + thickness * 2

        let fillColor: CIColor
        switch params.fill {
        case .color(let c):
            fillColor = CIColor(
                red: CGFloat(c.red),
                green: CGFloat(c.green),
                blue: CGFloat(c.blue),
                alpha: 1.0
            )
        default:
            // Known limitation: gradient and dominant color fills not yet implemented in CI pipeline.
            // Falls back to white background.
            fillColor = CIColor.white
        }

        let background = CIImage(color: fillColor)
            .cropped(to: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        let translated = image.transformed(by: CGAffineTransform(translationX: thickness, y: thickness))
        return translated.composited(over: background)
    }

    // MARK: - Canvas

    private static func applyCanvas(_ params: CanvasLayerParams, to image: CIImage) -> CIImage {
        let canvasWidth = CGFloat(params.width)
        let canvasHeight = CGFloat(params.height)

        let fillColor: CIColor
        switch params.fill {
        case .color(let c):
            fillColor = CIColor(
                red: CGFloat(c.red),
                green: CGFloat(c.green),
                blue: CGFloat(c.blue),
                alpha: 1.0
            )
        default:
            // Known limitation: gradient and dominant color fills not yet implemented in CI pipeline.
            // Falls back to white background.
            fillColor = CIColor.white
        }

        let background = CIImage(color: fillColor)
            .cropped(to: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        let extent = image.extent
        let offsetX = (canvasWidth - extent.width) / 2
        let offsetY = (canvasHeight - extent.height) / 2

        let translated = image.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        return translated.composited(over: background)
    }

    // MARK: - Resize

    private static func applyResize(_ params: ResizeLayerParams, to image: CIImage) -> CIImage {
        let extent = image.extent
        let scaleX = CGFloat(params.maxWidth) / extent.width
        let scaleY = CGFloat(params.maxHeight) / extent.height
        let scale = min(scaleX, scaleY)

        // Don't upscale
        guard scale < 1.0 else { return image }

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        return filter.outputImage ?? image
    }

    // MARK: - Dither

    private static func applyDither(_ params: DitherLayerParams, to image: CIImage) -> CIImage {
        let extent = image.extent
        let pixelScale = max(1, min(8, params.pixelScale))

        var working = image

        // Step 1: If pixelScale > 1, downscale with Lanczos
        if pixelScale > 1 {
            let scaleFactor = 1.0 / CGFloat(pixelScale)
            guard let downFilter = CIFilter(name: "CILanczosScaleTransform") else { return image }
            downFilter.setValue(working, forKey: kCIInputImageKey)
            downFilter.setValue(scaleFactor, forKey: kCIInputScaleKey)
            downFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            working = downFilter.outputImage ?? working
        }

        // Step 2: Apply DitherCIFilter (Bayer dithering via CIFilter chain)
        let ditherFilter = DitherCIFilter()
        ditherFilter.inputImage = working
        ditherFilter.threshold = Float(params.threshold)
        ditherFilter.bayerLevel = params.bayerLevel
        working = ditherFilter.outputImage ?? working

        // Step 3: If pixelScale > 1, upscale back with nearest-neighbor (CIAffineTransform)
        if pixelScale > 1 {
            let upscale = CGAffineTransform(scaleX: CGFloat(pixelScale), y: CGFloat(pixelScale))
            let upscaled = working.transformed(by: upscale, highQualityDownsample: false)
            // Crop to original extent to handle any rounding differences
            working = upscaled.cropped(to: extent)
        }

        return working
    }

    // MARK: - Overlay

    private static func applyOverlay(_ params: OverlayLayerParams, to image: CIImage) -> CIImage {
        // Resolve overlay texture URL
        guard let overlayURL = TextureFrameProvider.overlayURL(forName: params.overlayName) else {
            return image
        }

        // Load the overlay image
        guard let overlayCGImage = TextureFrameProvider.loadFullImage(for: overlayURL) else {
            return image
        }

        let extent = image.extent
        var overlayCI = CIImage(cgImage: overlayCGImage)

        // Scale overlay to match image dimensions
        let overlayExtent = overlayCI.extent
        let scaleX = extent.width / overlayExtent.width
        let scaleY = extent.height / overlayExtent.height
        overlayCI = overlayCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Apply opacity (0-100 range in params)
        let opacity = max(0, min(1, params.opacity / 100.0))
        if opacity < 1.0 {
            // Apply opacity using CIColorMatrix on the overlay's alpha channel
            guard let opacityFilter = CIFilter(name: "CIColorMatrix") else { return image }
            opacityFilter.setValue(overlayCI, forKey: kCIInputImageKey)
            opacityFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            opacityFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")
            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            overlayCI = opacityFilter.outputImage ?? overlayCI
        }

        // Apply blend mode
        let blended: CIImage
        switch params.blendMode {
        case .screen:
            blended = applyBlend(name: "CIScreenBlendMode", foreground: overlayCI, background: image)
        case .multiply:
            blended = applyBlend(name: "CIMultiplyBlendMode", foreground: overlayCI, background: image)
        case .softLight:
            blended = applyBlend(name: "CISoftLightBlendMode", foreground: overlayCI, background: image)
        case .normal:
            // Normal mode: composite overlay over base image
            blended = applyBlend(name: "CISourceOverCompositing", foreground: overlayCI, background: image)
        }

        return blended.cropped(to: extent)
    }

    /// Apply a named blend mode CIFilter with foreground over background.
    private static func applyBlend(name: String, foreground: CIImage, background: CIImage) -> CIImage {
        guard let filter = CIFilter(name: name) else {
            return foreground.composited(over: background)
        }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? foreground.composited(over: background)
    }
}
