import SwiftUI
import FramerCore

@Observable
final class AppState {
    var library: [PhotoItem] = []
    var selectedItems: Set<PhotoItem.ID> = []
    var currentConfig: ProcessingConfig = .default
    var presets: [Preset] = []
    var presetStore = PresetStore()
    var exportQueue: [ExportJob] = []

    // Navigation
    enum Tab { case library, presets, queue }
    var activeTab: Tab = .library

    init() {
        presetStore.initializeDefaults()
        loadPresets()
    }

    func loadPresets() {
        presets = (try? presetStore.list()) ?? []
    }

    var selectedPhoto: PhotoItem? {
        selectedItems.first.flatMap { id in
            library.first { $0.id == id }
        }
    }

    // MARK: - Export

    func exportItems(_ items: [PhotoItem], to directory: URL) {
        var job = ExportJob(items: items, config: currentConfig, outputDirectory: directory)
        job.status = .running
        exportQueue.append(job)
        activeTab = .queue

        let jobId = job.id
        let config = currentConfig

        Task {
            let processor = FrameProcessor()
            var failedCount = 0
            for (i, item) in items.enumerated() {
                do {
                    let outURL = Self.outputURL(for: item, config: config, directory: directory)
                    try await processor.process(input: item.url, output: outURL, config: config)
                } catch {
                    failedCount += 1
                }
                await MainActor.run {
                    if let idx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                        exportQueue[idx].completedCount = i + 1
                        exportQueue[idx].progress = Double(i + 1) / Double(items.count)
                    }
                }
            }
            await MainActor.run {
                if let idx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                    exportQueue[idx].status = failedCount > 0
                        ? .failed("\(failedCount) of \(items.count) failed")
                        : .done
                }
            }
        }
    }

    static func outputURL(for item: PhotoItem, config: ProcessingConfig, directory: URL) -> URL {
        let ext = config.outputFormat == .png ? "png" : "jpg"
        let stem = item.url.deletingPathExtension().lastPathComponent
        let suffix: String
        switch config.borderStyle {
        case .solid: suffix = "_solid"
        case .instagram: suffix = "_instagram"
        case .print: suffix = "_print"
        }
        return directory.appendingPathComponent("\(stem)\(suffix).\(ext)")
    }
}

struct PhotoItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var thumbnail: NSImage?

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ExportJob: Identifiable {
    let id = UUID()
    let items: [PhotoItem]
    let config: ProcessingConfig
    let outputDirectory: URL
    var progress: Double = 0
    var completedCount: Int = 0
    var status: JobStatus = .queued

    enum JobStatus: Equatable {
        case queued, running, done, failed(String)
    }
}
