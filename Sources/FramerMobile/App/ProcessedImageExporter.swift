import Foundation
import FramerCore

@MainActor
struct ProcessedImageExporter {
    func exportAllProcessed(
        items: [PhotoItem],
        config: ProcessingConfig,
        exportDirectory: URL?
    ) async throws -> [URL] {
        let destinationDirectory = exportDirectory ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var exported: [URL] = []
        let fileExtension = config.outputFormat == .png ? "png" : "jpg"

        for item in items {
            let url = destinationDirectory
                .appendingPathComponent(item.url.deletingPathExtension().lastPathComponent + "_framed")
                .appendingPathExtension(fileExtension)
            let processor = FrameProcessor()
            try await processor.process(input: item.url, output: url, config: config, rotation: item.rotation)
            exported.append(url)
        }

        return exported
    }
}
