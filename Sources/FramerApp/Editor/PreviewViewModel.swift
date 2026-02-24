import SwiftUI
import FramerCore

@MainActor
@Observable
final class PreviewViewModel {
    var previewImage: NSImage?
    var isLoading = false
    var error: String?
    var exifData: ExifData?

    private var renderTask: Task<Void, Never>?
    private let processor = FrameProcessor()

    func updatePreview(for item: PhotoItem?, config: ProcessingConfig) {
        guard let item else {
            previewImage = nil
            exifData = nil
            error = nil
            return
        }

        renderTask?.cancel()
        renderTask = Task {
            // Debounce: wait 150ms before rendering
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            isLoading = true
            error = nil

            do {
                let exif = try? EXIFReader.read(from: item.url)
                exifData = exif

                let image = try await processor.previewImage(for: item.url, config: config)
                guard !Task.isCancelled else { return }
                previewImage = image
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
