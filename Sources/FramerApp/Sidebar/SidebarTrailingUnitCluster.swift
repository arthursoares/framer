import SwiftUI

struct SidebarTrailingUnitCluster<Field: View>: View {
    private let metrics: SidebarMetrics
    private let unit: LocalizedStringKey
    private let field: Field

    init(
        unit: LocalizedStringKey,
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder field: () -> Field
    ) {
        self.metrics = metrics
        self.unit = unit
        self.field = field()
    }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.controlTrailingClusterSpacing) {
            field
                .frame(width: metrics.controlValueFieldWidth, alignment: .trailing)

            Text(unit)
                .font(AppFont.mono(9))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlUnitSuffixWidth, alignment: .leading)
        }
        .frame(
            minWidth: metrics.controlTrailingValueWidth + metrics.controlUnitSuffixWidth,
            alignment: .trailing
        )
    }
}
