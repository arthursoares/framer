import SwiftUI

struct PreviewArea: View {
    let viewModel: PreviewViewModel
    @Binding var showingOriginal: Bool
    let photoCount: Int
    let currentIndex: Int

    var body: some View {
        ZStack {
            // Background
            Color.surface0
            RadialGradient(
                colors: [Color.accent.opacity(0.02), .clear],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 300
            )

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color.text2)
            } else if let img = showingOriginal ? viewModel.originalImage : viewModel.previewImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 20)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.text3)
                    Text("No photo selected")
                        .font(AppFont.body(15, weight: .medium))
                        .foregroundStyle(Color.text2)
                    Text("Tap Photos to get started")
                        .font(AppFont.body(13))
                        .foregroundStyle(Color.text3)
                }
            }

            // Photo counter badge
            if photoCount > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(currentIndex + 1) / \(photoCount)")
                            .font(AppFont.mono(11))
                            .foregroundStyle(Color.text2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: Capsule())
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            }

            // Output size badge
            if let size = viewModel.outputSize {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(Int(size.width))×\(Int(size.height))")
                            .font(AppFont.mono(10))
                            .foregroundStyle(Color.text3)
                            .padding(.trailing, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in showingOriginal = true }
                .onEnded { _ in showingOriginal = false }
        )
    }
}
