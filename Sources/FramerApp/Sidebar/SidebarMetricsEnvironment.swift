import SwiftUI

/// Environment key for propagating `SidebarMetrics` from `SidebarShell` down
/// into every descendant primitive and editor. Primitives default to reading
/// this value instead of each one constructing its own `SidebarMetrics()`, so
/// a shell-level override (e.g. a custom width policy) reaches descendants
/// instead of getting dropped on the floor.
private struct SidebarMetricsKey: EnvironmentKey {
    static let defaultValue = SidebarMetrics()
}

extension EnvironmentValues {
    var sidebarMetrics: SidebarMetrics {
        get { self[SidebarMetricsKey.self] }
        set { self[SidebarMetricsKey.self] = newValue }
    }
}
