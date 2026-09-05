import SwiftUI
import AppKit
import FramerCore

struct OverlayLayerControls: View {
    var params: OverlayLayerParams
    var onChange: (OverlayLayerParams) -> Void

    @Environment(\.sidebarMetrics) private var metrics

    @State private var availableOverlays: [TextureFrameProvider.OverlayInfo] = []
    @State private var selectedKind: OverlayKind = .frame

    init(params: OverlayLayerParams, onChange: @escaping (OverlayLayerParams) -> Void) {
        self.params = params
        self.onChange = onChange
        _selectedKind = State(initialValue: params.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kindPicker

            SimpleLayerEditorDivider()

            overlayPicker

            if !filteredOverlays.isEmpty {
                SimpleLayerEditorDivider()

                overlayThumbnailStrip
            }

            SimpleLayerEditorDivider()

            SidebarCompoundControlBlock {
                blendModePicker
            } secondary: {
                opacityControl
            }

            SimpleLayerEditorDivider()

            openFolderButton
        }
        .onAppear(perform: loadOverlays)
        .onChange(of: params.kind) { _, newKind in
            selectedKind = newKind
        }
    }

    // MARK: - Subviews

    private var kindPicker: some View {
        SidebarFullWidthRow("Category") {
            Picker("", selection: $selectedKind) {
                Text("Frames").tag(OverlayKind.frame)
                Text("Dust").tag(OverlayKind.dust)
                Text("Light Leaks").tag(OverlayKind.lightLeak)
                Text("Wet Plate").tag(OverlayKind.wetPlate)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: selectedKind) { _, newKind in
                var p = params
                p.kind = newKind
                p.blendMode = OverlayBlendMode.defaultFor(newKind)
                if !filteredOverlays.contains(where: { $0.id == p.overlayName }) {
                    p.overlayName = ""
                }
                onChange(p)
            }
        }
    }

    private var overlayPicker: some View {
        Picker("", selection: overlayNameBinding) {
            Text("None").tag("")
            ForEach(filteredOverlays) { overlay in
                Text(overlay.displayName).tag(overlay.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .denseControlRow("Overlay")
    }

    private var overlayThumbnailStrip: some View {
        SidebarFullWidthRow("Preview") {
            SidebarPreviewStrip(items: filteredOverlays) { overlay in
                overlayThumb(overlay)
            }
        }
    }

    private var blendModePicker: some View {
        SidebarControlRow("Blend Mode") {
            Picker("", selection: blendModeBinding) {
                ForEach(OverlayBlendMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var opacityControl: some View {
        DenseSliderControlRow(
            title: "Opacity",
            value: opacityBinding,
            range: 0...100,
            accessibilityLabel: "Opacity",
            step: 1,
            unit: "%"
        )
    }

    private var openFolderButton: some View {
        SidebarFullWidthRow("Library") {
            Button {
                if let dir = TextureFrameProvider.ensureUserOverlayDirectory() {
                    NSWorkspace.shared.open(dir)
                }
            } label: {
                Label("Open Overlays Folder", systemImage: "folder")
                    .font(AppFont.controlLabel)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.text2)
        }
    }

    // MARK: - Thumbnail

    private func overlayThumb(_ overlay: TextureFrameProvider.OverlayInfo) -> some View {
        Button {
            var p = params
            p.overlayName = overlay.id
            p.kind = overlay.kind
            onChange(p)
        } label: {
            AsyncOverlayThumbnail(overlay: overlay, isSelected: params.overlayName == overlay.id)
        }
        .buttonStyle(.plain)
        .help(overlay.displayName)
    }

    // MARK: - Bindings

    private var overlayNameBinding: Binding<String> {
        Binding(
            get: { params.overlayName },
            set: { name in
                var p = params
                p.overlayName = name
                if let info = availableOverlays.first(where: { $0.id == name }) {
                    p.kind = info.kind
                }
                onChange(p)
            }
        )
    }

    private var blendModeBinding: Binding<OverlayBlendMode> {
        Binding(
            get: { params.blendMode },
            set: {
                var p = params
                p.blendMode = $0
                onChange(p)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { params.opacity },
            set: {
                var p = params
                p.opacity = $0
                onChange(p)
            }
        )
    }

    // MARK: - Data

    private var filteredOverlays: [TextureFrameProvider.OverlayInfo] {
        availableOverlays.filter { $0.kind == selectedKind }
    }

    private func loadOverlays() {
        // Load on background to avoid blocking the UI
        Task.detached {
            let overlays = TextureFrameProvider.availableOverlays()
            await MainActor.run {
                availableOverlays = overlays
            }
        }
    }
}

// MARK: - AsyncOverlayThumbnail

/// Loads overlay thumbnail asynchronously with caching — avoids blocking the main thread.
private struct AsyncOverlayThumbnail: View {
    let overlay: TextureFrameProvider.OverlayInfo
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor))

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 58, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 60, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .task(id: overlay.id) {
            guard thumbnail == nil else { return }
            let info = overlay
            let image = await Task.detached {
                TextureFrameProvider.cachedThumbnail(for: info)
            }.value
            if let cgImage = image {
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                thumbnail = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                )
            }
        }
    }
}

// MARK: - LayerFillPicker

