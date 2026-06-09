import SwiftUI
import FramerCore

/// "Saved palettes" menu: apply a stored user palette, save the current
/// colours under a name, or delete stored palettes. Backed by
/// `UserPaletteStore` (Application Support/Framer/palettes.json). Shared by
/// the Dither palette editor and the GPU-effect palette colour mode so a
/// palette built in one editor is reusable in the other.
struct UserPaletteMenu: View {
    var currentColors: [CodableColor]
    var onApply: ([CodableColor]) -> Void

    @State private var palettes: [UserPalette] = []
    @State private var showingSavePrompt = false
    @State private var saveName = ""

    private let store = UserPaletteStore()

    var body: some View {
        Menu {
            if palettes.isEmpty {
                Text("No Saved Palettes")
            } else {
                ForEach(palettes) { palette in
                    Button(palette.name) { onApply(palette.colors) }
                }
            }
            Divider()
            Button("Save Current Palette…") {
                saveName = ""
                showingSavePrompt = true
            }
            if !palettes.isEmpty {
                Menu("Delete Palette") {
                    ForEach(palettes) { palette in
                        Button(palette.name, role: .destructive) {
                            try? store.delete(id: palette.id)
                            reload()
                        }
                    }
                }
            }
        } label: {
            Label("Saved Palettes", systemImage: "swatchpalette")
                .font(AppFont.buttonText)
                .foregroundStyle(Color.text2)
        }
        .onAppear(perform: reload)
        .alert("Save Palette", isPresented: $showingSavePrompt) {
            TextField("Name", text: $saveName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current \(currentColors.count) colours for reuse in any palette editor.")
        }
    }

    private func reload() {
        palettes = store.list()
    }

    private func saveCurrent() {
        let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.save(UserPalette(name: trimmed, colors: currentColors))
        reload()
    }
}
