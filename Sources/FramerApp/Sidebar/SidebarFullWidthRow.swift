import SwiftUI

/// Row shape for content that can't fit the 3-column label/control/trailing
/// grid — preview images, thumbnail strips, chip flows, palette editors, etc.
/// Renders a compact title above the content and constrains the content to
/// `metrics.containedPreviewMaxWidth` so it never overflows the sidebar shell.
///
/// Promoted from the private `OverlayFullWidthControlRow` that lived inside
/// `LayerListSection.swift`; that usage was the first call site.
struct SidebarFullWidthRow<Content: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let title: LocalizedStringKey
    private let content: Content

    @Namespace private var accessibilityLabelNamespace

    init(
        _ title: LocalizedStringKey,
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.overrideMetrics = metrics
        self.content = content()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset / 2) {
            Text(title)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
                .accessibilityLabeledPair(role: .label, id: "SidebarFullWidthRowLabel", in: accessibilityLabelNamespace)

            content
                .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
                .accessibilityLabeledPair(role: .content, id: "SidebarFullWidthRowLabel", in: accessibilityLabelNamespace)
        }
        .padding(.horizontal, metrics.outerInset)
        .padding(.vertical, metrics.expandedBodyInset / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
