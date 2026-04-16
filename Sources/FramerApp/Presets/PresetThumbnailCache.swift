import SwiftUI
import FramerCore

/// In-memory cache of preset-preview thumbnails. Lives on `AppState` as a
/// dedicated `@Observable` type so thumbnail writes only invalidate views
/// that actually read the cache — previously `presetThumbnails` was a `var`
/// directly on `AppState`, and every thumbnail write during a background
/// render batch invalidated every view tracking any AppState property
/// (ExportBar, CanvasView, the Inspector output section, etc).
///
/// The cache is keyed by preset ID, with a separate `key: PresetPreviewRenderKey?`
/// tracking the input snapshot (selected photo + rotation + preset list)
/// that produced the current entries. When that input changes,
/// `PresetPreviewGrid` compares keys and invalidates.
@MainActor
@Observable
final class PresetThumbnailCache {
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var key: PresetPreviewRenderKey?

    func store(_ image: NSImage, for presetID: UUID) {
        thumbnails[presetID] = image
    }

    func thumbnail(for presetID: UUID) -> NSImage? {
        thumbnails[presetID]
    }

    /// Drop the thumbnail for a specific preset (e.g. after a Delete action).
    func remove(presetID: UUID) {
        thumbnails.removeValue(forKey: presetID)
    }

    /// Drop every thumbnail and adopt a new render key. Call when the
    /// render input changes (new photo, rotation, preset list) so stale
    /// previews don't survive a re-render cycle.
    func resetKey(_ newKey: PresetPreviewRenderKey) {
        thumbnails.removeAll()
        key = newKey
    }
}
