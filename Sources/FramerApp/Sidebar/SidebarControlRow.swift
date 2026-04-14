import SwiftUI

private enum SidebarControlRowLayout {
    static let cornerRadius = CornerRadius.lg
    static let labelSpacing = Spacing.sm
    static let contentSpacing = 8.0
    static let verticalPadding = 10.0
    static let trailingValueWidth = 56.0
}

struct SidebarControlRow<Content: View, TrailingValue: View>: View {
    private let label: LocalizedStringKey
    private let metrics: SidebarMetrics
    private let stateStyle: SidebarStateStyle
    private let content: Content
    private let trailingValue: TrailingValue

    init(
        _ label: LocalizedStringKey,
        metrics: SidebarMetrics = SidebarMetrics(),
        stateStyle: SidebarStateStyle = .default,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailingValue: () -> TrailingValue
    ) {
        self.label = label
        self.metrics = metrics
        self.stateStyle = stateStyle
        self.content = content()
        self.trailingValue = trailingValue()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarControlRowLayout.labelSpacing) {
            Text(label)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)

            HStack(alignment: .center, spacing: SidebarControlRowLayout.contentSpacing) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailingValue
                    .frame(minWidth: SidebarControlRowLayout.trailingValueWidth, alignment: .trailing)
            }
            .foregroundStyle(stateStyle.foregroundColor)
        }
        .padding(.horizontal, metrics.outerInset)
        .padding(.vertical, SidebarControlRowLayout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stateStyle.backgroundColor, in: RoundedRectangle(cornerRadius: SidebarControlRowLayout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SidebarControlRowLayout.cornerRadius)
                .stroke(stateStyle.borderColor, lineWidth: 1)
        }
        .opacity(stateStyle.opacity)
    }
}

extension SidebarControlRow where TrailingValue == EmptyView {
    init(
        _ label: LocalizedStringKey,
        metrics: SidebarMetrics = SidebarMetrics(),
        stateStyle: SidebarStateStyle = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label, metrics: metrics, stateStyle: stateStyle, content: content) {
            EmptyView()
        }
    }
}
