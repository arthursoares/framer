import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct FilmstripView: View {
    @Environment(AppState.self) var appState
    @FocusState private var focusedPhotoID: PhotoItem.ID?
    var onToggleOriginal: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(appState.library) { item in
                            Button {
                                select(item, extendingSelection: NSEvent.modifierFlags.contains(.command))
                                focusedPhotoID = item.id
                            } label: {
                                FilmstripThumbnail(
                                    item: item,
                                    isSelected: appState.selectedItems.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedPhotoID, equals: item.id)
                            .onKeyPress(phases: .down) { press in
                                guard press.modifiers.isEmpty else { return .ignored }
                                if press.key == .space {
                                    onToggleOriginal()
                                    return .handled
                                }
                                let forward: Bool
                                switch press.key {
                                case .leftArrow: forward = false
                                case .rightArrow: forward = true
                                default: return .ignored
                                }
                                focusedPhotoID = appState.selectAdjacentPhoto(forward: forward, from: item.id)
                                return .handled
                            }
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
        .onChange(of: appState.selectedItems) { _, selected in
            // Menu navigation updates selection outside the filmstrip. When a
            // thumbnail still owns focus, move focus with that selection so
            // the next arrow continues from the newly selected photo.
            if focusedPhotoID != nil, selected.count == 1 {
                focusedPhotoID = selected.first
            }
        }
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
