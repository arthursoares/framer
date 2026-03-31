import SwiftUI
import PhotosUI
import FramerCore

struct PhotoPickerView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 50,
                matching: .images,
                photoLibrary: .shared()
            ) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.text3)
                    Text("Select Photos")
                        .font(AppFont.body(16, weight: .medium))
                        .foregroundStyle(Color.text1)
                    Text("Tap to open the photo picker")
                        .font(AppFont.body(13))
                        .foregroundStyle(Color.text3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                loadPhotos(from: items)
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading photos...")
                        .tint(Color.accent)
                        .padding(24)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                }
            }
            .background(Color.surface0)
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.text2)
                }
            }
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        isLoading = true
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
            isLoading = false
            dismiss()
        }
    }
}
