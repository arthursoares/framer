import SwiftUI
import PhotosUI
import FramerCore

struct EditorView: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @State private var presetCache = PresetPreviewCache()
    @State private var showingOriginal = false
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview area
                PreviewArea(
                    viewModel: viewModel,
                    showingOriginal: $showingOriginal,
                    photoCount: appState.library.count,
                    currentIndex: appState.selectedIndex
                )

                // Photo filmstrip (when photos loaded)
                if !appState.library.isEmpty {
                    photoFilmstrip
                }

                // Bottom panel
                BottomPanel(presetCache: presetCache)
            }
            .background(Color.surface0)
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.previewImage != nil {
                        Button(action: shareImage) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.accent)
                        }
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
        }
        .onChange(of: selectedPickerItems) { _, items in
            guard !items.isEmpty else { return }
            loadPhotos(from: items)
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
    }

    // MARK: - Photo Filmstrip

    private var photoFilmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(appState.library.enumerated()), id: \.element.id) { index, item in
                    AsyncThumbnail(url: item.url)
                        .frame(width: 44, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(index == appState.selectedIndex ? Color.accent : .clear, lineWidth: 1.5)
                        )
                        .opacity(index == appState.selectedIndex ? 1.0 : 0.55)
                        .onTapGesture {
                            appState.selectedIndex = index
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
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
    }

    private func regeneratePresetPreviews() {
        guard let photo = appState.selectedPhoto else { return }
        presetCache.regenerate(for: photo, presets: appState.presets)
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        isLoadingPhotos = true
        Task {
            var newItems: [PhotoItem] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    try? data.write(to: tempURL)
                    newItems.append(PhotoItem(url: tempURL))
                }
            }
            appState.addPhotos(newItems)
            selectedPickerItems.removeAll()
            isLoadingPhotos = false
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
        guard let data = try? Data(contentsOf: url),
              let full = UIImage(data: data) else { return nil }
        let maxDim: CGFloat = 100
        let scale = min(maxDim / full.size.width, maxDim / full.size.height, 1.0)
        let size = CGSize(width: full.size.width * scale, height: full.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in full.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
