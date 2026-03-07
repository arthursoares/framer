import SwiftUI
import CoreGraphics
import ImageIO

struct PhotoThumbnailView: View {
    let item: PhotoItem
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 8) {
            AsyncThumbnail(url: item.url)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .rotationEffect(.degrees(Double(item.rotation)))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button {
                appState.rotateItem(item.id, clockwise: true)
            } label: {
                Label("Rotate 90° CW", systemImage: "rotate.right")
            }
            Button {
                appState.rotateItem(item.id, clockwise: false)
            } label: {
                Label("Rotate 90° CCW", systemImage: "rotate.left")
            }
        }
    }
}

struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if let cgImage = await Self.loadCGThumbnail(from: url) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: 80, height: 80))
            }
        }
    }

    /// Generates a square center-cropped thumbnail as a CGImage (Sendable) off the main actor.
    private static func loadCGThumbnail(from url: URL) async -> CGImage? {
        await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            let w = full.width, h = full.height
            let side = min(w, h)
            let cropRect = CGRect(
                x: (w - side) / 2,
                y: (h - side) / 2,
                width: side,
                height: side
            )
            guard let cropped = full.cropping(to: cropRect) else { return nil }
            // Scale down to 80×80
            guard let ctx = CGContext(data: nil, width: 80, height: 80,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return cropped
            }
            ctx.interpolationQuality = .high
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 80, height: 80))
            return ctx.makeImage()
        }.value
    }
}
