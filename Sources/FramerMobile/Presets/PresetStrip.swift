import SwiftUI
import FramerCore

struct PresetStrip: View {
    @Environment(AppState.self) var appState
    let cache: PresetPreviewCache

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.presets) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: appState.activePresetName == preset.name,
                        thumbnail: cache.previews[preset.id],
                        onTap: {
                            appState.currentConfig = preset.config
                            appState.activePresetName = preset.name
                            appState.appliedPresetConfig = preset.config
                        }
                    )
                }

                // Save card
                Button {
                    appState.showingSavePresetSheet = true
                } label: {
                    VStack(spacing: 0) {
                        ZStack {
                            Color.surface3
                            Image(systemName: "plus")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.text3)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .strokeBorder(Color.text3, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )

                        Text("Save")
                            .font(AppFont.body(10))
                            .foregroundStyle(Color.text3)
                            .padding(.top, 4)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 90)
    }
}

struct PresetCard: View {
    let preset: Preset
    let isActive: Bool
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    Color.surface3
                    if let thumb = thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(isActive ? Color.accent : .clear, lineWidth: 2)
                )
                .shadow(color: isActive ? Color.accent.opacity(0.25) : .clear, radius: 6)
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color.surface0)
                            }
                            .offset(x: 3, y: -3)
                    }
                }

                Text(preset.name)
                    .font(AppFont.body(10))
                    .foregroundStyle(isActive ? Color.accent : Color.text3)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}
