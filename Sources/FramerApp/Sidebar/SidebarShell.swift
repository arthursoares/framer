import SwiftUI

struct SidebarShell<Content: View, Footer: View>: View {
    private let metrics: SidebarMetrics
    private let content: Content
    private let footer: Footer

    init(
        widthPolicy: SidebarLayoutPolicy = .default,
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.metrics = metrics.replacing(widthPolicy: widthPolicy)
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.rowGap) {
                content
            }
            .padding(metrics.outerInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            minWidth: metrics.minimumWidth,
            idealWidth: metrics.idealWidth,
            maxWidth: metrics.maximumWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .safeAreaInset(edge: .bottom, spacing: metrics.footerSpacing) {
            footer
        }
        .background(Color.surface1)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.borderDefault)
                .frame(width: 1)
        }
    }
}

extension SidebarShell where Footer == EmptyView {
    init(
        widthPolicy: SidebarLayoutPolicy = .default,
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder content: () -> Content
    ) {
        self.init(widthPolicy: widthPolicy, metrics: metrics, content: content) {
            EmptyView()
        }
    }
}
