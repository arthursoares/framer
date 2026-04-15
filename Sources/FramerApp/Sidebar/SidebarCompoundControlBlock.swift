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
        VStack(alignment: .leading, spacing: metrics.controlStackSpacing) {
            primary
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsSecondary {
                VStack(alignment: .leading, spacing: metrics.controlStackSpacing) {
                    controlDivider
                    secondary
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsSecondary: Bool {
        Secondary.self != EmptyView.self
    }

    private var controlDivider: some View {
        Rectangle()
            .fill(Color.borderDefault)
            .frame(height: metrics.controlStackDividerThickness)
            .padding(.horizontal, metrics.controlStackDividerInset)
            .accessibilityHidden(true)
    }
}
