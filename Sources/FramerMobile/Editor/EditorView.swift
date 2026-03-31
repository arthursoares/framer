import SwiftUI
import FramerCore

struct EditorView: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @State private var presetCache = PresetPreviewCache()
    @State private var showingOriginal = false

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
                    Button {
                        appState.showingPhotosPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                            .foregroundStyle(Color.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "placeholder") {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Color.accent)
                    }
                }
            }
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        .sheet(isPresented: Binding(
            get: { appState.showingPhotosPicker },
            set: { appState.showingPhotosPicker = $0 }
        )) {
            PhotoPickerView()
        }
    }

    private func updatePreview() {
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
    }

    private func regeneratePresetPreviews() {
        guard let photo = appState.selectedPhoto else { return }
        presetCache.regenerate(for: photo, presets: appState.presets)
    }
}
