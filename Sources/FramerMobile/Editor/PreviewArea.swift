import SwiftUI

struct PreviewArea: View {
    @Environment(AppState.self) var appState
    let viewModel: PreviewViewModel
    @Binding var showingOriginal: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var zoomState = ZoomState()
    @State private var magnifyBase: CGFloat = 1.0
    @State private var panStart: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var isDragging = false

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
                GeometryReader { geo in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 20)
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                        .scaleEffect(zoomState.scale)
                        .offset(zoomState.isAtFit ? CGSize(width: dragOffset, height: 0) : zoomState.offset)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(viewSize: geo.size))
                        .simultaneousGesture(magnifyGesture(viewSize: geo.size))
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                zoomState.toggleFitActual()
                                panStart = .zero
                            }
                        }
                        .onAppear {
                            updateFitScale(img: img, viewSize: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            viewportSize = newSize
                            updateFitScale(img: img, viewSize: newSize)
                        }
                        .onChange(of: img.size.width) { _, _ in
                            updateFitScale(img: img, viewSize: geo.size)
                        }
                        .onChange(of: img.size.height) { _, _ in
                            updateFitScale(img: img, viewSize: geo.size)
                        }
                }
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

            // Zoom indicator (replaces output size badge when not at fit)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if !zoomState.isAtFit {
                        ZoomIndicator(
                            zoomState: zoomState,
                            onFit: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    zoomState.fitToWindow()
                                }
                            },
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    zoomState.toggleFitActual()
                                }
                            }
                        )
                    } else if let size = viewModel.outputSize {
                        Text("\(Int(size.width))×\(Int(size.height))")
                            .font(AppFont.mono(10))
                            .foregroundStyle(Color.text3)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Long press to show original (only when not dragging)
        .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
            if !isDragging { showingOriginal = pressing }
        }, perform: {})
        // Reset zoom on photo change
        .onChange(of: appState.selectedIndex) { _, _ in
            zoomState.fitToWindow()
            dragOffset = 0
        }
    }

    // MARK: - Gestures

    private func magnifyGesture(viewSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / magnifyBase
                zoomState.applyMagnification(delta, anchor: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize: viewSize)
                magnifyBase = value.magnification
            }
            .onEnded { _ in
                magnifyBase = 1.0
                if zoomState.isAtFit {
                    withAnimation(.easeOut(duration: 0.15)) {
                        zoomState.fitToWindow()
                    }
                } else {
                    zoomState.clampOffset(imageSize: fittedImageSize(), viewSize: viewSize)
                }
            }
    }

    private func dragGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: zoomState.isAtFit ? 30 : 5)
            .onChanged { value in
                isDragging = true
                if zoomState.isAtFit {
                    dragOffset = value.translation.width * 0.4
                } else {
                    zoomState.offset = CGSize(
                        width: panStart.width + value.translation.width,
                        height: panStart.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                isDragging = false
                if zoomState.isAtFit {
                    let threshold: CGFloat = 60
                    if value.translation.width < -threshold {
                        if appState.selectedIndex < appState.library.count - 1 {
                            appState.selectedIndex += 1
                        }
                    } else if value.translation.width > threshold {
                        if appState.selectedIndex > 0 {
                            appState.selectedIndex -= 1
                        }
                    }
                    withAnimation(.easeOut(duration: 0.15)) {
                        dragOffset = 0
                    }
                } else {
                    zoomState.clampOffset(imageSize: fittedImageSize(), viewSize: viewSize)
                    panStart = zoomState.offset
                }
            }
    }

    // MARK: - Helpers

    private func updateFitScale(img: UIImage, viewSize: CGSize) {
        let padded = CGSize(width: max(1, viewSize.width - 40), height: max(1, viewSize.height))
        zoomState.updateFitScale(imageSize: img.size, viewSize: padded)
        viewportSize = viewSize
    }

    private var displayedImage: UIImage? {
        showingOriginal ? viewModel.originalImage : viewModel.previewImage
    }

    private func fittedImageSize() -> CGSize {
        guard let img = displayedImage else { return .zero }
        let padded = CGSize(width: max(1, viewportSize.width - 40), height: max(1, viewportSize.height))
        let fitW = padded.width / img.size.width
        let fitH = padded.height / img.size.height
        let fit = min(fitW, fitH)
        return CGSize(width: img.size.width * fit, height: img.size.height * fit)
    }
}
