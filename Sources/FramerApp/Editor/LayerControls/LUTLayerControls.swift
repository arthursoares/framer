import SwiftUI
import AppKit
import FramerCore

// MARK: - LUTLayerControls

struct LUTLayerControls: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sidebarMetrics) private var metrics
    var params: LUTLayerParams
    var onChange: (LUTLayerParams) -> Void

    @State private var availableLUTs: [LUTInfo] = []
    @State private var thumbnailCache: [String: CGImage] = [:]
    @State private var renamingLUT: LUTInfo?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BlendModeControls(
                blendMode: Binding(
                    get: { params.blendMode },
                    set: { var p = params; p.blendMode = $0; onChange(p) }
                ),
                opacity: Binding(
                    get: { params.opacity },
                    set: { var p = params; p.opacity = $0; onChange(p) }
                )
            )

            SimpleLayerEditorDivider()
            lutPicker

            SimpleLayerEditorDivider()
            lutThumbnailStrip

            SimpleLayerEditorDivider()
            intensityControl

            SimpleLayerEditorDivider()
            importButtons
        }
        .task {
            loadLUTs()
            await reloadThumbnailsForSelectedPhoto()
        }
        .onChange(of: appState.selectedPhoto?.id) { _, _ in
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }
        }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }
        }
        .alert("Rename LUT", isPresented: Binding(
            get: { renamingLUT != nil },
            set: { if !$0 { renamingLUT = nil } }
        )) {
            TextField("LUT name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingLUT = nil
            }
            Button("Rename") {
                renameSelectedLUT()
            }
        } message: {
            Text("Enter a new name for this LUT.")
        }
    }

    private var lutPicker: some View {
        Picker("", selection: lutNameBinding) {
            Text("None").tag("")
            ForEach(availableLUTs) { lut in
                Text(lut.displayName).tag(lut.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("LUT")
    }

    @MainActor
    private func reloadThumbnailsForSelectedPhoto() async {
        thumbnailCache = [:]
        await generateThumbnails()
    }

    private func generateThumbnails() async {
        guard let sourceImage = await selectedPhotoThumbnail() else {
            return
        }

        let luts = availableLUTs
        for lut in luts {
            if thumbnailCache[lut.id] == nil {
                let thumb = await Task.detached(priority: .userInitiated) {
                    LUTProvider.thumbnail(for: lut, sourceImage: sourceImage, size: 48)
                }.value
                if let thumb {
                    await MainActor.run {
                        thumbnailCache[lut.id] = thumb
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lutThumbnailStrip: some View {
        if availableLUTs.isEmpty {
            SidebarFullWidthRow("Preview") {
                VStack(spacing: metrics.expandedBodyInset) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.text3)
                    Text("No LUTs available")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text3)
                    Text("Import .cube files to get started")
                        .font(.caption)
                        .foregroundStyle(Color.text3)
                }
                .padding(.vertical, metrics.expandedBodyInset * 2)
            }
        } else {
            SidebarFullWidthRow("Preview") {
                SidebarPreviewStrip(
                    items: availableLUTs,
                    tileWidth: 48,
                    tileHeight: nil,
                    spacing: metrics.expandedBodyInset
                ) { lut in
                    lutThumb(lut)
                }
            }
        }
    }

    private var intensityControl: some View {
        DenseSliderControlRow(
            title: "Intensity",
            value: Binding(
                get: { params.intensity * 100 },
                set: { intensityBinding.wrappedValue = $0 / 100 }
            ),
            range: 0...100,
            step: 5,
            unit: "%"
        )
    }

    private var importButtons: some View {
        SidebarFullWidthRow("Library") {
            HStack(spacing: metrics.controlColumnSpacing) {
                Button {
                    importLUT()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(AppFont.controlLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.text2)

                Button {
                    openLUTsFolder()
                } label: {
                    Label("Show Folder", systemImage: "folder")
                        .font(AppFont.controlLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.text2)
            }
        }
    }

    private func lutThumb(_ lut: LUTInfo) -> some View {
        Button {
            selectLUT(lut)
        } label: {
            VStack(spacing: 2) {
                Group {
                    if let thumb = thumbnailCache[lut.id] {
                        Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: 48, height: 48)))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if appState.selectedPhoto == nil {
                        ZStack {
                            Color.surface2
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(Color.text3)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.surface2
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                        .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(params.lutFileName == lut.id ? Color.accent : Color.clear, lineWidth: 2)
                )
                Text(lut.displayName)
                    .font(.caption2)
                    .foregroundStyle(Color.text2)
                    .lineLimit(1)
                    .frame(width: 48)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if lut.category == "user" {
                Button {
                    renameText = lut.displayName
                    renamingLUT = lut
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteLUT(lut)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func selectLUT(_ lut: LUTInfo) {
        var p = params
        p.lutName = lut.displayName
        p.lutFileName = lut.id
        onChange(p)
    }

    private func loadLUTs() {
        availableLUTs = LUTProvider.availableLUTs()
    }

    private func selectedPhotoThumbnail() async -> CGImage? {
        guard let photo = appState.selectedPhoto else {
            return nil
        }

        return await ImageThumbnailLoader.loadCGThumbnail(
            from: photo.url,
            maxPixelSize: 96,
            rotation: photo.rotation
        )
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a .cube LUT file to import"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let info = try LUTProvider.importLUT(from: url)
                LUTProvider.invalidateCache()
                loadLUTs()
                Task {
                    await reloadThumbnailsForSelectedPhoto()
                }
                selectLUT(info)
            } catch {
                showImportError(error)
            }
        }
    }

    private func renameSelectedLUT() {
        guard let lut = renamingLUT else { return }

        do {
            try LUTProvider.renameUserLUT(named: lut.id, displayName: renameText)
            loadLUTs()
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }
            if params.lutFileName == lut.id,
               let refreshed = availableLUTs.first(where: { $0.id == lut.id }) {
                selectLUT(refreshed)
            }
        } catch {
            showLUTManagementError(error)
        }

        renamingLUT = nil
    }

    private func deleteLUT(_ lut: LUTInfo) {
        let alert = NSAlert()
        alert.messageText = "Remove LUT?"
        alert.informativeText = "This will remove \"\(lut.displayName)\" from your imported LUTs."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try LUTProvider.deleteUserLUT(named: lut.id)
            loadLUTs()
            Task {
                await reloadThumbnailsForSelectedPhoto()
            }

            if params.lutFileName == lut.id {
                var p = params
                p.lutName = ""
                p.lutFileName = ""
                onChange(p)
            }
        } catch {
            showLUTManagementError(error)
        }
    }

    private func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Import Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showLUTManagementError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "LUT Update Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openLUTsFolder() {
        if let dir = LUTProvider.userLUTDirectory() {
            NSWorkspace.shared.open(dir)
        }
    }

    private var lutNameBinding: Binding<String> {
        Binding(
            get: { params.lutFileName },
            set: { newValue in
                var p = params
                p.lutFileName = newValue
                if let lut = availableLUTs.first(where: { $0.id == newValue }) {
                    p.lutName = lut.displayName
                }
                onChange(p)
            }
        )
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { params.intensity },
            set: { newValue in
                var p = params
                p.intensity = newValue
                onChange(p)
            }
        )
    }
}
