import SwiftUI
import UniformTypeIdentifiers

struct LibrarySidebar: View {
    @Environment(AppState.self) var appState
    @State private var isTargeted = false

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedItems },
            set: { appState.selectedItems = $0 }
        )) {
            if appState.library.isEmpty {
                emptyState
            } else {
                ForEach(appState.library) { item in
                    PhotoThumbnailView(item: item)
                        .tag(item.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
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
        .safeAreaInset(edge: .bottom) {
            libraryStatusBar
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
    }

    @ViewBuilder
    private var libraryStatusBar: some View {
        if !appState.library.isEmpty {
            HStack {
                Text("\(appState.library.count) photo\(appState.library.count == 1 ? "" : "s")")
                if !appState.selectedItems.isEmpty {
                    Text("\(appState.selectedItems.count) selected")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.regularMaterial)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drop photos here")
                .foregroundStyle(.secondary)
            Text("or click + to add")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        addURLs([url])
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

    private func addURLs(_ urls: [URL]) {
        let imageExts = Set(["jpg", "jpeg", "png", "tiff", "tif", "heic"])
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
        let existing = Set(appState.library.map(\.url))
        let newItems = allFiles
            .filter { !existing.contains($0) }
            .map { PhotoItem(url: $0) }
        appState.library.append(contentsOf: newItems)
    }
}
