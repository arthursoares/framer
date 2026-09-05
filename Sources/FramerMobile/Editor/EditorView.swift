import SwiftUI
import PhotosUI
import ImageIO
import FramerCore

struct EditorOperationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum BatchShareCompletion {
    static func partialFailureAlert(
        exportedCount: Int,
        totalCount: Int,
        failedCount: Int
    ) -> EditorOperationAlert? {
        guard failedCount > 0 else { return nil }
        return EditorOperationAlert(
            title: "Some Photos Weren’t Prepared",
            message: "Prepared \(exportedCount) of \(totalCount) photos. \(failedCount) couldn’t be processed."
        )
    }

    @MainActor
    static func finish(
        temporaryFiles: [URL],
        feedback: EditorOperationAlert?,
        publish: (EditorOperationAlert) -> Void
    ) {
        for file in temporaryFiles {
            try? FileManager.default.removeItem(at: file)
        }
        if let feedback {
            publish(feedback)
        }
    }
}

struct EditorView: View {
    @Environment(AppState.self) var appState
    @Environment(\.undoManager) private var undoManager
    @State private var undoCoalescer = ConfigUndoCoalescer()
    @State private var viewModel = PreviewViewModel()
    @State private var presetCache = PresetPreviewCache()
    @State private var showingOriginal = false
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var photoImporter = PhotoImportCoordinator()
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportTotal: Int = 0
    @State private var operationAlert: EditorOperationAlert?

    private var layersBinding: Binding<[CompositionLayer]> {
        Binding(
            get: { appState.editorLayers },
            set: { appState.editorLayers = $0 }
        )
    }

    private var presetPreviewRenderKey: MobilePresetPreviewRenderKey {
        MobilePresetPreviewRenderKey(
            photoID: appState.selectedPhoto?.id,
            photoRotation: appState.selectedPhoto?.rotation,
            presets: appState.presets
        )
    }

    var body: some View {
        @Bindable var appState = appState

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
                    }
                }
            }
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .photosPicker(
            isPresented: $appState.showingPhotosPicker,
            selection: $selectedPickerItems,
            maxSelectionCount: 50,
            matching: .images
        )
        .overlay {
            if photoImporter.isLoading {
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
        }
        .onChange(of: appState.currentConfig) { old, new in
            updatePreview()
            // Single undo hook for every config edit (shake / three-finger
            // swipe / ⌘Z on iPad) — see ConfigUndoCoalescer.
            undoCoalescer.configChanged(
                from: old,
                to: new,
                undoManager: undoManager,
                current: { appState.currentConfig },
                restore: { appState.currentConfig = $0 }
            )
        }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in updatePreview() }
        .onChange(of: appState.library.count) { _, _ in
            updatePreview()
        }
        .onChange(of: presetPreviewRenderKey) { _, _ in
            regeneratePresetPreviews()
        }
        .onAppear {
            updatePreview()
            regeneratePresetPreviews()
        }
        .onDisappear {
            photoImporter.cancel()
        }
        .alert(item: $operationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
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
        photoImporter.start {
            var newItems: [PhotoItem] = []
            var temporaryURLs: [URL] = []
            var failureCount = 0
            for item in items {
                guard !Task.isCancelled else { break }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        failureCount += 1
                        continue
                    }
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    try data.write(to: tempURL, options: .atomic)
                    temporaryURLs.append(tempURL)
                    newItems.append(PhotoItem(url: tempURL))
                } catch {
                    failureCount += 1
                }
            }
            return PhotoImportResult(
                items: newItems,
                temporaryURLs: temporaryURLs,
                failureCount: failureCount
            )
        } onComplete: { newItems in
            appState.addPhotos(newItems)
        } clearSelection: {
            selectedPickerItems.removeAll()
        } onFeedback: { result in
            if let message = PhotoImportCoordinator.feedbackMessage(for: result) {
                operationAlert = EditorOperationAlert(title: "Photos", message: message)
            }
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
            var exportedFiles: [URL] = []
            var failedCount = 0
            var completedCount = 0
            let maxConcurrency = Self.shareAllConcurrency(itemCount: items.count)

            await withTaskGroup(of: URL?.self) { group in
                var nextIndex = 0

                func enqueue() {
                    guard nextIndex < items.count else { return }
                    let item = items[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let processor = FrameProcessor()
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(config.outputFormat == .png ? "png" : "jpg")
                        do {
                            try await processor.process(input: item.url, output: tempURL, config: config, rotation: item.rotation)
                            return tempURL
                        } catch {
                            return nil
                        }
                    }
                }

                for _ in 0..<maxConcurrency {
                    enqueue()
                }

                while let result = await group.next() {
                    completedCount += 1
                    exportProgress = Double(completedCount)
                    if let url = result {
                        exportedFiles.append(url)
                    } else {
                        failedCount += 1
                    }
                    enqueue()
                }
            }

            guard !exportedFiles.isEmpty else {
                operationAlert = EditorOperationAlert(
                    title: "Photos Not Shared",
                    message: "Framer couldn’t prepare any photos for sharing."
                )
                return
            }
            let completionFeedback = BatchShareCompletion.partialFailureAlert(
                exportedCount: exportedFiles.count,
                totalCount: items.count,
                failedCount: failedCount
            )
            // Share all processed images
            let activityVC = UIActivityViewController(activityItems: exportedFiles, applicationActivities: nil)
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                Task { @MainActor in
                    BatchShareCompletion.finish(
                        temporaryFiles: exportedFiles,
                        feedback: completionFeedback
                    ) { operationAlert = $0 }
                }
            }
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                BatchShareCompletion.finish(temporaryFiles: exportedFiles, feedback: nil) { _ in }
                operationAlert = EditorOperationAlert(
                    title: "Photos Not Shared",
                    message: "Framer couldn’t open the share sheet. Try again."
                )
                return
            }
            var presenter = rootVC
            while let presented = presenter.presentedViewController { presenter = presented }
            activityVC.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activityVC, animated: true)
        }
    }

    private nonisolated static func shareAllConcurrency(itemCount: Int) -> Int {
        guard itemCount > 0 else { return 1 }
        return min(2, itemCount)
    }

    private func shareImage() {
        guard let image = viewModel.previewImage else { return }
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            operationAlert = EditorOperationAlert(
                title: "Photo Not Shared",
                message: "Framer couldn’t open the share sheet. Try again."
            )
            return
        }
        // Find the topmost presented VC
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }
}

