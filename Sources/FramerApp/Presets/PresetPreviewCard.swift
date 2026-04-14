import SwiftUI
import FramerCore

private enum PresetPreviewCardLayout {
    static let cornerRadius = CornerRadius.lg
    static let thumbnailCornerRadius = CornerRadius.md
}

struct PresetPreviewCard: View {
    let preset: Preset
    let isActive: Bool
    let thumbnail: NSImage?
    let onTap: () -> Void

    private let metrics = SidebarMetrics()

    private var stateStyle: SidebarStateStyle {
        isActive ? .selectedCurrent : .hover
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
                ZStack {
                    Color.surface3

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: PresetPreviewCardLayout.thumbnailCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: PresetPreviewCardLayout.thumbnailCornerRadius)
                        .stroke(Color.borderDefault, lineWidth: 1)
                }

                HStack(spacing: Spacing.sm) {
                    Text(preset.name)
                        .font(AppFont.templateToken)
                        .foregroundStyle(isActive ? Color.accent : Color.text1)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                }
            }
            .padding(metrics.expandedBodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stateStyle.backgroundColor, in: RoundedRectangle(cornerRadius: PresetPreviewCardLayout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PresetPreviewCardLayout.cornerRadius)
                    .stroke(stateStyle.borderColor, lineWidth: 1)
            }
            .opacity(stateStyle.opacity)
        }
        .buttonStyle(.plain)
    }
}
