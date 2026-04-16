import SwiftUI
import FramerCore

struct PresetPreviewRenderKey: Equatable {
    let photoID: UUID?
    let photoRotation: Int?
    let presets: [Preset]
}

private enum PresetPreviewGridLayout {
    static let actionVerticalPadding = 7.0
    static let saveCardBorderDash: [CGFloat] = [4]
}

struct PresetPreviewGrid: View {
    @Environment(AppState.self) var appState
    @Environment(\.sidebarMetrics) private var metrics
    // Thumbnails live on AppState (see presetThumbnails / presetThumbnailsKey)
    // so collapsing + re-expanding the Presets section doesn't discard work.
    // A single Task? (not a dictionary keyed by fresh UUIDs) is sufficient —
    // only one batch is ever in flight, and cancel-before-replace prevents
    // the .onChange-plus-.onAppear race where the first task's handle was
    // leaked under a one-use key and could never be cancelled.
    @State private var renderTask: Task<Void, Never>?
    @State private var renamingPreset: Preset?
    @State private var renameText = ""

    private let maxConcurrentPresetRenders = 4

    private var columns: [GridItem] {
        let inset = metrics.expandedBodyInset
        return [
            GridItem(.flexible(), spacing: inset),
            GridItem(.flexible(), spacing: inset),
            GridItem(.flexible(), spacing: inset),
        ]
    }

