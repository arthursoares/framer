import XCTest
import AppKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class DesktopInteractionUXTests: XCTestCase {
    func test_queuedExportsAreNotAnnouncedAsFinished() {
        let state = AppState()
        state.exportQueue = [ExportJob(items: [], config: .default, outputDirectory: URL(fileURLWithPath: "/tmp"))]
        let host = NSHostingView(rootView: ExportBar().environment(state))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 350, height: 70),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let queueButton = accessibilityElements(host).first {
            accessibilityValue($0, "accessibilityLabel") as? String == "Show export queue"
        }
        XCTAssertNotNil(queueButton)
        if let queueButton {
            XCTAssertEqual(accessibilityValue(queueButton, "accessibilityValue") as? String, "Exports waiting to start")
        }
    }

    func test_formatRowExposesItsButtonsToAccessibility() {
        let host = NSHostingView(rootView: SidebarControlRow("Format") {
            FormatPicker(selection: .constant("jpeg"))
        })
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 350, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let buttons = accessibilityElements(host).filter { accessibilityValue($0, "accessibilityRole") as? String == "AXButton" }
        let labels = buttons.compactMap {
            (accessibilityValue($0, "accessibilityLabel") ?? accessibilityValue($0, "accessibilityTitle")) as? String
        }
        XCTAssertTrue(labels.contains("JPEG"), "Missing JPEG button: \(labels)")
        XCTAssertTrue(labels.contains("PNG"), "Missing PNG button: \(labels)")
    }

    // SwiftUI nodes expose the informal ObjC accessibility selectors without
    // necessarily declaring conformance to the full NSAccessibility protocol.
    private func accessibilityElements(_ element: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 20 else { return [] }
        let children = accessibilityValue(element, "accessibilityChildren") as? [NSObject] ?? []
        return [element] + children.flatMap { accessibilityElements($0, depth: depth + 1) }
    }

    private func accessibilityValue(_ element: NSObject, _ name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    func test_clearFinishedExportsRetainsOnlyActiveJobs() {
        let state = AppState()
        let photo = PhotoItem(url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        let statuses: [ExportJob.JobStatus] = [.queued, .done, .failed("Could not write the photo"), .running, .cancelled]
        state.exportQueue = statuses.map { status in
            var job = ExportJob(items: [photo], config: .default, outputDirectory: URL(fileURLWithPath: "/tmp"))
            job.status = status
            return job
        }
        let activeIDs = [state.exportQueue[0].id, state.exportQueue[3].id]

        state.clearFinishedExports()

        XCTAssertEqual(state.exportQueue.map(\.id), activeIDs)
        XCTAssertEqual(state.exportQueue.map(\.status), [.queued, .running])
    }
}
