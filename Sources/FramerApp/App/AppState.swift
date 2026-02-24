import SwiftUI
import FramerCore

@MainActor
@Observable
final class AppState {
    var library: [PhotoItem] = []
    var selectedItems: Set<PhotoItem.ID> = []
    var currentConfig: ProcessingConfig = .default
    var activePresetName: String?
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
        let suffix = Self.exportSuffix(presetName: activePresetName)

        Task {
            let processor = FrameProcessor()
            var failedCount = 0
            for (i, item) in items.enumerated() {
                do {
                    let outURL = Self.outputURL(for: item, config: config, directory: directory, suffix: suffix)
                    try await processor.process(input: item.url, output: outURL, config: config)
                } catch {
                    failedCount += 1
                }
                if let idx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                    exportQueue[idx].completedCount = i + 1
                    exportQueue[idx].progress = Double(i + 1) / Double(items.count)
                }
            }
            if let idx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                exportQueue[idx].status = failedCount > 0
                    ? .failed("\(failedCount) of \(items.count) failed")
                    : .done
            }
        }
    }

    static func outputURL(for item: PhotoItem, config: ProcessingConfig, directory: URL, suffix: String) -> URL {
        let ext = config.outputFormat == .png ? "png" : "jpg"
        let stem = item.url.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(stem)_\(suffix).\(ext)")
    }

    // MARK: - Photo Import

    func addPhotos(from urls: [URL]) {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic"]
        var allFiles: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)
                ) ?? []
                allFiles += files.filter { imageExts.contains($0.pathExtension.lowercased()) }
            } else if imageExts.contains(url.pathExtension.lowercased()) {
                allFiles.append(url)
            }
        }
        let existing = Set(library.map(\.url))
        let newItems = allFiles
            .filter { !existing.contains($0) }
            .map { PhotoItem(url: $0) }
        library.append(contentsOf: newItems)
    }

    /// Sanitized filename suffix from preset name, falling back to "framed".
    static func exportSuffix(presetName: String?) -> String {
        guard let name = presetName, !name.isEmpty else { return "framed" }
        // Replace non-alphanumeric characters with underscores, collapse runs
        let sanitized = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "framed" : sanitized
    }
}

struct PhotoItem: Identifiable, Hashable, @unchecked Sendable {
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
