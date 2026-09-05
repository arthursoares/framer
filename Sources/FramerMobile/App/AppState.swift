import SwiftUI
import FramerCore

struct PresetOperationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum BottomTab {
    case presets
    case layers
}

@MainActor
@Observable
final class AppState {
    var library: [PhotoItem] = []
    var selectedIndex: Int = 0
    var currentConfig: ProcessingConfig = .default
    var activePresetName: String?
    var appliedPresetConfig: ProcessingConfig?
    var presets: [Preset] = []
    let presetStore: PresetStore
    var presetOperationAlert: PresetOperationAlert?
    private let fallbackEditorLayers = CompositionLayer.defaultLayers()

    // UI state
    var activeTab: BottomTab = .presets
    var showingSavePresetSheet = false
    var showingPhotosPicker = false

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
                message: "Framer couldn’t save “\(name)”. Check that Framer can access its presets, then try again."
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
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
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
            message: "Framer couldn’t export “\(preset.name)”. Try again."
        )
    }

    nonisolated static func safePresetFilename(for name: String) -> String {
        let sanitized = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return "\(sanitized.isEmpty ? "Preset" : sanitized).json"
    }

    private func validatePresetName(_ proposedName: String, excluding presetID: UUID? = nil) -> Bool {
        guard let problem = presetNameProblem(proposedName, excluding: presetID) else { return true }
        presetOperationAlert = PresetOperationAlert(title: "Choose Another Name", message: problem)
        return false
    }

    var selectedPhoto: PhotoItem? {
        guard library.indices.contains(selectedIndex) else { return nil }
        return library[selectedIndex]
    }

    var isPresetModified: Bool {
        guard activePresetName != nil, let applied = appliedPresetConfig else { return false }
        return currentConfig != applied
    }

    var editorLayers: [CompositionLayer] {
        get { currentConfig.layers ?? fallbackEditorLayers }
        set { currentConfig.layers = newValue }
    }

    // MARK: - Photo Management

    func addPhotos(_ items: [PhotoItem]) {
        let wasEmpty = library.isEmpty
        library.append(contentsOf: items)
        if wasEmpty && !items.isEmpty {
            selectedIndex = 0
        }
    }

    func rotateItem(_ id: PhotoItem.ID, clockwise: Bool) {
        guard let idx = library.firstIndex(where: { $0.id == id }) else { return }
        let delta = clockwise ? 90 : -90
        library[idx].rotation = (library[idx].rotation + delta + 360) % 360
    }
}

struct PhotoItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var rotation: Int = 0

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
