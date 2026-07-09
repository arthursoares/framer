import SwiftUI
import FramerCore

@MainActor
@Observable
final class AppState {
    var library: [PhotoItem] = []
    var selectedItems: Set<PhotoItem.ID> = []
    var currentConfig: ProcessingConfig = .default
    var activePresetName: String?
    /// Snapshot of the config when a preset was applied — used to detect manual overrides.
    var appliedPresetConfig: ProcessingConfig?

    /// True when a preset is active but config has been manually modified.
    var isPresetModified: Bool {
        guard activePresetName != nil, let applied = appliedPresetConfig else { return false }
        return currentConfig != applied
    }
    var presets: [Preset] = []
    var presetStore = PresetStore()
    var exportQueue: [ExportJob] = []
    private var exportTasks: [UUID: Task<Void, Never>] = [:]

    /// Cached preset-preview thumbnails. A separate `@Observable` instance so
    /// writes during a background render batch invalidate only views that
    /// actually read the cache (the Presets grid), not every view tracking
    /// AppState properties generally.
    let presetThumbnailCache = PresetThumbnailCache()


    init() {
        presetStore.initializeDefaults()
        loadPresets()
    }

    func loadPresets() {
        presets = (try? presetStore.list()) ?? []
    }

    var selectedPhoto: PhotoItem? {
        library.first { selectedItems.contains($0.id) }
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

        // `.utility` priority avoids the same CoreGraphics priority inversion
        // the preview render hits: `processor.process` runs on the FrameProcessor
        // actor, which escalates to the awaiter's QoS; at User-initiated the
        // synchronous CG draws inside BorderRenderer block on CG's Default-QoS
        // internal threads. Export is batch work with its own progress UI, so
        // utility is the right band — TaskGroup children inherit this priority.
        let task = Task(priority: .utility) {
            defer { exportTasks.removeValue(forKey: jobId) }
            let maxConcurrency = Self.recommendedExportConcurrency(itemCount: items.count)
            var completed = 0
            var failedCount = 0

            await withTaskGroup(of: Bool.self) { group in
                var index = 0

                // Seed initial batch up to max concurrency
                for _ in 0..<min(maxConcurrency, items.count) {
                    let item = items[index]
                    let idx = index
                    index += 1
                    _ = idx  // suppress unused warning; index tracks insertion order, not used inside closure
                    group.addTask {
                        if Task.isCancelled { return false }
                        let processor = FrameProcessor()
                        let outURL = Self.outputURL(for: item, config: config, directory: directory, suffix: suffix)
                        do {
                            try await processor.process(input: item.url, output: outURL, config: config, rotation: item.rotation)
                            return true
                        } catch {
                            return false
                        }
                    }
                }

                // Drain results and feed remaining items one-for-one
                for await success in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    completed += 1
                    if !success { failedCount += 1 }

                    if let qIdx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                        exportQueue[qIdx].completedCount = completed
                        exportQueue[qIdx].progress = Double(completed) / Double(items.count)
                    }

                    if index < items.count {
                        let item = items[index]
                        index += 1
                        group.addTask {
                            if Task.isCancelled { return false }
                            let processor = FrameProcessor()
                            let outURL = Self.outputURL(for: item, config: config, directory: directory, suffix: suffix)
                            do {
                                try await processor.process(input: item.url, output: outURL, config: config, rotation: item.rotation)
                                return true
                            } catch {
                                return false
                            }
                        }
                    }
                }
            }

            if let qIdx = exportQueue.firstIndex(where: { $0.id == jobId }) {
                if Task.isCancelled {
                    exportQueue[qIdx].status = .cancelled
                } else {
                    exportQueue[qIdx].status = failedCount > 0
                        ? .failed("\(failedCount) of \(items.count) failed")
                        : .done
                }
            }
        }
        exportTasks[jobId] = task
    }

    nonisolated static func outputURL(for item: PhotoItem, config: ProcessingConfig, directory: URL, suffix: String) -> URL {
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

    // MARK: - Photo Removal

    /// Removes the given photos from the in-app library. Original files on
    /// disk are left untouched — this only clears them from the session.
    ///
    /// If the removal empties the current selection, a neighbouring photo is
    /// selected (the one that slid into the first removed slot, clamped to the
    /// new bounds) so the editor keeps showing a photo instead of dropping to
    /// the empty state.
    func removeItems(_ ids: Set<PhotoItem.ID>) {
        guard !ids.isEmpty else { return }
        let firstRemovedIndex = library.firstIndex { ids.contains($0.id) }
        let removedFromSelection = !selectedItems.isDisjoint(with: ids)
        library.removeAll { ids.contains($0.id) }
        selectedItems.subtract(ids)
        if removedFromSelection, selectedItems.isEmpty, let anchor = firstRemovedIndex, !library.isEmpty {
            let neighbour = min(anchor, library.count - 1)
            selectedItems = [library[neighbour].id]
        }
    }

    /// Removes every currently selected photo. See `removeItems(_:)`.
    func removeSelected() {
        removeItems(selectedItems)
    }

    /// Removes all photos from the library and clears the selection. Original
    /// files on disk are left untouched.
    func removeAllPhotos() {
        library.removeAll()
        selectedItems.removeAll()
    }

    func retryJob(_ job: ExportJob) {
        guard case .failed = job.status else { return }
        exportQueue.removeAll { $0.id == job.id }
        let suffix = job.label ?? Self.exportSuffix(presetName: activePresetName)
        exportItems(job.items, to: job.outputDirectory, config: job.config, suffix: suffix)
    }

    func cancelJob(_ job: ExportJob) {
        guard case .running = job.status else { return }
        exportTasks[job.id]?.cancel()
        exportTasks.removeValue(forKey: job.id)
        if let idx = exportQueue.firstIndex(where: { $0.id == job.id }) {
            exportQueue[idx].status = .cancelled
        }
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

    nonisolated static func recommendedExportConcurrency(
        itemCount: Int,
        cpuCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        guard itemCount > 0 else { return 1 }
        let available = max(1, cpuCount)
        let uiFriendlyCap = min(6, max(1, available - 1))
        return min(itemCount, uiFriendlyCap)
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
        case queued, running, done, cancelled, failed(String)
    }
}
