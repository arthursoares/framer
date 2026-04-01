import SwiftUI
import CoreGraphics

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
                    .foregroundStyle(Color.text3)
            }
        }
        .task {
            if let cgImage = await ImageThumbnailLoader.loadCGThumbnail(from: url) {
                // Use the actual pixel dimensions so NSImage doesn't scale incorrectly at init.
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
    }
}
