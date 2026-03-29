import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @State private var showOriginal = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Viewport
            ZStack {
                // Dark background with warm radial gradient
                Color.surface0
                RadialGradient(
                    colors: [Color.accent.opacity(0.02), .clear],
                    center: UnitPoint(x: 0.5, y: 0.4),
                    startRadius: 0,
                    endRadius: 400
                )

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.text2)
                } else if let img = showOriginal ? viewModel.originalImage : viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(32)
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.text3)
                        Text("No photo selected")
                            .font(AppFont.body(16, weight: .medium))
                            .foregroundStyle(Color.text2)
                        Text("Select a photo from the filmstrip,\nor drag images here")
                            .font(AppFont.body(13))
                            .foregroundStyle(Color.text3)
                            .multilineTextAlignment(.center)
                    }
                }

                // Error display
                if let err = viewModel.error {
                    VStack {
                        Spacer()
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(AppFont.body(11))
                            .foregroundStyle(Color.error)
                            .padding(8)
                            .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                            .padding()
                    }
                }

                // Before/After toggle — top-left
                if viewModel.previewImage != nil {
                    VStack {
                        HStack {
                            BeforeAfterToggle(showOriginal: $showOriginal)
                                .padding(.leading, 16)
                                .padding(.top, 16)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Drop target overlay
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(Color.accentDim, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Color.accentGlow, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                        .padding(12)
                }

                // Floating filmstrip
                if !appState.library.isEmpty {
                    VStack {
                        Spacer()
                        FilmstripView()
                            .padding(.leading, 14)
                            .padding(.trailing, 294)
                            .padding(.bottom, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            // EXIF bar
            if let exif = viewModel.exifData {
                ExifInfoBar(exif: exif, config: appState.currentConfig)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        Color.surface1
                            .overlay(alignment: .top) {
                                Rectangle().fill(Color.borderDefault).frame(height: 1)
                            }
                    }
            }
        }
        .onChange(of: appState.selectedItems) { _, _ in
            showOriginal = false
            updatePreview()
        }
        .onChange(of: appState.currentConfig) { _, _ in updatePreview() }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in updatePreview() }
        .onAppear { updatePreview() }
        .onReceive(NotificationCenter.default.publisher(for: .framerOpenPhotos)) { _ in
            openFilePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerSelectAll)) { _ in
            appState.selectedItems = Set(appState.library.map(\.id))
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerDeleteSelected)) { _ in
            removeSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerRotateCW)) { _ in
            for id in appState.selectedItems { appState.rotateItem(id, clockwise: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerRotateCCW)) { _ in
            for id in appState.selectedItems { appState.rotateItem(id, clockwise: false) }
        }
        .onKeyPress(.space) {
            showOriginal.toggle()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigateFilmstrip(forward: false)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateFilmstrip(forward: true)
            return .handled
        }
        .focusable()
    }

    private func updatePreview() {
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
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

    private func navigateFilmstrip(forward: Bool) {
        guard !appState.library.isEmpty else { return }
        let currentID = appState.selectedItems.first
        let currentIndex = currentID.flatMap { id in appState.library.firstIndex(where: { $0.id == id }) }
        let nextIndex: Int
        if let idx = currentIndex {
            nextIndex = forward
                ? min(idx + 1, appState.library.count - 1)
                : max(idx - 1, 0)
        } else {
            nextIndex = 0
        }
        appState.selectedItems = [appState.library[nextIndex].id]
    }

    private func removeSelected() {
        withAnimation {
            appState.library.removeAll { appState.selectedItems.contains($0.id) }
            appState.selectedItems.removeAll()
        }
    }
}

// MARK: - Before/After Toggle

struct BeforeAfterToggle: View {
    @Binding var showOriginal: Bool

    var body: some View {
        HStack(spacing: 0) {
            toggleButton("Before", isActive: showOriginal) {
                showOriginal = true
            }
            toggleButton("After", isActive: !showOriginal) {
                showOriginal = false
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func toggleButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.toggleLabel)
                .textCase(.uppercase)
                .foregroundStyle(isActive ? Color.text0 : Color.text3)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.white.opacity(0.1) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
