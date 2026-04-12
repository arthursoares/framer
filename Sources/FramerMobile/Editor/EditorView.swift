import SwiftUI
import PhotosUI
import ImageIO
import FramerCore

struct EditorView: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @State private var presetCache = PresetPreviewCache()
    @State private var showingOriginal = false
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportTotal: Int = 0
    @State private var loadPhotosTask: Task<Void, Never>?
    @State private var exportStatusMessage: String?

    private var layersBinding: Binding<[CompositionLayer]> {
        Binding(
            get: { appState.currentConfig.layers ?? CompositionLayer.defaultLayers() },
            set: { appState.currentConfig.layers = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview area
                PreviewArea(
                    viewModel: viewModel,
                    showingOriginal: $showingOriginal
                )

                // Photo filmstrip (when photos loaded)
                if !appState.library.isEmpty {
                    photoFilmstrip
                }

                // Bottom panel
                BottomPanel(presetCache: presetCache)
            }
            .background(Color.surface0)
            .navigationDestination(for: UUID.self) { layerID in
                if let index = layersBinding.wrappedValue.firstIndex(where: { $0.id == layerID }) {
                    LayerDetailView(layer: Binding(
                        get: {
                            guard layersBinding.wrappedValue.indices.contains(index),
                                  layersBinding.wrappedValue[index].id == layerID else {
                                return layersBinding.wrappedValue.first { $0.id == layerID } ?? .border(BorderLayerParams())
                            }
                            return layersBinding.wrappedValue[index]
                        },
                        set: {
                            if let i = layersBinding.wrappedValue.firstIndex(where: { $0.id == layerID }) {
                                layersBinding.wrappedValue[i] = $0
                            }
                        }
                    ), onDelete: {
                        if let i = layersBinding.wrappedValue.firstIndex(where: { $0.id == layerID }) {
                            layersBinding.wrappedValue.remove(at: i)
                        }
                    })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(appState.selectedPhoto?.url.deletingPathExtension().lastPathComponent ?? "Framer")
                        .font(AppFont.body(14, weight: .medium))
                        .foregroundStyle(Color.text0)
                }
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker(
                        selection: $selectedPickerItems,
                        maxSelectionCount: 50,
                        matching: .images
                    ) {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(Color.accent)
                    }
                    .accessibilityLabel("Add Photos")
                    .accessibilityIdentifier("toolbar.addPhotos")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if appState.selectedPhoto != nil {
                        Button {
                            if let photo = appState.selectedPhoto {
                                appState.rotateItem(photo.id, clockwise: true)
                            }
                        } label: {
                            Image(systemName: "rotate.right")
                                .foregroundStyle(Color.text2)
                        }
                        .accessibilityLabel("Rotate Clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.previewImage != nil {
                        Menu {
                            Button {
                                shareImage()
                            } label: {
                                Label("Share Current", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                shareAllProcessed()
                            } label: {
                                Label("Share All Processed", systemImage: "photo.on.rectangle.angled")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.accent)
                        }
                        .accessibilityLabel("Share")
                        .accessibilityIdentifier("toolbar.share")
                    }
                }
            }
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .overlay {
            if isLoadingPhotos {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView("Loading photos...")
                            .tint(Color.accent)
                            .padding(24)
                            .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                    }
            }
            if isExporting {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView(value: exportProgress, total: Double(exportTotal))
                                .tint(Color.accent)
                                .frame(width: 200)
                            Text("Exporting \(Int(exportProgress))/\(exportTotal)...")
                                .font(AppFont.body(13))
                                .foregroundStyle(Color.text1)
                        }
                        .padding(24)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                    }
            }
        }
        .onChange(of: selectedPickerItems) { _, items in
            guard !items.isEmpty else {
                selectedPickerItems.removeAll()
                return
            }
            loadPhotos(from: items)
        }
        .onChange(of: showingOriginal) { _, isShowingOriginal in
            if isShowingOriginal {
                viewModel.loadOriginalIfNeeded(for: appState.selectedPhoto)
            }
        }
        .onChange(of: appState.selectedIndex) { _, _ in
            showingOriginal = false
            updatePreview()
            regeneratePresetPreviews()
        }
        .onChange(of: appState.currentConfig) { _, _ in updatePreview() }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in updatePreview() }
        .onChange(of: appState.library.count) { _, _ in
            updatePreview()
            regeneratePresetPreviews()
        }
        .onAppear {
            updatePreview()
            regeneratePresetPreviews()
        }
        .onDisappear {
            loadPhotosTask?.cancel()
        }
        .alert(
            "Export",
            isPresented: Binding(
                get: { exportStatusMessage != nil },
                set: { if !$0 { exportStatusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportStatusMessage ?? "")
        }
    }

    // MARK: - Photo Filmstrip

    private var photoFilmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(appState.library.enumerated()), id: \.element.id) { index, item in
                    Button {
                        appState.selectedIndex = index
                    } label: {
                        ZStack {
                            Color.surface3
                            AsyncThumbnail(url: item.url)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(index == appState.selectedIndex ? Color.accent : .clear, lineWidth: 1.5)
                        )
                        .opacity(index == appState.selectedIndex ? 1.0 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1)")
                    .accessibilityHint("Select photo")
                    .accessibilityValue(index == appState.selectedIndex ? "Selected" : "")
                    .contextMenu {
                        Button {
                            appState.rotateItem(item.id, clockwise: true)
                        } label: {
                            Label("Rotate Right", systemImage: "rotate.right")
                        }
                        Button {
                            appState.rotateItem(item.id, clockwise: false)
                        } label: {
                            Label("Rotate Left", systemImage: "rotate.left")
                        }
                        Divider()
                        Button(role: .destructive) {
                            withAnimation {
                                let removedIndex = appState.library.firstIndex(where: { $0.id == item.id })
                                appState.library.removeAll { $0.id == item.id }
                                if let removedIndex {
                                    if removedIndex < appState.selectedIndex {
                                        appState.selectedIndex -= 1
                                    } else if removedIndex == appState.selectedIndex {
                                        appState.selectedIndex = min(appState.selectedIndex, max(0, appState.library.count - 1))
                                    }
                                }
                                if appState.selectedIndex >= appState.library.count {
                                    appState.selectedIndex = max(0, appState.library.count - 1)
                                }
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background {
            Color.surface1
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.borderDefault).frame(height: 1)
                }
        }
    }

    // MARK: - Actions

    private func updatePreview() {
        viewModel.updatePreview(
            for: appState.selectedPhoto,
            config: appState.currentConfig,
            includeOriginal: showingOriginal
        )
    }

    private func regeneratePresetPreviews() {
        guard let photo = appState.selectedPhoto else {
            presetCache.clear()
            return
        }
        presetCache.regenerate(for: photo, presets: appState.presets)
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        loadPhotosTask?.cancel()
        isLoadingPhotos = true
        loadPhotosTask = Task {
            defer {
                isLoadingPhotos = false
                loadPhotosTask = nil
            }
            var newItems: [PhotoItem] = []
            for item in items {
                guard !Task.isCancelled else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    do {
                        try data.write(to: tempURL)
                        newItems.append(PhotoItem(url: tempURL))
                    } catch {
                        // skip this item
                    }
                }
            }
            guard !Task.isCancelled else { return }
            appState.addPhotos(newItems)
            selectedPickerItems.removeAll()
        }
    }

    private func shareAllProcessed() {
        guard !appState.library.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        exportTotal = appState.library.count
        let items = appState.library
        let config = appState.currentConfig

        Task {
            defer { isExporting = false }
            let exporter = ProcessedImageExporter()
            let exportedFiles: [URL]

            do {
                exportedFiles = try await exporter.exportAllProcessed(
                    items: items,
                    config: config,
                    exportDirectory: appState.e2eExportDirectory
                )
                exportProgress = Double(exportedFiles.count)
            } catch {
                exportStatusMessage = "Could not process any photos for sharing."
                return
            }

            guard !exportedFiles.isEmpty else {
                exportStatusMessage = "Could not process any photos for sharing."
                return
            }

            if appState.isRunningE2ETests {
                exportStatusMessage = "Exported \(exportedFiles.count) files"
                return
            }

            let activityVC = UIActivityViewController(activityItems: exportedFiles, applicationActivities: nil)
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                for file in exportedFiles {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                for file in exportedFiles {
                    try? FileManager.default.removeItem(at: file)
                }
                exportStatusMessage = "Unable to present share sheet."
                return
            }
            var presenter = rootVC
            while let presented = presenter.presentedViewController { presenter = presented }
            activityVC.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activityVC, animated: true)
        }
    }

    private func shareImage() {
        guard let image = viewModel.previewImage else { return }
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        // Find the topmost presented VC
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }
}

// MARK: - Async Thumbnail (simplified for iOS)

struct AsyncThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.surface3
            }
        }
        .task(id: url) {
            image = await Self.loadThumbnail(from: url)
        }
    }

    private nonisolated static func loadThumbnail(from url: URL) async -> UIImage? {
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            return cached
        }

        return await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: 200
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            let image = UIImage(cgImage: cgImage)
            thumbnailCache.setObject(image, forKey: url as NSURL)
            return image
        }.value
    }

    private nonisolated(unsafe) static let thumbnailCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 500
        return cache
    }()
}
