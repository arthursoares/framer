import XCTest
@testable import FramerCore

final class UserPaletteStoreTests: XCTestCase {
    func test_missingFileStartsEmptyAndSavedPaletteRoundTrips() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = UserPaletteStore(fileURL: file)
        let palette = UserPalette(name: "Two Colors", colors: [.black, .white])

        XCTAssertEqual(try store.list(), [])
        try store.save(palette)
        XCTAssertEqual(try store.list(), [palette])
    }

    func test_unreadablePaletteFileIsPreservedBySaveAndDelete() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("{unfinished".utf8)
        try original.write(to: file)
        let store = UserPaletteStore(fileURL: file)

        XCTAssertThrowsError(try store.list())
        XCTAssertThrowsError(try store.save(UserPalette(name: "New", colors: [.white])))
        XCTAssertThrowsError(try store.delete(id: UUID()))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("framer-palettes-\(UUID().uuidString).json")
    }
}
