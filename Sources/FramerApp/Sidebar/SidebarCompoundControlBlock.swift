import SwiftUI

/// Secondary content for `SidebarCompoundControlBlock`. Same result-builder
/// approach as `SidebarControlRowTrailingValueContent` for the same reason:
/// conditional secondary closures (`secondary: { if flag { row } }`) resolve
/// to `_ConditionalContent<Row, EmptyView>` at compile time, which a naive
/// `Secondary == EmptyView` check wouldn't catch — and the block would draw
/// a divider above an empty second row. The `.absent` path tracks runtime
/// presence so the divider + secondary stack render only when there's
/// actual content.
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
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let primary: Primary
    private let secondary: SidebarCompoundControlBlockSecondaryContent

    init(
        metrics: SidebarMetrics? = nil,
        @ViewBuilder primary: () -> Primary,
        @SidebarCompoundControlBlockSecondaryContentBuilder secondary: () -> SidebarCompoundControlBlockSecondaryContent
    ) {
        self.overrideMetrics = metrics
        self.primary = primary()
        self.secondary = secondary()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

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
