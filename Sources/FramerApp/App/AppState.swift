import SwiftUI
import FramerCore

struct PresetOperationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

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
    let presetStore: PresetStore
    var presetOperationAlert: PresetOperationAlert?
    var exportQueue: [ExportJob] = []
    private var exportTasks: [UUID: Task<Void, Never>] = [:]

    /// Cached preset-preview thumbnails. A separate `@Observable` instance so
    /// writes during a background render batch invalidate only views that
    /// actually read the cache (the Presets grid), not every view tracking
    /// AppState properties generally.
    let presetThumbnailCache = PresetThumbnailCache()


    init(presetStore: PresetStore = PresetStore(), initializeDefaults: Bool = true) {
        self.presetStore = presetStore
        if initializeDefaults {
            presetStore.initializeDefaults()
        }
        _ = loadPresets()
    }

    @discardableResult
    func loadPresets(reportFailure: Bool = false) -> Bool {
        do {
            presets = try presetStore.list()
            return true
        } catch {
            if reportFailure {
                presetOperationAlert = PresetOperationAlert(
                    title: "Presets Unavailable",
                    message: "Framer couldn’t refresh your presets. Try again."
                )
            }
            return false
        }
    }

    func presetNameProblem(_ proposedName: String, excluding presetID: UUID? = nil) -> String? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a preset name." }
        if let duplicate = presets.first(where: {
            $0.id != presetID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return "A preset named “\(duplicate.name)” already exists."
        }
        return nil
    }

    @discardableResult
    func saveCurrentPreset(named proposedName: String) -> Bool {
        guard validatePresetName(proposedName) else { return false }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(name: name, config: currentConfig)
        do {
            try presetStore.save(preset)
            presets = try presetStore.list()
            activePresetName = preset.name
            appliedPresetConfig = preset.config
            return true
        } catch {
            presetOperationAlert = PresetOperationAlert(
                title: "Preset Not Saved",
                message: "Framer couldn’t save “\(name)”. Check that the presets folder is available, then try again."
            )
            return false
        }
    }

    @discardableResult
    func updatePreset(_ preset: Preset) -> Bool {
        let updated = Preset(id: preset.id, name: preset.name, config: currentConfig)
        do {
            try presetStore.save(updated)
            presets = try presetStore.list()
            activePresetName = updated.name
            appliedPresetConfig = updated.config
            return true
        } catch {
            presetOperationAlert = PresetOperationAlert(
                title: "Preset Not Updated",
                message: "Framer couldn’t update “\(preset.name)”. Your saved preset was left unchanged."
            )
            return false
        }
    }

    @discardableResult
    func renamePreset(_ preset: Preset, to proposedName: String) -> Bool {
        guard validatePresetName(proposedName, excluding: preset.id) else { return false }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Preset(id: preset.id, name: name, config: preset.config)
        do {
            try presetStore.save(updated)
            presets = try presetStore.list()
            if activePresetName == preset.name {
                activePresetName = name
            }
            return true
        } catch {
            presetOperationAlert = PresetOperationAlert(
                title: "Preset Not Renamed",
                message: "Framer couldn’t rename “\(preset.name)”. Its original name is unchanged."
            )
            return false
        }
    }

    @discardableResult
    func deletePreset(_ preset: Preset) -> Bool {
        do {
            try presetStore.delete(id: preset.id)
            presets = try presetStore.list()
            if activePresetName == preset.name {
                activePresetName = nil
                appliedPresetConfig = nil
            }
            return true
        } catch {
            presetOperationAlert = PresetOperationAlert(
                title: "Preset Not Deleted",
                message: "Framer couldn’t delete “\(preset.name)”. It remains in your presets."
            )
            return false
        }
    }

    func importPresets(from urls: [URL]) {
        var importedCount = 0
        var failedPresetCount = 0
        var failedFileCount = 0
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let decodedPresets = try presetStore.decodeImportData(data)
                for preset in decodedPresets {
                    do {
                        try presetStore.save(preset)
                        importedCount += 1
                    } catch {
                        failedPresetCount += 1
                    }
                }
            } catch {
                failedFileCount += 1
            }
        }

        if importedCount > 0 {
            guard loadPresets(reportFailure: true) else { return }
        }
        if failedPresetCount > 0 || failedFileCount > 0 {
            let title = importedCount > 0 ? "Some Presets Weren’t Imported" : "Presets Not Imported"
            let message: String
            if importedCount > 0 {
                message = "Imported \(importedCount) \(importedCount == 1 ? "preset" : "presets"). \(Self.importFailureDescription(failedPresets: failedPresetCount, failedFiles: failedFileCount))"
            } else if failedPresetCount == 0, failedFileCount == 1 {
                message = "The selected file couldn’t be imported."
            } else if failedPresetCount == 1, failedFileCount == 0 {
                message = "The preset couldn’t be imported."
            } else {
                message = "No presets were imported. \(Self.importFailureDescription(failedPresets: failedPresetCount, failedFiles: failedFileCount))"
            }
            presetOperationAlert = PresetOperationAlert(title: title, message: message)
        }
    }

    private static func importFailureDescription(failedPresets: Int, failedFiles: Int) -> String {
        let presetPart = "\(failedPresets) \(failedPresets == 1 ? "preset" : "presets")"
        let filePart = "\(failedFiles) \(failedFiles == 1 ? "file" : "files")"
        if failedPresets > 0, failedFiles > 0 {
            return "\(presetPart) and \(filePart) couldn’t be imported."
        }
        return "\(failedPresets > 0 ? presetPart : filePart) couldn’t be imported."
    }

    func presetExportData(_ preset: Preset) -> Data? {
        do {
            return try presetStore.exportData(for: preset)
        } catch {
            reportPresetExportFailure(for: preset)
            return nil
        }
    }

    func reportPresetExportFailure(for preset: Preset) {
        presetOperationAlert = PresetOperationAlert(
            title: "Preset Not Exported",
            message: "Framer couldn’t export “\(preset.name)”. Choose another location and try again."
        )
    }

    private func validatePresetName(_ proposedName: String, excluding presetID: UUID? = nil) -> Bool {
        guard let problem = presetNameProblem(proposedName, excluding: presetID) else { return true }
        presetOperationAlert = PresetOperationAlert(title: "Choose Another Name", message: problem)
        return false
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
