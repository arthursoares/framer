import SwiftUI
import FramerCore

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
    var presetStore = PresetStore()
    var e2eExportDirectory: URL?
    var isRunningE2ETests = false

    // UI state
    var activeTab: BottomTab = .presets
    var showingSavePresetSheet = false
    var showingPhotosPicker = false

    init() {
        presetStore.initializeDefaults()
        loadPresets()
    }

    func loadPresets() {
        presets = (try? presetStore.list()) ?? []
    }

    func applyE2ETestConfiguration(_ config: AppE2ETestConfiguration) {
        isRunningE2ETests = true
        e2eExportDirectory = config.exportDirectory

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: config.fixturesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let imageURLs = urls
            .filter { ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if !imageURLs.isEmpty {
            library = imageURLs.map { PhotoItem(url: $0) }
            selectedIndex = 0
        }

        if let presetName = config.presetName,
           let preset = presets.first(where: { $0.name == presetName }) {
            activePresetName = preset.name
            currentConfig = preset.config
            appliedPresetConfig = preset.config
        }
    }

    var selectedPhoto: PhotoItem? {
        guard library.indices.contains(selectedIndex) else { return nil }
        return library[selectedIndex]
    }

    var isPresetModified: Bool {
        guard activePresetName != nil, let applied = appliedPresetConfig else { return false }
        return currentConfig != applied
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
