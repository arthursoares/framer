import SwiftUI

struct SidebarSection<Header: View, Content: View>: View {
    private let metrics: SidebarMetrics
    private let header: Header
    private let content: Content

    init(
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.metrics = metrics
        self.header = header()
        self.content = content()
    }

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
        metrics: SidebarMetrics = SidebarMetrics(),
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
