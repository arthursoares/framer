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
                // Use the actual pixel dimensions so NSImage doesn't scale incorrectly at init.
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
    }

    /// Loads a retina-resolution thumbnail via ImageIO, caching the result in a
    /// process-wide NSCache so repeated scrolls never re-decode from disk.
    private static func loadCGThumbnail(from url: URL) async -> CGImage? {
        // Fast path: return cached image without hitting the disk.
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            return cached.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        return await Task.detached { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                // Ask ImageIO to decode only a small thumbnail, skipping the full image decode.
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // 160 px covers the 80-pt slot at 2x Retina without decoding the full image.
                kCGImageSourceThumbnailMaxPixelSize: 160,
                // Apply EXIF rotation so the thumbnail is correctly oriented.
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            // Store as NSImage so the cache can evict under memory pressure.
            let nsImage = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            thumbnailCache.setObject(nsImage, forKey: url as NSURL)

            return thumbnail
        }.value
    }

    /// Process-wide thumbnail cache. Capped at 500 entries (~40 MB at 160px JPEG thumbnails).
    private nonisolated(unsafe) static let thumbnailCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 500
        return cache
    }()
}
