import SwiftUI

struct PhotoThumbnailView: View {
    let item: PhotoItem

    var body: some View {
        HStack(spacing: 8) {
            AsyncThumbnail(url: item.url)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(item.url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
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
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> NSImage? {
        await Task.detached {
            guard let nsImage = NSImage(contentsOf: url) else { return nil }
            let orig = nsImage.size
            // Center-crop to square (cover)
            let side = min(orig.width, orig.height)
            let cropRect = NSRect(
                x: (orig.width - side) / 2,
                y: (orig.height - side) / 2,
                width: side,
                height: side
            )
            let size = NSSize(width: 80, height: 80)
            return NSImage(size: size, flipped: false) { rect in
                nsImage.draw(in: rect, from: cropRect,
                             operation: .copy, fraction: 1.0)
                return true
            }
        }.value
    }
}
