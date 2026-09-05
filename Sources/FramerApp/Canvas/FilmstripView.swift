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
                            Button {
                                select(item, extendingSelection: NSEvent.modifierFlags.contains(.command))
                            } label: {
                                FilmstripThumbnail(
                                    item: item,
                                    isSelected: appState.selectedItems.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .accessibilityLabel(item.url.lastPathComponent)
                            .accessibilityAddTraits(appState.selectedItems.contains(item.id) ? .isSelected : [])
                            .accessibilityAction(named: appState.selectedItems.contains(item.id) ? "Remove from selection" : "Add to selection") {
                                select(item, extendingSelection: true)
                            }
                            .help(item.url.lastPathComponent)
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
                        Button(action: { NotificationCenter.default.post(name: .framerOpenPhotos, object: nil) }) {
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
                        .accessibilityLabel("Open more photos")
                        .help("Open more photos (⌘O)")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }
                .onChange(of: appState.selectedItems) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    if let first = appState.selectedPhoto?.id {
                        withAnimation {
                            proxy.scrollTo(first, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color.clear)
    }

    private func select(_ item: PhotoItem, extendingSelection: Bool) {
        guard appState.library.contains(where: { $0.id == item.id }) else { return }
        if extendingSelection {
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