struct PhotoImportResult: Sendable {
    let items: [PhotoItem]
    let temporaryURLs: [URL]
    let failureCount: Int

    init(items: [PhotoItem], temporaryURLs: [URL], failureCount: Int = 0) {
        self.items = items
        self.temporaryURLs = temporaryURLs
        self.failureCount = failureCount
    }
}

@MainActor
@Observable
final class PhotoImportCoordinator {
    private(set) var isLoading = false
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    @discardableResult
    func start(
        operation: @escaping @MainActor () async -> PhotoImportResult,
        onComplete: @escaping @MainActor ([PhotoItem]) -> Void,
        clearSelection: @escaping @MainActor () -> Void,
        onFeedback: @escaping @MainActor (PhotoImportResult) -> Void = { _ in }
    ) -> Task<Void, Never> {
        task?.cancel()
        generation &+= 1
        let requestGeneration = generation
        isLoading = true

        let newTask = Task {
            let result = await operation()
            guard !Task.isCancelled, requestGeneration == generation else {
                Self.removeTemporaryFiles(result.temporaryURLs)
                return
            }

            onComplete(result.items)
            clearSelection()
            onFeedback(result)
            finish(requestGeneration)
        }
        task = newTask
        return newTask
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        isLoading = false
    }

    private func finish(_ requestGeneration: UInt64) {
        guard requestGeneration == generation else { return }
        task = nil
        isLoading = false
    }

    nonisolated static func feedbackMessage(for result: PhotoImportResult) -> String? {
        guard result.failureCount > 0 else { return nil }
        let failed = result.failureCount
        let failedDescription = "\(failed) \(failed == 1 ? "photo couldn’t" : "photos couldn’t") be loaded."
        if result.items.isEmpty {
            return "No photos were added. \(failedDescription)"
        }
        let added = result.items.count
        return "Added \(added) \(added == 1 ? "photo" : "photos"). \(failedDescription)"
    }

    private nonisolated static func removeTemporaryFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
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
