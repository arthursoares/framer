import XCTest
import AppKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class SidebarLayoutContainmentTests: XCTestCase {
    func test_overlayLayerControls_fitWithinSidebarShellWidth() {
        assertFitsSidebarWidth(
            OverlayLayerControls(params: OverlayLayerParams()) { _ in },
            name: "OverlayLayerControls"
        )
    }

    func test_lutLayerControls_fitWithinSidebarShellWidth() {
        assertFitsSidebarWidth(
            LUTLayerControls(params: LUTLayerParams()) { _ in }
                .environment(AppState()),
            name: "LUTLayerControls"
        )
    }

    private func assertFitsSidebarWidth<V: View>(
        _ view: V,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let metrics = SidebarMetrics()
        let size = CGSize(width: metrics.idealWidth, height: 420)
        let rootView = view
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height, alignment: .topLeading)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        pumpRunLoop()
        hostingView.layoutSubtreeIfNeeded()

        let overflowFrames = visibleDescendantFrames(in: hostingView)
            .filter { $0.maxX > metrics.idealWidth + 0.5 }

        XCTAssertTrue(
            overflowFrames.isEmpty,
            "\(name) should keep visible content within the \(metrics.idealWidth)pt sidebar shell. Overflow frames: \(overflowFrames)",
            file: file,
            line: line
        )
    }

    private func pumpRunLoop(iterations: Int = 4) {
        for _ in 0..<iterations {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func visibleDescendantFrames(in root: NSView) -> [CGRect] {
        var frames: [CGRect] = []

        func collect(from view: NSView) {
            for subview in view.subviews {
                if !hasClipViewAncestor(subview) {
                    frames.append(subview.convert(subview.bounds, to: root))
                }
                collect(from: subview)
            }
        }

        collect(from: root)
        return frames
    }

    private func hasClipViewAncestor(_ view: NSView) -> Bool {
        var current: NSView? = view.superview
        while let ancestor = current {
            if ancestor is NSClipView {
                return true
            }
            current = ancestor.superview
        }
        return false
    }
}
