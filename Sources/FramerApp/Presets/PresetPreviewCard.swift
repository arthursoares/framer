import SwiftUI
import FramerCore

struct PresetPreviewCard: View {
    let preset: Preset
    let isActive: Bool
    let thumbnail: NSImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Thumbnail area — 4:3 aspect ratio
                ZStack {
                    Color.surface3

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()

                // Label strip
                Text(preset.name)
                    .font(AppFont.templateToken)
                    .foregroundStyle(isActive ? Color.accent : Color.text2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isActive ? Color.accentGlow : Color.surface2)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isActive ? Color.accent : .clear, lineWidth: 2)
            )
            .shadow(color: isActive ? Color.accent.opacity(0.15) : .clear, radius: 6)
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
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
