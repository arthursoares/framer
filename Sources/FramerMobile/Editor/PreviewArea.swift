import SwiftUI

struct PreviewArea: View {
    @Environment(AppState.self) var appState
    let viewModel: PreviewViewModel
    @Binding var showingOriginal: Bool

    @State private var dragOffset: CGFloat = 0

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
                    .offset(x: dragOffset)
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
            if appState.library.count > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(appState.selectedIndex + 1) / \(appState.library.count)")
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
        .contentShape(Rectangle())
        // Swipe left/right to navigate photos
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    dragOffset = value.translation.width * 0.4
                }
                .onEnded { value in
                    let threshold: CGFloat = 60
                    if value.translation.width < -threshold {
                        // Swipe left → next photo
                        if appState.selectedIndex < appState.library.count - 1 {
                            appState.selectedIndex += 1
                        }
                    } else if value.translation.width > threshold {
                        // Swipe right → previous photo
                        if appState.selectedIndex > 0 {
                            appState.selectedIndex -= 1
                        }
                    }
                    withAnimation(.easeOut(duration: 0.15)) {
                        dragOffset = 0
                    }
                }
        )
        // Long press to show original
        .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
            showingOriginal = pressing
        }, perform: {})
    }
}
