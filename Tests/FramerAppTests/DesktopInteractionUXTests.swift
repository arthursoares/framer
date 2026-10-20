import XCTest
import AppKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class DesktopInteractionUXTests: XCTestCase {
    func test_exportDestinationsAvoidSameNameInputsAndExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = directory.appendingPathComponent("Photo_framed.jpg")
        try Data("original export".utf8).write(to: existing)
        let items = [
            PhotoItem(url: URL(fileURLWithPath: "/first/Photo.jpg")),
            PhotoItem(url: URL(fileURLWithPath: "/second/photo.png")),
            PhotoItem(url: URL(fileURLWithPath: "/third/Photo.tif")),
        ]

        let destinations = try AppState.plannedOutputURLs(
            for: items, config: .default, directory: directory, suffix: "framed"
        )

        XCTAssertEqual(destinations.map(\.lastPathComponent), [
            "Photo_framed_2.jpg", "photo_framed_3.jpg", "Photo_framed_4.jpg",
        ])
        XCTAssertEqual(try Data(contentsOf: existing), Data("original export".utf8))
    }

    func test_exportDestinationsRespectOtherRunningJobs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = PhotoItem(url: URL(fileURLWithPath: "/first/photo.jpg"))

        let first = try AppState.plannedOutputURLs(
            for: [item], config: .default, directory: directory, suffix: "framed"
        )
        let second = try AppState.plannedOutputURLs(
            for: [item], config: .default, directory: directory, suffix: "framed",
            reservedPaths: Set(first.map { $0.standardizedFileURL.path.lowercased() })
        )

        XCTAssertEqual(first.first?.lastPathComponent, "photo_framed.jpg")
        XCTAssertEqual(second.first?.lastPathComponent, "photo_framed_2.jpg")
    }

    func test_arrowNavigationUsesFocusedPhotoAndStopsAtFilmstripEnds() {
        let state = AppState()
        let photos = (0..<3).map { PhotoItem(url: URL(fileURLWithPath: "/tmp/photo-\($0).jpg")) }
        state.library = photos
        state.selectedItems = [photos[0].id, photos[2].id]

        XCTAssertEqual(state.selectAdjacentPhoto(forward: true, from: photos[2].id), photos[2].id)
        XCTAssertEqual(state.selectedItems, [photos[2].id])
        XCTAssertEqual(state.selectAdjacentPhoto(forward: false), photos[1].id)
        XCTAssertEqual(state.selectedItems, [photos[1].id])
        XCTAssertEqual(state.selectAdjacentPhoto(forward: false), photos[0].id)
        XCTAssertEqual(state.selectAdjacentPhoto(forward: false), photos[0].id)

        state.selectedItems = []
        XCTAssertEqual(state.selectAdjacentPhoto(forward: true, from: photos[1].id), photos[2].id,
                       "Deselecting a focused thumbnail should still navigate from its position")
        state.selectedItems = []
        XCTAssertEqual(state.selectAdjacentPhoto(forward: true), photos[0].id)
    }

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
