import SwiftUI
import FramerCore

struct PresetStrip: View {
    @Environment(AppState.self) var appState
    let cache: PresetPreviewCache
    @State private var showingImporter = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.presets) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: appState.activePresetName == preset.name,
                        thumbnail: cache.previews[preset.id],
                        onTap: {
                            appState.currentConfig = preset.config
                            appState.activePresetName = preset.name
                            appState.appliedPresetConfig = preset.config
                        }
                    )
                    .contextMenu {
                        Button {
                            appState.currentConfig = preset.config
                            appState.activePresetName = preset.name
                            appState.appliedPresetConfig = preset.config
                        } label: {
                            Label("Apply", systemImage: "checkmark.circle")
                        }
                        Button {
                            exportPreset(preset)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            try? appState.presetStore.delete(id: preset.id)
                            appState.loadPresets()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                // Save card
                Button {
                    saveCurrentAsPreset()
                } label: {
                    VStack(spacing: 0) {
                        ZStack {
                            Color.surface3
                            Image(systemName: "plus")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.text3)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .strokeBorder(Color.text3, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )

                        Text("Save")
                            .font(AppFont.body(10))
                            .foregroundStyle(Color.text3)
                            .padding(.top, 4)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(.plain)

                // Import card
                Button {
                    showingImporter = true
                } label: {
                    VStack(spacing: 0) {
                        ZStack {
                            Color.surface3.opacity(0.5)
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.text3)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .strokeBorder(Color.text3.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )

                        Text("Import")
                            .font(AppFont.body(10))
                            .foregroundStyle(Color.text3)
                            .padding(.top, 4)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 100)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        try? appState.presetStore.importData(data)
                    }
                }
                appState.loadPresets()
            }
        }
    }

    private func saveCurrentAsPreset() {
        let baseName = "Preset"
        let existingNames = Set(appState.presets.map(\.name))
        var name = baseName
        var counter = 1
        while existingNames.contains(name) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        let preset = Preset(name: name, config: appState.currentConfig)
        try? appState.presetStore.save(preset)
        appState.loadPresets()
        appState.activePresetName = preset.name
        appState.appliedPresetConfig = preset.config
    }

    private func exportPreset(_ preset: Preset) {
        guard let data = try? appState.presetStore.exportData(for: preset) else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(preset.name).framerpreset")
        try? data.write(to: tempURL)
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        var presenter = rootVC
        while let presented = presenter.presentedViewController { presenter = presented }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }
}

struct PresetCard: View {
    let preset: Preset
    let isActive: Bool
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    Color.surface3
                    if let thumb = thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(isActive ? Color.accent : .clear, lineWidth: 2)
                )
                .shadow(color: isActive ? Color.accent.opacity(0.25) : .clear, radius: 6)
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color.surface0)
                            }
                            .offset(x: 3, y: -3)
                    }
                }

                Text(preset.name)
                    .font(AppFont.body(10))
                    .foregroundStyle(isActive ? Color.accent : Color.text3)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}
