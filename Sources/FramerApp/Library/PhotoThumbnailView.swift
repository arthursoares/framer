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
            let size = NSSize(width: 80, height: 80)
            let thumb = NSImage(size: size)
            thumb.lockFocus()
            nsImage.draw(in: NSRect(origin: .zero, size: size),
                        from: NSRect(origin: .zero, size: nsImage.size),
                        operation: .copy, fraction: 1.0)
            thumb.unlockFocus()
            return thumb
        }.value
    }
}
