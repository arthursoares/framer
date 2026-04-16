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

@MainActor
struct SidebarControlRowTrailingValueContent {
    private let content: AnyView
    private let isPresent: Bool

    static let absent = SidebarControlRowTrailingValueContent(content: AnyView(EmptyView()), isPresent: false)

    static func present<Content: View>(_ content: Content) -> SidebarControlRowTrailingValueContent {
        SidebarControlRowTrailingValueContent(content: AnyView(content), isPresent: true)
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
enum SidebarControlRowTrailingValueContentBuilder {
    static func buildExpression<Content: View>(_ expression: Content) -> SidebarControlRowTrailingValueContent {
        SidebarControlRowTrailingValueContent.present(expression)
    }

    static func buildExpression(_ expression: EmptyView) -> SidebarControlRowTrailingValueContent {
        .absent
    }

    static func buildOptional(_ component: SidebarControlRowTrailingValueContent?) -> SidebarControlRowTrailingValueContent {
        component ?? .absent
    }

    static func buildEither(first component: SidebarControlRowTrailingValueContent) -> SidebarControlRowTrailingValueContent {
        component
    }

    static func buildEither(second component: SidebarControlRowTrailingValueContent) -> SidebarControlRowTrailingValueContent {
        component
    }

    static func buildBlock(_ component: SidebarControlRowTrailingValueContent) -> SidebarControlRowTrailingValueContent {
        component
    }
}

struct SidebarControlRow<Content: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    @Namespace private var accessibilityLabelNamespace
    private let label: LocalizedStringKey
    private let overrideMetrics: SidebarMetrics?
    private let style: SidebarControlRowStyle
    private let content: Content
    private let trailingValue: SidebarControlRowTrailingValueContent

    init(
        _ label: LocalizedStringKey,
        metrics: SidebarMetrics? = nil,
        style: SidebarControlRowStyle = .default,
        @ViewBuilder content: () -> Content,
        @SidebarControlRowTrailingValueContentBuilder trailingValue: () -> SidebarControlRowTrailingValueContent
    ) {
        self.label = label
        self.overrideMetrics = metrics
        self.style = style
        self.content = content()
        self.trailingValue = trailingValue()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.controlColumnSpacing) {
            Text(label)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
                .frame(width: metrics.controlLabelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabeledPair(role: .label, id: "SidebarControlRowLabel", in: accessibilityLabelNamespace)

            HStack(alignment: .center, spacing: metrics.controlColumnSpacing) {
                content
                    .frame(maxWidth: .infinity, alignment: trailingValue.hasContent ? .trailing : .leading)
                    // Buffer against the trailing cluster. macOS NSSlider (used
                    // by SwiftUI's Slider) renders its track and knob to the
                    // very edge of its layout frame — at extreme values the
                    // knob overlaps any view 10pt away. A few extra pt keep
                    // the slider's hit-area and glyph away from the trailing
                    // field's rounded rectangle. No effect on EmptyView / Toggle
                    // / Picker content, which already render within their
                    // intrinsic bounds.
                    .padding(.trailing, trailingValue.hasContent ? metrics.controlTrailingClusterSpacing : 0)

                if trailingValue.hasContent {
                    trailingValue.body
                        .frame(minWidth: metrics.controlTrailingValueWidth, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .foregroundStyle(style.foregroundColor)
            .accessibilityLabeledPair(role: .content, id: "SidebarControlRowLabel", in: accessibilityLabelNamespace)
        }
        .padding(.horizontal, metrics.outerInset)
        .frame(maxWidth: .infinity, minHeight: metrics.controlRowMinHeight, alignment: .leading)
        .opacity(style.opacity)
    }
}

extension SidebarControlRow {
    init(
        _ label: LocalizedStringKey,
        metrics: SidebarMetrics? = nil,
        style: SidebarControlRowStyle = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label, metrics: metrics, style: style, content: content) {
            EmptyView()
        }
    }
}
