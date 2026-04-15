import SwiftUI

@MainActor
struct SidebarCompoundControlBlockSecondaryContent {
    private let content: AnyView
    private let isPresent: Bool

    static let absent = SidebarCompoundControlBlockSecondaryContent(
        content: AnyView(EmptyView()),
        isPresent: false
    )

    static func present<Content: View>(_ content: Content) -> SidebarCompoundControlBlockSecondaryContent {
        SidebarCompoundControlBlockSecondaryContent(content: AnyView(content), isPresent: true)
    }

    fileprivate var body: some View {
        content
    }

    fileprivate var hasContent: Bool {
        isPresent
    }
}

@MainActor
@resultBuilder
enum SidebarCompoundControlBlockSecondaryContentBuilder {
    static func buildExpression<Content: View>(_ expression: Content) -> SidebarCompoundControlBlockSecondaryContent {
        SidebarCompoundControlBlockSecondaryContent.present(expression)
    }

    static func buildExpression(_ expression: EmptyView) -> SidebarCompoundControlBlockSecondaryContent {
        .absent
    }

    static func buildOptional(_ component: SidebarCompoundControlBlockSecondaryContent?) -> SidebarCompoundControlBlockSecondaryContent {
        component ?? .absent
    }

    static func buildEither(first component: SidebarCompoundControlBlockSecondaryContent) -> SidebarCompoundControlBlockSecondaryContent {
        component
    }

    static func buildEither(second component: SidebarCompoundControlBlockSecondaryContent) -> SidebarCompoundControlBlockSecondaryContent {
        component
    }

    static func buildBlock(_ component: SidebarCompoundControlBlockSecondaryContent) -> SidebarCompoundControlBlockSecondaryContent {
        component
    }
}

struct SidebarCompoundControlBlock<Primary: View>: View {
    private let metrics: SidebarMetrics
    private let primary: Primary
    private let secondary: SidebarCompoundControlBlockSecondaryContent

    init(
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder primary: () -> Primary,
        @SidebarCompoundControlBlockSecondaryContentBuilder secondary: () -> SidebarCompoundControlBlockSecondaryContent
    ) {
        self.metrics = metrics
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.controlStackSpacing) {
            primary
                .frame(maxWidth: .infinity, alignment: .leading)

            if secondary.hasContent {
                VStack(alignment: .leading, spacing: metrics.controlStackSpacing) {
                    controlDivider
                    secondary.body
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlDivider: some View {
        Rectangle()
            .fill(Color.borderDefault)
            .frame(height: metrics.controlStackDividerThickness)
            .padding(.horizontal, metrics.controlStackDividerInset)
            .accessibilityHidden(true)
    }
}
