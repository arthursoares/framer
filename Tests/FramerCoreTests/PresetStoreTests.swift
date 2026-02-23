import XCTest
@testable import FramerCore

final class PresetStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer_preset_test_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_saveAndLoad_preset() throws {
        let store = PresetStore(directory: tempDir)
        let preset = Preset(name: "My Preset", config: .default)
        try store.save(preset)

        let loaded = try store.load(id: preset.id)
        XCTAssertEqual(loaded.name, preset.name)
        XCTAssertEqual(loaded.config.borderStyle, preset.config.borderStyle)
    }

    func test_listPresets_returnsAll() throws {
        let store = PresetStore(directory: tempDir)
        let p1 = Preset(name: "A", config: .default)
        let p2 = Preset(name: "B", config: .default)
        try store.save(p1)
        try store.save(p2)

        let all = try store.list()
        XCTAssertEqual(all.count, 2)
    }

    func test_deletePreset_removesIt() throws {
        let store = PresetStore(directory: tempDir)
        let preset = Preset(name: "Delete Me", config: .default)
        try store.save(preset)
        try store.delete(id: preset.id)

        XCTAssertThrowsError(try store.load(id: preset.id))
    }

    func test_yamlConfig_roundtrips() throws {
        let config = ProcessingConfig.default
        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)
        XCTAssertEqual(config.borderStyle, decoded.borderStyle)
        XCTAssertEqual(config.padding, decoded.padding)
    }
}