    private var renderKey: PresetPreviewRenderKey {
        PresetPreviewRenderKey(
            photoID: appState.selectedPhoto?.id,
            photoRotation: appState.selectedPhoto?.rotation,
            presets: appState.presets
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            LazyVGrid(columns: columns, spacing: metrics.expandedBodyInset) {
                ForEach(appState.presets) { preset in
                    PresetPreviewCard(
                        preset: preset,
                        isActive: appState.activePresetName == preset.name,
                        thumbnail: appState.selectedPhoto != nil ? appState.presetThumbnailCache.thumbnail(for: preset.id) : nil,
                        onTap: {
                            appState.currentConfig = preset.config
                            appState.activePresetName = preset.name
                            appState.appliedPresetConfig = preset.config
                        }
                    )
                    .contextMenu {
                        Button {
                            appState.currentConfig = preset.config
                            appState.activePresetName = preset.name
                            appState.appliedPresetConfig = preset.config
                        } label: {
                            Label("Apply", systemImage: "checkmark.circle")
                        }
                        Button {
                            let updated = Preset(id: preset.id, name: preset.name, config: appState.currentConfig)
                            try? appState.presetStore.save(updated)
                            appState.loadPresets()
                            appState.activePresetName = preset.name
                            appState.appliedPresetConfig = appState.currentConfig
                        } label: {
                            Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            renameText = preset.name
                            renamingPreset = preset
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            exportPreset(preset)
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            try? appState.presetStore.delete(id: preset.id)
                            // Purge the thumbnail synchronously so a quick
                            // re-open of the Presets section doesn't briefly
                            // surface the dead entry before the renderKey
                            // change fires `schedulePreviewRenders` and
                            // invalidates the whole cache.
                            appState.presetThumbnailCache.remove(presetID: preset.id)
                            appState.loadPresets()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                saveCard
            }

            HStack(spacing: Spacing.sm) {
                supportActionButton("Import", systemImage: "square.and.arrow.down", action: importPresets)

                Spacer(minLength: metrics.expandedBodyInset)

                supportActionButton("Show in Finder", systemImage: "folder", action: showInFinder)
            }
        }

        .onChange(of: renderKey) { _, _ in
            schedulePreviewRenders()
        }
        .onAppear {
            schedulePreviewRenders()
        }
        .onDisappear {
            // Cancel in-flight work if the grid is torn down (section
            // collapse, window close, navigation). The @State Task would
            // otherwise keep running and write stale previews into
            // appState.presetThumbnailCache.thumbnails from the background actor context.
            renderTask?.cancel()
            renderTask = nil
        }
        .alert("Rename Preset", isPresented: Binding(
            get: { renamingPreset != nil },
            set: { if !$0 { renamingPreset = nil } }
        )) {
            TextField("Preset name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingPreset = nil }
            Button("Rename") {
                if let preset = renamingPreset, !renameText.isEmpty {
                    let updated = Preset(id: preset.id, name: renameText, config: preset.config)
                    try? appState.presetStore.save(updated)
                    if appState.activePresetName == preset.name {
                        appState.activePresetName = renameText
                    }
                    appState.loadPresets()
                }
                renamingPreset = nil
            }
        } message: {
            Text("Enter a new name for this preset.")
        }
    }

    private var saveCard: some View {
        Button(action: saveCurrentAsPreset) {
            let supportStyle = SidebarStateStyle.hover

            VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.surface3)

                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.text2)
                        Text("Save")
                            .font(AppFont.templateToken)
                            .foregroundStyle(Color.text1)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.borderDefault, lineWidth: 1)
                }

                HStack(spacing: Spacing.sm) {
                    Text("Save")
                        .font(AppFont.templateToken)
                        .foregroundStyle(Color.text1)

                    Spacer(minLength: 0)

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.text2)
                }
            }
            .padding(metrics.expandedBodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(supportStyle.backgroundColor, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .strokeBorder(
                        supportStyle.borderColor,
                        style: StrokeStyle(lineWidth: 1, dash: PresetPreviewGridLayout.saveCardBorderDash)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func supportActionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let supportStyle = SidebarStateStyle.hover

        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppFont.buttonText)
                .foregroundStyle(Color.text1)
                .padding(.horizontal, metrics.outerInset)
                .padding(.vertical, PresetPreviewGridLayout.actionVerticalPadding)
                .frame(maxWidth: .infinity)
                .background(supportStyle.backgroundColor, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(supportStyle.borderColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview Rendering

    /// Refreshes `appState.presetThumbnailCache.thumbnails` against the current render key.
    /// - If the key changed since the cache was last populated, all stale
    ///   thumbnails are dropped and every preset is re-rendered.
    /// - If the key matches (common case: user expanded/collapsed the Presets
    ///   section without changing photo or preset list), only presets with
    ///   missing thumbnails are rendered — the rest are served from cache.
    private func schedulePreviewRenders() {
        // Cancel any in-flight work. Either we're about to re-enqueue the
        // same set (key changed) or we're going to filter down to just the
        // missing ones below.
        renderTask?.cancel()
        renderTask = nil

        guard let photo = appState.selectedPhoto else { return }

        let presets = appState.presets
        let currentKey = renderKey

        if appState.presetThumbnailCache.key != currentKey {
            // Input changed (new photo, rotation, or preset list) — cache is
            // stale. Drop everything and rebuild under the new key.
            appState.presetThumbnailCache.resetKey(currentKey)
        }

        // Only render presets that don't already have a thumbnail cached.
        // This is what makes the section collapse/expand cheap: when the view
        // remounts with the same key, `missingPresets` is empty.
        let missingPresets = presets.filter { appState.presetThumbnailCache.thumbnail(for: $0.id) == nil }
        guard !missingPresets.isEmpty else { return }

        let url = photo.url
        let rotation = photo.rotation
        let compactPreviewMaxDimension = 320

        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            let processor = FrameProcessor()
            await withTaskGroup(of: Void.self) { group in
                var nextIndex = 0

                func enqueueNext() {
                    guard nextIndex < missingPresets.count else { return }
                    let preset = missingPresets[nextIndex]
                    nextIndex += 1

                    group.addTask {
                        guard !Task.isCancelled else { return }
                        do {
                            let cgImage = try await Task.detached {
                                try await processor.previewCGImage(
                                    for: url,
                                    config: preset.config,
                                    rotation: rotation,
                                    maxDimension: compactPreviewMaxDimension
                                )
                            }.value
                            guard !Task.isCancelled else { return }

                            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                            let preview = NSImage(cgImage: cgImage, size: NSSize(
                                width: CGFloat(cgImage.width) / scale,
                                height: CGFloat(cgImage.height) / scale
                            ))
                            await MainActor.run {
                                appState.presetThumbnailCache.store(preview, for: preset.id)
                            }
                        } catch {
                            // Silently fail — card shows placeholder
                        }
                    }
                }

                for _ in 0..<min(maxConcurrentPresetRenders, missingPresets.count) {
                    enqueueNext()
                }

                while await group.next() != nil {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    enqueueNext()
                }
            }
        }
    }

    // MARK: - Save Preset

    private func saveCurrentAsPreset() {
        let baseName = "Preset"
        let existingNames = Set(appState.presets.map(\.name))
        var name = baseName
        var counter = 1
        while existingNames.contains(name) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        let preset = Preset(name: name, config: appState.currentConfig)
        try? appState.presetStore.save(preset)
        appState.loadPresets()
        appState.activePresetName = preset.name
        appState.appliedPresetConfig = preset.config
    }

    // MARK: - Import / Export

    private func exportPreset(_ preset: Preset) {
        guard let data = try? appState.presetStore.exportData(for: preset) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).framerpreset"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Select .framerpreset or .json files to import"
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let data = try? Data(contentsOf: url) {
                    _ = try? appState.presetStore.importData(data)
                }
            }
            appState.loadPresets()
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.open(appState.presetStore.storageDirectory)
    }
}
