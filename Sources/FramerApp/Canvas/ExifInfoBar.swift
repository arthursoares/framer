import SwiftUI
import FramerCore

struct ExifInfoBar: View {
    let exif: ExifData
    let config: ProcessingConfig
    var outputSize: CGSize?
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
                        .font(AppFont.body(11))
                        .foregroundStyle(Color.text2)
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
                Text("CAPTION")
                    .font(AppFont.sectionHeader)
                    .tracking(1.5)
                    .foregroundStyle(Color.text3)
                Text(captionText)
                    .font(AppFont.mono(11))
                    .foregroundStyle(Color.text1)
            }

            if let size = outputSize {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("OUTPUT")
                        .font(AppFont.sectionHeader)
                        .tracking(1.5)
                        .foregroundStyle(Color.text3)
                    Text("\(Int(size.width))×\(Int(size.height))")
                        .font(AppFont.mono(11))
                        .foregroundStyle(Color.text1)
                }
                .padding(.leading, 12)
            }

            Button(action: { showingInspector.toggle() }) {
                Circle()
                    .stroke(Color.borderDefault, lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "info")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.text2)
                    }
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
                .font(AppFont.exifChip)
                .foregroundStyle(Color.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.surface3, in: Capsule())
        }
    }
}

struct EXIFInspectorPopover: View {
    let exif: ExifData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXIF DATA")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)
                .padding(.bottom, 4)
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
        .background(Color.surface1)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.text2)
                .frame(width: 100, alignment: .trailing)
            Text(value ?? "--")
                .foregroundStyle(Color.text1)
        }
        .font(AppFont.body(11))
    }
}
