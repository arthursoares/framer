import SwiftUI

struct SidebarCompoundControlBlock<Primary: View, Secondary: View>: View {
    private let metrics: SidebarMetrics
    private let primary: Primary
    private let secondary: Secondary

    init(
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.metrics = metrics
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            primary
                .frame(maxWidth: .infinity, alignment: .leading)

            secondary
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
