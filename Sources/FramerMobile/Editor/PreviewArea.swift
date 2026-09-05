import SwiftUI

struct PreviewArea: View {
    struct ComparisonPressState {
        private var previousMode: Bool?

        mutating func update(
            isPressing: Bool,
            isDragging: Bool,
            currentMode: Bool
        ) -> Bool? {
            if isPressing {
                guard previousMode == nil, !isDragging else { return nil }
                previousMode = currentMode
                return true
            }

            guard let previousMode else { return nil }
            self.previousMode = nil
            return previousMode
        }

        mutating func select(_ mode: Bool) -> Bool {
            previousMode = nil
            return mode
        }
    }

    @Environment(AppState.self) var appState
    let viewModel: PreviewViewModel
    @Binding var showingOriginal: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var zoomState = ZoomState()
    @State private var magnifyBase: CGFloat = 1.0
    @State private var panStart: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var isDragging = false
    @State private var comparisonPressState = ComparisonPressState()

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

            GeometryReader { geo in
                ZStack {
                    ZStack {
                        Color.clear
                        if let img = displayedImage {
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
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 0.3,
                        pressing: updateComparisonPress,
                        perform: {}
                    )

                    if displayedImage == nil {
                        viewportState
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            retainedPreviewProgress
            retainedPreviewError

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

            if appState.selectedPhoto != nil {
                VStack {
                    Spacer()
                    beforeAfterControl
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Reset zoom on photo change
        .onChange(of: appState.selectedIndex) { _, _ in
            zoomState.fitToWindow()
            dragOffset = 0
        }
    }

    @ViewBuilder
    private var viewportState: some View {
        if appState.selectedPhoto == nil {
            VStack(spacing: 12) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.text3)
                Text("Add photos to begin")
                    .font(AppFont.body(15, weight: .medium))
                    .foregroundStyle(Color.text2)
                Text("Choose images from your photo library")
                    .font(AppFont.body(13))
                    .foregroundStyle(Color.text3)
                Button("Choose Photos", systemImage: "photo.on.rectangle") {
                    appState.showingPhotosPicker = true
                }
                .font(AppFont.buttonText)
                .buttonStyle(.borderedProminent)
                .tint(Color.accentDim)
                .frame(minHeight: 44)
            }
        } else if showingOriginal, viewModel.isOriginalLoading {
            loadingState("Loading original…")
        } else if showingOriginal, let error = viewModel.originalError {
            failureState(
                title: "Original unavailable",
                message: error,
                retry: retryOriginal,
                secondaryTitle: "Show Edited",
                secondaryAction: showEdited
            )
        } else if !showingOriginal, viewModel.isLoading {
            loadingState("Rendering preview…")
        } else if !showingOriginal, let error = viewModel.error {
            failureState(title: "Preview unavailable", message: error, retry: retryPreview)
        } else {
            loadingState(showingOriginal ? "Loading original…" : "Rendering preview…")
        }
    }

    @ViewBuilder
    private var retainedPreviewProgress: some View {
        if !showingOriginal, viewModel.previewImage != nil, viewModel.isLoading {
            VStack {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Updating…")
                        .font(AppFont.body(12))
                }
                .tint(Color.accent)
                .foregroundStyle(Color.text1)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.surface2, in: Capsule())
                .padding(.top, Spacing.md)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var retainedPreviewError: some View {
        if !showingOriginal, viewModel.previewImage != nil, let error = viewModel.error {
            VStack {
                Spacer()
                HStack(spacing: Spacing.md) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .lineLimit(2)
                    Button("Retry", action: retryPreview)
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                }
                .font(AppFont.body(12))
                .foregroundStyle(Color.error)
                .padding(.horizontal, Spacing.md)
                .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, 60)
            }
        }
    }

    private var beforeAfterControl: some View {
        HStack(spacing: 0) {
            comparisonButton("Before", showsOriginal: true)
            comparisonButton("After", showsOriginal: false)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.borderActive, lineWidth: 1))
    }

    private func comparisonButton(_ title: String, showsOriginal: Bool) -> some View {
        let isSelected = showingOriginal == showsOriginal
        return Button(title) {
            showingOriginal = comparisonPressState.select(showsOriginal)
        }
        .font(AppFont.buttonText)
        .foregroundStyle(isSelected ? Color.text0 : Color.text2)
        .frame(minWidth: 88, minHeight: 44)
        .background(isSelected ? Color.accentSubtle : .clear, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityLabel(showsOriginal ? "Before, original photo" : "After, edited photo")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func loadingState(_ title: String) -> some View {
        ProgressView(title)
            .font(AppFont.body(13))
            .foregroundStyle(Color.text2)
            .tint(Color.accent)
    }

    private func failureState(
        title: String,
        message: String,
        retry: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.error)
            Text(title)
                .font(AppFont.body(15, weight: .medium))
                .foregroundStyle(Color.text1)
            Text(message)
                .font(AppFont.body(12))
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack(spacing: Spacing.sm) {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentDim)
                    .frame(minHeight: 44)
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(Spacing.xl)
    }

    private func retryPreview() {
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
    }

    private func retryOriginal() {
        viewModel.loadOriginalIfNeeded(for: appState.selectedPhoto)
    }

    private func showEdited() {
        showingOriginal = false
    }

    private func updateComparisonPress(_ isPressing: Bool) {
        if isPressing {
            guard appState.selectedPhoto != nil, viewModel.previewImage != nil else { return }
        }
        if let mode = comparisonPressState.update(
            isPressing: isPressing,
            isDragging: isDragging,
            currentMode: showingOriginal
        ) {
            showingOriginal = mode
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
