import XCTest

final class FramerMobileUITests: XCTestCase {
    func test_shareAllProcessed_writesFilesToInjectedDirectory() throws {
        let app = XCUIApplication()
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/E2EFixtures/input")
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("framer-ios-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        app.launchEnvironment["FRAMER_E2E_MODE"] = "1"
        app.launchEnvironment["FRAMER_E2E_FIXTURE_DIR"] = fixtures.path
        app.launchEnvironment["FRAMER_E2E_EXPORT_DIR"] = exportDir.path
        app.launch()

        app.buttons["toolbar.share"].tap()
        app.buttons["Share All Processed"].tap()

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("sample-1_framed.jpg").path))
    }
}
