import SwiftUI

struct SidebarSection<Header: View, Content: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let header: Header
    private let content: Content

    init(
        metrics: SidebarMetrics? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.overrideMetrics = metrics
        self.header = header()
        self.content = content()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SidebarSection where Header == Text {
    init(
        _ title: LocalizedStringKey,
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(metrics: metrics, header: {
            Text(title)
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)
        }, content: content)
    }
}

/// Header-less convenience: `SidebarSection(metrics: ...) { content }`. Used
/// by the Layers section in `InspectorView` which owns its own header row
/// inside `LayerListSection` rather than the section eyebrow.
extension SidebarSection where Header == EmptyView {
    init(
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(metrics: metrics, header: { EmptyView() }, content: content)
    }
}
