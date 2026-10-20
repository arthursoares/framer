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
    @State private var paletteError: String?
    @State private var showingPaletteError = false

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
                            do {
                                try store.delete(id: palette.id)
                                reload()
                            } catch {
                                report(error)
                            }
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
        .alert("Saved Palettes Unavailable", isPresented: $showingPaletteError) {
            Button("OK") { }
        } message: {
            Text(paletteError ?? "Check the saved palettes file and try again.")
        }
    }

    private func reload() {
        do {
            palettes = try store.list()
        } catch {
            palettes = []
            report(error)
        }
    }

    private func saveCurrent() {
        let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.save(UserPalette(name: trimmed, colors: currentColors))
            reload()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        paletteError = "Framer couldn’t read or update saved palettes. \(error.localizedDescription)"
        showingPaletteError = true
    }
}
