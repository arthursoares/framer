import SwiftUI
import FramerCore

struct PresetStrip: View {
    @Environment(AppState.self) var appState
    let cache: PresetPreviewCache
    @State private var showingImporter = false
    @State private var renamingPreset: Preset?
    @State private var renameText = ""
    @State private var saveText = ""
    @State private var pendingDeletion: Preset?

    var body: some View {
        @Bindable var appState = appState

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
                            renameText = preset.name
                            renamingPreset = preset
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            appState.updatePreset(preset)
                        } label: {
                            Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            exportPreset(preset)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            pendingDeletion = preset
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .confirmationDialog(
                        "Delete “\(preset.name)”?",
                        isPresented: Binding(
                            get: { pendingDeletion?.id == preset.id },
                            set: { if !$0, pendingDeletion?.id == preset.id { pendingDeletion = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("Delete Preset", role: .destructive) {
                            appState.deletePreset(preset)
                            pendingDeletion = nil
                        }
                        Button("Cancel", role: .cancel) { pendingDeletion = nil }
                    } message: {
                        Text("This removes the saved preset from Framer.")
                    }
                }

                // Save card
                Button {
                    saveText = suggestedPresetName
                    appState.showingSavePresetSheet = true
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
            switch result {
            case .success(let urls):
                appState.importPresets(from: urls)
            case .failure(let error):
                if (error as? CocoaError)?.code == .userCancelled { return }
                appState.presetOperationAlert = PresetOperationAlert(
                    title: "Presets Not Imported",
                    message: "Framer couldn’t open the selected files. Try choosing them again."
                )
            }
        }
        .alert("Rename Preset", isPresented: Binding(
            get: { renamingPreset != nil },
            set: { if !$0 { renamingPreset = nil } }
        )) {
            TextField("Preset name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingPreset = nil }
            Button("Rename") {
                if let preset = renamingPreset, appState.renamePreset(preset, to: renameText) {
                    renamingPreset = nil
                }
            }
            .disabled(appState.presetNameProblem(renameText, excluding: renamingPreset?.id) != nil)
        } message: {
            Text(appState.presetNameProblem(renameText, excluding: renamingPreset?.id) ?? "Choose a clear name for this preset.")
        }
        .alert("Save Preset", isPresented: $appState.showingSavePresetSheet) {
            TextField("Preset name", text: $saveText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                appState.saveCurrentPreset(named: saveText)
            }
            .disabled(appState.presetNameProblem(saveText) != nil)
        } message: {
            Text(appState.presetNameProblem(saveText) ?? "Name these settings so you can find them again.")
        }
        .alert(item: $appState.presetOperationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var suggestedPresetName: String {
        let baseName = "Preset"
        let existingNames = Set(appState.presets.map(\.name))
        var name = baseName
        var counter = 1
        while existingNames.contains(name) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        return name
    }

    private func exportPreset(_ preset: Preset) {
        guard let data = appState.presetExportData(preset) else { return }
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FramerPresetExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempURL = exportDirectory.appendingPathComponent(AppState.safePresetFilename(for: preset.name))
        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try data.write(to: tempURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: exportDirectory)
            appState.reportPresetExportFailure(for: preset)
            return
        }
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: exportDirectory)
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            try? FileManager.default.removeItem(at: exportDirectory)
            appState.reportPresetExportFailure(for: preset)
            return
        }
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
                            .aspectRatio(contentMode: .fit)
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
