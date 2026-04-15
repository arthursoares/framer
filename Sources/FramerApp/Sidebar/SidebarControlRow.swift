import SwiftUI

struct SidebarControlRowStyle: Sendable, Equatable {
    let foreground: SidebarStateStyle.Foreground
    let opacity: Double

    static let `default` = SidebarControlRowStyle(foreground: .primary, opacity: 1)
    static let disabled = SidebarControlRowStyle(foreground: .secondary, opacity: SidebarStateStyle.disabled.opacity)
    static let accent = SidebarControlRowStyle(foreground: .accent, opacity: 1)

    var foregroundColor: Color {
        switch foreground {
        case .primary:
            .text0
        case .secondary:
            .text2
        case .accent:
            .accent
        }
    }
}

struct SidebarControlRow<Content: View, TrailingValue: View>: View {
    private let label: LocalizedStringKey
    private let metrics: SidebarMetrics
    private let style: SidebarControlRowStyle
    private let content: Content
    private let trailingValue: TrailingValue

    init(
        _ label: LocalizedStringKey,
        metrics: SidebarMetrics = SidebarMetrics(),
        style: SidebarControlRowStyle = .default,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailingValue: () -> TrailingValue
    ) {
        self.label = label
        self.metrics = metrics
        self.style = style
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
            .foregroundStyle(style.foregroundColor)
        }
        .padding(.horizontal, metrics.outerInset)
        .frame(maxWidth: .infinity, minHeight: metrics.controlRowMinHeight, alignment: .leading)
        .opacity(style.opacity)
    }

    private var showsTrailingValue: Bool {
        TrailingValue.self != EmptyView.self
    }
}

extension SidebarControlRow where TrailingValue == EmptyView {
    init(
        _ label: LocalizedStringKey,
        metrics: SidebarMetrics = SidebarMetrics(),
        style: SidebarControlRowStyle = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label, metrics: metrics, style: style, content: content) {
            EmptyView()
        }
    }
}
