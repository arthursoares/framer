import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct LivePreviewPanel: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @State private var showOriginal = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Preview image
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let img = showOriginal ? viewModel.originalImage : viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(24)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .transition(.opacity)
                        .overlay(alignment: .bottomTrailing) {
                            if !showOriginal, let dims = viewModel.outputDimensions {
                                Text(dims)
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .padding(8)
                            }
                        }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("No photo selected")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Select a photo from the library,\nor drag images here")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }

                if let err = viewModel.error {
                    VStack {
                        Spacer()
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding()
                    }
                }

                // Before/After toggle
                if viewModel.previewImage != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Picker("", selection: Binding(
                                get: { showOriginal },
                                set: { newValue in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        showOriginal = newValue
                                    }
                                }
                            )) {
                                Text("Before").tag(true)
                                Text("After").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            .labelsHidden()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            Spacer()
                        }
                        .padding(.leading, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(4)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            // EXIF + caption info bar
            if let exif = viewModel.exifData {
                Divider()
                ExifInfoBar(exif: exif, config: appState.currentConfig)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
        }
        .onChange(of: appState.selectedItems) { _, _ in
            showOriginal = false
            updatePreview()
        }
        .onChange(of: appState.currentConfig) { _, _ in updatePreview() }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in updatePreview() }
        .onAppear { updatePreview() }
    }

    private func updatePreview() {
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        appState.addPhotos(from: [url])
                    }
                }
            }
        }
        return true
    }
}

struct ExifInfoBar: View {
    let exif: ExifData
    let config: ProcessingConfig
    @State private var showingInspector = false

    var captionText: String {
        guard let layers = config.layers,
              let captionLayer = layers.first(where: { if case .caption = $0 { return true }; return false }),
              case .caption(let params) = captionLayer else {
            return "(no caption)"
        }
        switch params.mode {
        case .template(let t): return exif.resolve(template: t)
        case .custom(let s): return s
        case .none: return "(no caption)"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let camera = exif.camera {
                    Text(camera)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    exifChip(exif.iso.map { "ISO \($0)" })
                    exifChip(exif.aperture.map { "f/\($0)" })
                    exifChip(exif.shutterSpeed)
                    exifChip(exif.focalLength.map { "\($0)mm" })
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Caption:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(captionText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Button(action: { showingInspector.toggle() }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInspector) {
                EXIFInspectorPopover(exif: exif)
            }
        }
    }

    @ViewBuilder
    private func exifChip(_ value: String?) -> some View {
        if let v = value {
            Text(v)
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }
}

struct EXIFInspectorPopover: View {
    let exif: ExifData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXIF Data").font(.headline).padding(.bottom, 4)
            row("Camera", exif.camera)
            row("Lens", exif.lens)
            row("ISO", exif.iso)
            row("Aperture", exif.aperture.map { "f/\($0)" })
            row("Shutter", exif.shutterSpeed)
            row("Focal Length", exif.focalLength.map { "\($0)mm" })
            if let date = exif.dateTime {
                row("Date", DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
            }
        }
        .padding(16)
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value ?? "--")
        }
        .font(.caption)
    }
}
