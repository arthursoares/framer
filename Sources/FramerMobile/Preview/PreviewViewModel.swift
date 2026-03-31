import SwiftUI
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    var previewImage: UIImage?
    var originalImage: UIImage?
    var isLoading = false
    var error: String?
    var outputSize: CGSize?

    private var renderTask: Task<Void, Never>?
    private let processor = FrameProcessor()

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig) {
        guard let item else {
            previewImage = nil
            originalImage = nil
            error = nil
            outputSize = nil
            return
        }

        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            isLoading = true
            error = nil

            do {
                let itemURL = item.url
                let itemRotation = item.rotation
                let originalHandle = Task.detached {
                    Self.loadOriginal(from: itemURL, maxDimension: 1200)
                }
                let cgPreview = try await processor.previewCGImage(for: itemURL, config: config, rotation: itemRotation)
                let preview = UIImage(cgImage: cgPreview)
                let original = await originalHandle.value
                guard !Task.isCancelled else { return }
                originalImage = original
                previewImage = preview
                outputSize = CGSize(width: cgPreview.width, height: cgPreview.height)
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private nonisolated static func loadOriginal(from url: URL, maxDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let w = cgImage.width, h = cgImage.height
        guard max(w, h) > maxDimension else {
            return UIImage(cgImage: cgImage)
        }
        let scale = Double(maxDimension) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)
        guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: cgImage.bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: cgImage.bitmapInfo.rawValue),
              let scaled = (ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH)), ctx.makeImage()).1 else {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(cgImage: scaled)
    }
}
