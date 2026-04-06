import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @Binding var showOriginal: Bool
    @State private var isDropTargeted = false
    @FocusState private var isFocused: Bool
    @State private var zoomState =  ZoomState()
    @State private var viewportSize: CGSize = .zero
    @State private var scrollMonitor: Any?
    @State private var magnifyBase: CGFloat = 1.0
    @State private var isHoveringViewport = false
    @State private var panStartOffset: CGSize = .zero
    @State private var mouseLocationInViewport: CGPoint = .zero

    var body: some View {
        content
            .onAppear {
                updatePreview()
                installScrollMonitor()
                isFocused = true
            }
            .onDisappear { removeScrollMonitor() }
            .onChange(of: appState.selectedItems) { _, _ in
                showOriginal = false
                zoomState.fitToWindow()
                updatePreview()
            }
            .onChange(of: showOriginal) { _, show in
                if show { viewModel.loadOriginalIfNeeded(for: appState.selectedPhoto) }
                // Recompute fitScale for the now-displayed image
                if let img = displayedImage {
                    updateFitScale(img: img, viewSize: viewportSize)
                }
            }
            .onChange(of: appState.currentConfig) { _, _ in
                updatePreview()
            }
            .onChange(of: appState.selectedPhoto?.rotation) { _, _ in updatePreview() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            viewport
            filmstrip
            exifBar
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onReceive(NotificationCenter.default.publisher(for: .framerOpenPhotos)) { _ in openFilePicker() }
        .onReceive(NotificationCenter.default.publisher(for: .framerSelectAll)) { _ in
            appState.selectedItems = Set(appState.library.map(\.id))
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerDeleteSelected)) { _ in removeSelected() }
        .onReceive(NotificationCenter.default.publisher(for: .framerRotateCW)) { _ in
            for id in appState.selectedItems { appState.rotateItem(id, clockwise: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerRotateCCW)) { _ in
            for id in appState.selectedItems { appState.rotateItem(id, clockwise: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerPreviousPhoto)) { _ in navigateFilmstrip(forward: false) }
        .onReceive(NotificationCenter.default.publisher(for: .framerNextPhoto)) { _ in navigateFilmstrip(forward: true) }
        .onKeyPress(phases: .down, action: handleKeyPress)
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .space {
            showOriginal.toggle()
            return .handled
        }
        guard press.modifiers.contains(.command) else { return .ignored }
        switch press.characters {
        case "+", "=":
            withAnimation(.easeOut(duration: 0.15)) { zoomState.zoomIn() }
            return .handled
        case "-":
            withAnimation(.easeOut(duration: 0.15)) { zoomState.zoomOut() }
            return .handled
        case "0":
            withAnimation(.easeInOut(duration: 0.25)) { zoomState.fitToWindow() }
            return .handled
        case "1":
            withAnimation(.easeInOut(duration: 0.25)) { zoomState.actualPixels() }
            return .handled
        default:
            return .ignored
        }
    }

    @ViewBuilder
    private var filmstrip: some View {
        if !appState.library.isEmpty {
            FilmstripView()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Color.surface1
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.borderDefault).frame(height: 1)
                        }
                }
        }
    }

    @ViewBuilder
    private var exifBar: some View {
        if let exif = viewModel.exifData {
            ExifInfoBar(exif: exif, config: appState.currentConfig, outputSize: viewModel.outputSize)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Color.surface1
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.borderDefault).frame(height: 1)
                        }
                }
        }
    }

    private func updatePreview() {
        viewModel.updatePreview(
            for: appState.selectedPhoto,
            config: appState.currentConfig,
            includeOriginal: showOriginal
        )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    DispatchQueue.main.async {
                        appState.addPhotos(from: [url])
                        if didAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                }
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK {
            appState.addPhotos(from: panel.urls)
        }
    }

    private func navigateFilmstrip(forward: Bool) {
        guard !appState.library.isEmpty else { return }
        let currentID = appState.selectedPhoto?.id
        let currentIndex = currentID.flatMap { id in appState.library.firstIndex(where: { $0.id == id }) }
        let nextIndex: Int
        if let idx = currentIndex {
            nextIndex = forward
                ? min(idx + 1, appState.library.count - 1)
                : max(idx - 1, 0)
        } else {
            nextIndex = 0
        }
        appState.selectedItems = [appState.library[nextIndex].id]
    }

    private func removeSelected() {
        withAnimation {
            appState.library.removeAll { appState.selectedItems.contains($0.id) }
            appState.selectedItems.removeAll()
        }
    }

    // MARK: - Viewport

    private var viewport: some View {
        ZStack {
            Color.surface0
            RadialGradient(
                colors: [Color.accent.opacity(0.02), .clear],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 400
            )

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color.text2)
            } else if let img = showOriginal ? viewModel.originalImage : viewModel.previewImage {
                zoomableImage(img)
            } else {
                emptyState
            }

            zoomOverlay
            errorOverlay

            if isDropTargeted {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(Color.accentDim, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.accentGlow, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHoveringViewport = true
                mouseLocationInViewport = location
            case .ended:
                isHoveringViewport = false
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.artframe")
                .font(.system(size: 48))
                .foregroundStyle(Color.text3)
            Text("No photo selected")
                .font(AppFont.body(16, weight: .medium))
                .foregroundStyle(Color.text2)
            Text("Select a photo from the filmstrip,\nor drag images here")
                .font(AppFont.body(13))
                .foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let err = viewModel.error {
            VStack {
                Spacer()
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(AppFont.body(11))
                    .foregroundStyle(Color.error)
                    .padding(8)
                    .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                    .padding()
            }
        }
    }

    // MARK: - Zoomable Image

    private func zoomableImage(_ img: NSImage) -> some View {
        GeometryReader { geo in
            let size = geo.size
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(32)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                .scaleEffect(zoomState.scale)
                .offset(zoomState.offset)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(panGesture(viewSize: size))
                .gesture(magnifyGesture(viewSize: size))
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        zoomState.toggleFitActual()
                    }
                }
                .contextMenu {
                    Button {
                        for id in appState.selectedItems { appState.rotateItem(id, clockwise: true) }
                    } label: {
                        Label("Rotate Right", systemImage: "rotate.right")
                    }
                    Button {
                        for id in appState.selectedItems { appState.rotateItem(id, clockwise: false) }
                    } label: {
                        Label("Rotate Left", systemImage: "rotate.left")
                    }
                }
                .onAppear {
                    updateFitScale(img: img, viewSize: size)
                }
                .onChange(of: geo.size) { _, newSize in
                    viewportSize = newSize
                    updateFitScale(img: img, viewSize: newSize)
                }
                .onChange(of: img.size.width) { _, _ in
                    updateFitScale(img: img, viewSize: size)
                }
                .onChange(of: img.size.height) { _, _ in
                    updateFitScale(img: img, viewSize: size)
                }
        }
    }

    // MARK: - Zoom Overlay

    @ViewBuilder
    private var zoomOverlay: some View {
        if !zoomState.isAtFit {
            VStack {
                Spacer()
                HStack {
                    Spacer()
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
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Zoom Gestures

    private func magnifyGesture(viewSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / magnifyBase
                zoomState.applyMagnification(delta, anchor: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize: viewSize)
                magnifyBase = value.magnification
            }
            .onEnded { _ in
                magnifyBase = 1.0
                zoomState.clampOffset(imageSize: fittedImageSize(), viewSize: viewSize)
            }
    }

    private func panGesture(viewSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !zoomState.isAtFit else { return }
                if value.translation == .zero {
                    panStartOffset = zoomState.offset
                }
                zoomState.offset = CGSize(
                    width: panStartOffset.width + value.translation.width,
                    height: panStartOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                zoomState.clampOffset(imageSize: fittedImageSize(), viewSize: viewSize)
                panStartOffset = zoomState.offset
            }
    }

    private func updateFitScale(img: NSImage, viewSize: CGSize) {
        let padded = CGSize(width: max(1, viewSize.width - 64), height: max(1, viewSize.height - 64))
        zoomState.updateFitScale(imageSize: img.size, viewSize: padded)
        viewportSize = viewSize
    }

    private var displayedImage: NSImage? {
        showOriginal ? viewModel.originalImage : viewModel.previewImage
    }

    private func fittedImageSize() -> CGSize {
        guard let img = displayedImage else { return .zero }
        let padded = CGSize(width: max(1, viewportSize.width - 64), height: max(1, viewportSize.height - 64))
        let fitW = padded.width / img.size.width
        let fitH = padded.height / img.size.height
        let fit = min(fitW, fitH)
        return CGSize(width: img.size.width * fit, height: img.size.height * fit)
    }

    // MARK: - Scroll Wheel Monitor

    private func installScrollMonitor() {
        // Guard against duplicate registration if onAppear fires multiple times
        if scrollMonitor != nil { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHoveringViewport else { return event }
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.5 else { return event }
            let factor: CGFloat = delta > 0 ? 1.05 : 0.95
            withAnimation(.easeOut(duration: 0.1)) {
                zoomState.zoom(by: factor, anchor: mouseLocationInViewport, viewSize: viewportSize)
            }
            return event // pass through so other UI can still scroll
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }
}

// MARK: - Before/After Toggle

struct BeforeAfterToggle: View {
    @Binding var showOriginal: Bool

    var body: some View {
        HStack(spacing: 0) {
            toggleButton("Before", isActive: showOriginal) {
                showOriginal = true
            }
            toggleButton("After", isActive: !showOriginal) {
                showOriginal = false
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func toggleButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.toggleLabel)
                .textCase(.uppercase)
                .foregroundStyle(isActive ? Color.text0 : Color.text3)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.white.opacity(0.1) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
