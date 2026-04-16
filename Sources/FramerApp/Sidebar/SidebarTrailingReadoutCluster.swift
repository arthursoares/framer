import SwiftUI

/// Read-only counterpart to `SidebarTrailingUnitCluster`. Renders a derived or
/// computed `[value][unit]` trailing block using the same field / suffix widths
/// so editable rows and read-only readouts occupy an identical trailing column
/// and adjacent labels stay aligned.
struct SidebarTrailingReadoutCluster<Content: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let unit: LocalizedStringKey
    private let content: Content

    init(
        unit: LocalizedStringKey = "",
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.overrideMetrics = metrics
        self.unit = unit
        self.content = content()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.controlTrailingClusterSpacing) {
            content
                .frame(width: metrics.controlReadoutWidth, alignment: .trailing)

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
