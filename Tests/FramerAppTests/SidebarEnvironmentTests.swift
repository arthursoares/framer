import XCTest
import AppKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class SidebarEnvironmentTests: XCTestCase {
    func test_shellMetricsReachDescendants() throws {
        let customPolicy = SidebarLayoutPolicy(
            minimumWidth: 320,
            idealWidth: 400,
            maximumWidth: 520
        )

        var captured: SidebarMetrics?

        let probe = MetricsProbe { captured = $0 }
        let shell = SidebarShell(widthPolicy: customPolicy) {
            probe
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 400, height: 200)

        let host = NSHostingView(rootView: shell)
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let metrics = try XCTUnwrap(captured, "SidebarShell should inject SidebarMetrics into environment")
        XCTAssertEqual(metrics.widthPolicy, customPolicy,
                       "Descendants should read the width policy that SidebarShell applied")
        XCTAssertEqual(metrics.idealWidth, 400)
    }
}

private struct MetricsProbe: View {
    @Environment(\.sidebarMetrics) private var metrics
    let capture: (SidebarMetrics) -> Void

    var body: some View {
        Color.clear
            .onAppear { capture(metrics) }
    }
}
