import SwiftUI
import FramerCore

struct LayerDetailView: View {
    @Environment(AppState.self) var appState
    @Binding var layer: CompositionLayer
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var miniPreview: UIImage?
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Mini live preview
                ZStack {
                    Color.surface1
                    if let miniPreview {
                        Image(uiImage: miniPreview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    } else if appState.selectedPhoto != nil {
                        ProgressView()
                            .tint(Color.text3)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .padding(.horizontal, 16)

                // Layer header
                HStack(spacing: 12) {
                    Image(systemName: layer.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accent)
                        .frame(width: 36, height: 36)
                        .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                        .accessibilityHidden(true)

                    Text(layer.label)
                        .font(AppFont.body(22, weight: .bold))
                        .foregroundStyle(Color.text0)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    LayerVisibilityButton(
                        layerName: layer.label,
                        isEnabled: layer.isEnabled,
                        action: { layer.isEnabled.toggle() }
                    )
                    .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                }
                .padding(.horizontal, 16)

                // Layer-specific controls
                layerControls
                    .padding(.horizontal, 16)
                    .opacity(layer.isEnabled ? 1.0 : 0.55)
                    .allowsHitTesting(layer.isEnabled)

                Spacer(minLength: 20)

                // Delete button
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Text("Delete Layer")
                        .font(AppFont.buttonText)
                        .foregroundStyle(Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                }
                .padding(.horizontal, 16)
                .accessibilityLabel("Delete \(layer.label) layer")
                .accessibilityHint("Removes this layer. You can undo this action.")
            }
            .padding(.vertical, 16)
        }
        .background(Color.surface0)
        .navigationTitle(layer.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.surface1, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .foregroundStyle(Color.text1)
        .tint(Color.accent)
        .onChange(of: layer) { _, _ in updateMiniPreview() }
        .onAppear { updateMiniPreview() }
    }

    private func updateMiniPreview() {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let photo = appState.selectedPhoto else { return }
            let processor = FrameProcessor()
            let url = photo.url
            let config = appState.currentConfig
            let rotation = photo.rotation
            let compactPreviewMaxDimension = 320
            do {
                let cgImage = try await Task.detached {
                    try await processor.previewCGImage(
                        for: url,
                        config: config,
                        rotation: rotation,
                        maxDimension: compactPreviewMaxDimension
                    )
                }.value
                guard !Task.isCancelled else { return }
                miniPreview = UIImage(cgImage: cgImage)
            } catch { }
        }
    }

    @ViewBuilder
    private var layerControls: some View {
        switch layer {
        case .border(let params):
            BorderControls(params: params) { layer = .border($0) }
        case .padding(let params):
            PaddingControls(params: params) { layer = .padding($0) }
        case .canvas(let params):
            CanvasControls(params: params) { layer = .canvas($0) }
        case .resize(let params):
            ResizeControls(params: params) { layer = .resize($0) }
        case .aspectRatio(let params):
            AspectRatioControls(params: params) { layer = .aspectRatio($0) }
        case .orientation(let params):
            OrientationControls(params: params) { layer = .orientation($0) }
        case .caption(let params):
            CaptionControls(params: params) { layer = .caption($0) }
        case .dither(let params):
            DitherControls(params: params) { layer = .dither($0) }
        case .overlay(let params):
            OverlayControls(params: params) { layer = .overlay($0) }
        case .lut(let params):
            LUTControls(params: params) { layer = .lut($0) }
        case .shader(let params):
            ShaderControls(params: params) { layer = .shader($0) }
        case .gpuEffect(let params):
            GPUEffectControls(params: params) { layer = .gpuEffect($0) }
        }
    }
}
