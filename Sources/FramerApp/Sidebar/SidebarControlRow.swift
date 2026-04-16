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

/// Trailing-value content for `SidebarControlRow`. A small hand-rolled
/// result-builder type (rather than a plain `View` generic) so the row can
/// distinguish "no trailing content at all" from "trailing content wrapped
/// in a conditional that currently renders EmptyView".
///
/// Without this distinction, `secondary: { if jpegQuality != nil { row } }`
/// resolves to `_ConditionalContent<Row, EmptyView>` — a non-EmptyView type
/// that wouldn't be caught by a compile-time `TrailingValue == EmptyView`
/// check, and the row would reserve trailing space + flip content alignment
/// even when the conditional's false branch was active. The builder's
/// `.absent` case tracks absence at runtime so the layout decisions stay
/// correct in both unconditional and conditional trailing closures.
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
                    // Hard-clip content to its frame so macOS NSSlider (the
                    // AppKit control backing SwiftUI's Slider) can't render
                    // its track/knob into the trailing field's area. Without
                    // clipping, the NSSlider rasteriser draws a few extra
                    // pixels of track past the layout frame at every value,
                    // which combined with the 10pt HStack gap produces the
                    // visible overlap users reported on narrow sidebars.
                    .clipShape(Rectangle())
                    // Additional breathing room between the content frame and
                    // the trailing cluster's rounded field. A full
                    // `controlColumnSpacing` buffer plus the existing HStack
                    // spacing gives ~20pt of empty space — enough that even if
                    // the slider track does leak a pixel or two past
                    // clip-shape (AppKit can still bleed layer-level
                    // rasterisation in some edge cases), the user never sees
                    // a visual overlap with the field.
                    .padding(.trailing, trailingValue.hasContent ? metrics.controlColumnSpacing : 0)

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
