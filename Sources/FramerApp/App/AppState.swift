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

    // MARK: - Video Export

    var videoCodec: VideoCodec = .h264
    var videoExportProgress: Double = 0
    var isExportingVideo: Bool = false


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
        exportItems(items, to: directory, config: currentConfig, suffix: Self.exportSuffix(presetName: activePresetName))
    }

    func exportItems(_ items: [PhotoItem], to directory: URL, withPresets presetConfigs: [(name: String, config: ProcessingConfig)]) {
        for (name, config) in presetConfigs {
            let suffix = Self.exportSuffix(presetName: name)
            exportItems(items, to: directory, config: config, suffix: suffix)
        }
    }

    private func exportItems(_ items: [PhotoItem], to directory: URL, config: ProcessingConfig, suffix: String) {
        var job = ExportJob(items: items, config: config, outputDirectory: directory, label: suffix)
        job.status = .running
        exportQueue.append(job)
        let jobId = job.id

        Task {
            let maxConcurrency = ProcessInfo.processInfo.processorCount
            let videoCodec = self.videoCodec
            var completed = 0
            var failedCount = 0

            await withTaskGroup(of: Bool.self) { group in
                var index = 0

                func addExportTask(for item: PhotoItem) {
                    group.addTask {
                        let outURL = Self.outputURL(for: item, config: config, directory: directory, suffix: suffix)
                        do {
                            if Self.isVideoFile(item.url) {
                                let msg = "AppState: starting video export \(item.url.lastPathComponent) -> \(outURL.lastPathComponent)\n"
                                if let h = FileHandle(forWritingAtPath: "/tmp/vproc.log") {
                                    h.seekToEndOfFile(); h.write(msg.data(using: .utf8)!); h.closeFile()
                                } else { try? msg.write(toFile: "/tmp/vproc.log", atomically: false, encoding: .utf8) }

                                let videoConfig = VideoExportConfig(codec: videoCodec)
                                let processor = VideoProcessor()
                                try await processor.process(
                                    input: item.url,
                                    output: outURL,
                                    config: config,
                                    videoExport: videoConfig
                                )
                            } else {
                                let processor = FrameProcessor()
                                try await processor.process(input: item.url, output: outURL, config: config, rotation: item.rotation)
                            }
                            return true
                        } catch {
                            print("Export failed for \(item.url.lastPathComponent): \(error)")
                            return false
                        }
                    }
                }

                // Seed initial batch up to max concurrency
                for _ in 0..<min(maxConcurrency, items.count) {
                    addExportTask(for: items[index])
                    index += 1
                }

                // Drain results and feed remaining items one-for-one
                for await success in group {
                    completed += 1
                    if !success { failedCount += 1 }

                    if let qIdx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                        exportQueue[qIdx].completedCount = completed
                        exportQueue[qIdx].progress = Double(completed) / Double(items.count)
                    }

                    if index < items.count {
                        addExportTask(for: items[index])
                        index += 1
                    }
                }
            }

            if let qIdx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                exportQueue[qIdx].status = failedCount > 0
                    ? .failed("\(failedCount) of \(items.count) failed")
                    : .done
            }
        }
    }

    nonisolated static func outputURL(for item: PhotoItem, config: ProcessingConfig, directory: URL, suffix: String) -> URL {
        let ext: String
        if isVideoFile(item.url) {
            ext = "mp4"
        } else {
            ext = config.outputFormat == .png ? "png" : "jpg"
        }
        let stem = item.url.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(stem)_\(suffix).\(ext)")
    }

    // MARK: - Video Export

    nonisolated static func isVideoFile(_ url: URL) -> Bool {
        FrameProcessor.isVideoFile(url)
    }

    func exportVideo(item: PhotoItem, outputURL: URL, trimRange: TrimRange? = nil) async throws {
        isExportingVideo = true
        videoExportProgress = 0
        defer { isExportingVideo = false }

        let videoConfig = VideoExportConfig(codec: videoCodec, trim: trimRange)
        let processor = VideoProcessor()
        await processor.onProgress { [weak self] progress in
            Task { @MainActor in
                self?.videoExportProgress = progress.fraction
            }
        }
        try await processor.process(
            input: item.url,
            output: outputURL,
            config: currentConfig,
            videoExport: videoConfig
        )
    }

    // MARK: - Photo Import

    func addPhotos(from urls: [URL]) {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic"]
        let supportedExts = imageExts.union(FrameProcessor.videoExtensions)
        var allFiles: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)
                ) ?? []
                allFiles += files.filter { supportedExts.contains($0.pathExtension.lowercased()) }
            } else if supportedExts.contains(url.pathExtension.lowercased()) {
                allFiles.append(url)
            }
        }
        let existing = Set(library.map(\.url))
        let newItems = allFiles
            .filter { !existing.contains($0) }
            .map { PhotoItem(url: $0) }
        let wasEmpty = library.isEmpty
        library.append(contentsOf: newItems)
        // Auto-select first photo when adding to empty library
        if wasEmpty, let first = newItems.first {
            selectedItems = [first.id]
        }
    }

    func rotateItem(_ id: PhotoItem.ID, clockwise: Bool) {
        guard let idx = library.firstIndex(where: { $0.id == id }) else { return }
        let delta = clockwise ? 90 : -90
        library[idx].rotation = (library[idx].rotation + delta + 360) % 360
    }

    func retryJob(_ job: ExportJob) {
        guard case .failed = job.status else { return }
        exportQueue.removeAll { $0.id == job.id }
        exportItems(job.items, to: job.outputDirectory)
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

struct PhotoItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    /// Manual rotation in degrees (0, 90, 180, 270).
    var rotation: Int = 0

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ExportJob: Identifiable {
    let id = UUID()
    let items: [PhotoItem]
    let config: ProcessingConfig
    let outputDirectory: URL
    var label: String?
    var progress: Double = 0
    var completedCount: Int = 0
    var status: JobStatus = .queued

    enum JobStatus: Equatable {
        case queued, running, done, failed(String)
    }
}
