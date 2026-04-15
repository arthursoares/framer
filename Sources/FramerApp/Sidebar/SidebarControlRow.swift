import SwiftUI

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
        HStack(alignment: .center, spacing: metrics.controlColumnSpacing) {
            Text(label)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
                .frame(width: metrics.controlLabelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: metrics.controlColumnSpacing) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsTrailingValue {
                    trailingValue
                        .frame(minWidth: metrics.controlTrailingValueWidth, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(stateStyle.foregroundColor)
        }
        .padding(.horizontal, metrics.outerInset)
        .frame(maxWidth: .infinity, minHeight: metrics.controlRowMinHeight, alignment: .leading)
        .opacity(stateStyle.opacity)
    }

    private var showsTrailingValue: Bool {
        TrailingValue.self != EmptyView.self
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
