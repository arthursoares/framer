import Foundation
import CoreImage
import CoreGraphics

/// Converts a `[CompositionLayer]` stack into a Core Image filter chain,
/// producing a `CIImage` output.
public enum CIFilterPipeline {

    /// Apply the full layer stack to a CIImage, returning the composited result.
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
        case .overlay:
            // TODO: Metal kernel in Task 4
            return image
        case .orientation:
            // TODO: orientation transform
            return image
        case .caption:
            // TODO: CoreText rendering
            return image
        case .dither:
            // TODO: Metal kernel in Task 4
            return image
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
            // TODO: implement gradient and dominant color fills
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
            // TODO: implement gradient and dominant color fills
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
}
