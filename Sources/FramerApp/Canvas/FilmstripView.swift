import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct FilmstripView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(appState.library) { item in
                            FilmstripThumbnail(
                                item: item,
                                isSelected: appState.selectedItems.contains(item.id)
                            )
                            .id(item.id)
                            .onTapGesture {
                                if NSEvent.modifierFlags.contains(.command) {
                                    if appState.selectedItems.contains(item.id) {
                                        appState.selectedItems.remove(item.id)
                                    } else {
                                        appState.selectedItems.insert(item.id)
                                    }
                                } else {
                                    appState.selectedItems = [item.id]
                                }
                            }
                        }

                        // Divider + count
                        if !appState.library.isEmpty {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 6)

                            Text("\(appState.library.count)")
                                .font(AppFont.photoCount)
                                .foregroundStyle(Color.text3)
                        }

                        // Add button
                        Button(action: openFilePicker) {
                            Circle()
                                .strokeBorder(Color.text3, style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.text3)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }
                .onChange(of: appState.selectedItems) { _, newValue in
                    if let first = newValue.first {
                        withAnimation {
                            proxy.scrollTo(first, anchor: .center)
                        }
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        }
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
}
