import SwiftUI

struct SidebarTrailingUnitCluster<Field: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let unit: LocalizedStringKey
    private let field: Field

    init(
        unit: LocalizedStringKey,
        metrics: SidebarMetrics? = nil,
        @ViewBuilder field: () -> Field
    ) {
        self.overrideMetrics = metrics
        self.unit = unit
        self.field = field()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

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
