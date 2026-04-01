import XCTest
@testable import FramerCore

final class LUTProviderTests: XCTestCase {
    private var importedURL: URL?

    override func tearDown() {
        if let importedURL {
            try? FileManager.default.removeItem(at: importedURL)
        }
        LUTProvider.clearThumbnailCache()
        LUTProvider.invalidateCache()
        super.tearDown()
    }

    func test_importLUT_replacingSameFilenameRefreshesLoadedData() throws {
        let lutName = "lut-provider-cache-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(lutName).cube")

        try makeCube(low: 0.1, high: 0.9).write(to: sourceURL, atomically: true, encoding: .utf8)
        let info = try LUTProvider.importLUT(from: sourceURL)
        importedURL = LUTProvider.userLUTDirectory()?.appendingPathComponent("\(lutName).cube")

        let first = try XCTUnwrap(LUTProvider.loadLUT(named: info.id))
        XCTAssertEqual(first.data[0], 0.1, accuracy: 0.0001)

        try makeCube(low: 0.6, high: 0.95).write(to: sourceURL, atomically: true, encoding: .utf8)
        _ = try LUTProvider.importLUT(from: sourceURL)

        let second = try XCTUnwrap(LUTProvider.loadLUT(named: info.id))
        XCTAssertEqual(second.data[0], 0.6, accuracy: 0.0001)
    }

    private func makeCube(low: Float, high: Float) -> String {
        """
        LUT_3D_SIZE 2
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        """
    }
}
