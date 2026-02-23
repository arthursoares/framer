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
