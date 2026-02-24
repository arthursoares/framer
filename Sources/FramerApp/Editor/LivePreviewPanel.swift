import SwiftUI
import FramerCore

struct LivePreviewPanel: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Preview image
            ZStack {
                checkerboardBackground

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let img = viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(24)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("No photo selected")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Select a photo from the library,\nor drag images into the sidebar")
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // EXIF + caption info bar
            if let exif = viewModel.exifData {
                Divider()
                ExifInfoBar(exif: exif, config: appState.currentConfig)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
        }
        .onChange(of: appState.selectedItems) { _, _ in updatePreview() }
        .onChange(of: appState.currentConfig) { _, _ in updatePreview() }
        .onAppear { updatePreview() }
    }

    /// Subtle checkerboard for transparency visibility
    private var checkerboardBackground: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 12
            let lightColor = Color(nsColor: .controlBackgroundColor)
            let darkColor = Color(nsColor: .controlBackgroundColor).opacity(0.92)
            for row in 0..<Int(ceil(size.height / tileSize)) {
                for col in 0..<Int(ceil(size.width / tileSize)) {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(Path(rect), with: .color(isLight ? lightColor : darkColor))
                }
            }
        }
    }

    private func updatePreview() {
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
    }
}

struct ExifInfoBar: View {
    let exif: ExifData
    let config: ProcessingConfig
    @State private var showingInspector = false

    var captionText: String {
        switch config.captionMode {
        case .template(let t): exif.resolve(template: t)
        case .custom(let s): s
        case .none: "(no caption)"
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
