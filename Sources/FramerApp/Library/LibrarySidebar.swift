import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct LibrarySidebar: View {
    @Environment(AppState.self) var appState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Selectable photo list — standalone, no other sections
            List(selection: Binding(
                get: { appState.selectedItems },
                set: { appState.selectedItems = $0 }
            )) {
                ForEach(appState.library) { item in
                    PhotoThumbnailView(item: item)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if appState.library.isEmpty {
                    emptyState
                }
            }

            Divider()

            // Presets & Queue — plain ScrollView, no List selection interference
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarPresetsSection()
                    SidebarQueueSection()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(minHeight: 100, maxHeight: 220)
        }
        .navigationTitle("Framer")
        .toolbar {
            ToolbarItemGroup {
                if !appState.selectedItems.isEmpty {
                    Button(action: removeSelected) {
                        Label("Remove Selected", systemImage: "minus")
                    }
                    .help("Remove selected photos from library")
                }
                Button(action: openFilePicker) {
                    Label("Add Photos", systemImage: "plus")
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(4)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerOpenPhotos)) { _ in
            openFilePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerSelectAll)) { _ in
            appState.selectedItems = Set(appState.library.map(\.id))
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerDeleteSelected)) { _ in
            removeSelected()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop photos here or click +")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK {
            appState.addPhotos(from: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        appState.addPhotos(from: [url])
                    }
                }
            }
        }
        return true
    }

    private func removeSelected() {
        withAnimation {
            appState.library.removeAll { appState.selectedItems.contains($0.id) }
            appState.selectedItems.removeAll()
        }
    }
}

// MARK: - Sidebar Presets Section

struct SidebarPresetsSection: View {
    @Environment(AppState.self) var appState
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""
    @State private var presetToDelete: Preset?
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup("Presets", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                if appState.presets.isEmpty {
                    Text("No presets yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.presets) { preset in
                        presetRow(preset)
                    }
                }

                Button(action: { showingSaveSheet = true }) {
                    Label("Save Current Settings", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .sheet(isPresented: $showingSaveSheet) {
            savePresetSheet
        }
        .alert("Delete Preset?", isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { presetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    try? appState.presetStore.delete(id: preset.id)
                    appState.loadPresets()
                    presetToDelete = nil
                }
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete \"\(preset.name)\"?")
            }
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        Button {
            appState.currentConfig = preset.config
            appState.activePresetName = preset.name
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                Text(preset.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if appState.activePresetName == preset.name {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                appState.activePresetName == preset.name
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                appState.currentConfig = preset.config
                appState.activePresetName = preset.name
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
            }
            Button {
                let updated = Preset(id: preset.id, name: preset.name, config: appState.currentConfig)
                try? appState.presetStore.save(updated)
                appState.loadPresets()
                appState.activePresetName = preset.name
            } label: {
                Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive) {
                presetToDelete = preset
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(.headline)

            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack {
                Button("Cancel") {
                    newPresetName = ""
                    showingSaveSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let name = newPresetName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let preset = Preset(name: name, config: appState.currentConfig)
                    try? appState.presetStore.save(preset)
                    appState.loadPresets()
                    newPresetName = ""
                    showingSaveSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }
}

// MARK: - Sidebar Queue Section

struct SidebarQueueSection: View {
    @Environment(AppState.self) var appState
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup("Export Queue", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                if appState.exportQueue.isEmpty {
                    Text("No exports yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.exportQueue) { job in
                        sidebarJobRow(job)
                    }

                    if hasCompleted {
                        Button(action: clearCompleted) {
                            Label("Clear Completed", systemImage: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private func sidebarJobRow(_ job: ExportJob) -> some View {
        HStack(spacing: 6) {
            statusIcon(job.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(job.items.count) photo\(job.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    if let label = job.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                    .lineLimit(1)
                if job.status == .running {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                }
            }
            Spacer()
            if job.status == .done {
                Button {
                    NSWorkspace.shared.open(job.outputDirectory)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reveal in Finder")
            }
            if case .failed = job.status {
                Button {
                    appState.retryJob(job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Retry")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIcon(_ status: ExportJob.JobStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private var hasCompleted: Bool {
        appState.exportQueue.contains { $0.status == .done }
    }

    private func clearCompleted() {
        appState.exportQueue.removeAll { $0.status == .done }
    }
}
