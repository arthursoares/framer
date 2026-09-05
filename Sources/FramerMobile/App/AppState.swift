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
    private let fallbackEditorLayers = CompositionLayer.defaultLayers()

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
