import Foundation
import CoreGraphics

/// Computes the final output dimensions by walking the layer stack without rendering.
public enum OutputSizeCalculator {

    /// Compute the output dimensions by walking the layer stack without rendering.
    public static func outputSize(for inputSize: CGSize, layers: [CompositionLayer]) -> CGSize {
        var size = inputSize

        for layer in layers {
            switch layer {
            case .border(let params):
                let shorter = Int(min(size.width, size.height))
                let thickness = CGFloat(params.thickness.resolved(relativeTo: shorter))
                size = CGSize(
                    width: size.width + thickness * 2,
                    height: size.height + thickness * 2
                )

            case .padding(let params):
                let thickness = CGFloat(params.thickness)
                size = CGSize(
                    width: size.width + thickness * 2,
                    height: size.height + thickness * 2
                )

            case .canvas(let params):
                size = CGSize(width: CGFloat(params.width), height: CGFloat(params.height))

            case .resize(let params):
                let maxW = CGFloat(params.maxWidth)
                let maxH = CGFloat(params.maxHeight)
                // Only downscale, never upscale
                if size.width > maxW || size.height > maxH {
                    let scale = min(maxW / size.width, maxH / size.height)
                    size = CGSize(
                        width: (size.width * scale).rounded(.down),
                        height: (size.height * scale).rounded(.down)
                    )
                }

            case .overlay, .orientation, .caption, .dither:
                break
            }
        }

        return size
    }
}
