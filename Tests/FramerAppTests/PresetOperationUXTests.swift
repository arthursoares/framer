import XCTest
import FramerCore
@testable import Framer

@MainActor
final class PresetOperationUXTests: XCTestCase {
    func test_failedSaveDoesNotActivateOrRefreshPreset() throws {
        let state = AppState(presetStore: failingStore(), initializeDefaults: false)
        let existing = Preset(name: "Existing", config: .default)
        state.presets = [existing]
        state.activePresetName = existing.name
        state.appliedPresetConfig = existing.config

        XCTAssertFalse(state.saveCurrentPreset(named: "New look"))

        XCTAssertEqual(state.presets, [existing])
        XCTAssertEqual(state.activePresetName, existing.name)
        XCTAssertEqual(state.appliedPresetConfig, existing.config)
        XCTAssertEqual(state.presetOperationAlert?.title, "Preset Not Saved")
    }

    func test_invalidAndDuplicateNamesExplainWhyTheyCannotBeSaved() throws {
        let directory = try temporaryDirectory()
        let state = AppState(
            presetStore: PresetStore(directory: directory),
            initializeDefaults: false
        )
        state.presets = [Preset(name: "Soft Glow", config: .default)]

        XCTAssertEqual(state.presetNameProblem("   "), "Enter a preset name.")
        XCTAssertEqual(
            state.presetNameProblem(" soft glow "),
            "A preset named “Soft Glow” already exists."
        )
        XCTAssertFalse(state.saveCurrentPreset(named: " soft glow "))
        XCTAssertEqual(state.presetOperationAlert?.title, "Choose Another Name")
    }

    func test_failedRenameDeleteAndUpdatePreserveVisibleState() {
        let state = AppState(presetStore: failingStore(), initializeDefaults: false)
        let preset = Preset(name: "Keep Me", config: .default)
        state.presets = [preset]
        state.activePresetName = preset.name
        state.appliedPresetConfig = preset.config

        XCTAssertFalse(state.renamePreset(preset, to: "Renamed"))
        XCTAssertEqual(state.presets, [preset])
        XCTAssertEqual(state.activePresetName, preset.name)

        XCTAssertFalse(state.updatePreset(preset))
        XCTAssertEqual(state.appliedPresetConfig, preset.config)

        XCTAssertFalse(state.deletePreset(preset))
        XCTAssertEqual(state.presets, [preset])
        XCTAssertEqual(state.activePresetName, preset.name)
    }

    func test_partialImportReportsFailuresAndDoesNotChangeActivePreset() throws {
        let directory = try temporaryDirectory()
        let store = PresetStore(directory: directory)
        let state = AppState(presetStore: store, initializeDefaults: false)
        let active = Preset(name: "Active", config: .default)
        state.activePresetName = active.name
        state.appliedPresetConfig = active.config

        let imported = Preset(name: "Imported", config: .default)
        let validURL = directory.appendingPathComponent("valid.json")
        let invalidURL = directory.appendingPathComponent("invalid.json")
        try JSONEncoder().encode(imported).write(to: validURL)
        try Data("not json".utf8).write(to: invalidURL)

        state.importPresets(from: [validURL, invalidURL])

        XCTAssertEqual(state.presets.map(\.id), [imported.id])
        XCTAssertEqual(state.activePresetName, active.name)
        XCTAssertEqual(state.appliedPresetConfig, active.config)
        XCTAssertEqual(state.presetOperationAlert?.title, "Some Presets Weren’t Imported")
        XCTAssertEqual(state.presetOperationAlert?.message, "Imported 1 preset. 1 file couldn’t be imported.")
    }

    func test_arrayImportRefreshesSuccessfulPresetsWhenLaterPresetCannotBeSaved() throws {
        let root = try temporaryDirectory()
        let storeDirectory = root.appendingPathComponent("presets")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let first = Preset(name: "First", config: .default)
        let second = Preset(name: "Second", config: .default)
        try FileManager.default.createDirectory(
            at: storeDirectory.appendingPathComponent("\(second.id.uuidString).json"),
            withIntermediateDirectories: true
        )
        let importURL = root.appendingPathComponent("batch.json")
        try JSONEncoder().encode([first, second]).write(to: importURL)
        let state = AppState(
            presetStore: PresetStore(directory: storeDirectory),
            initializeDefaults: false
        )

        state.importPresets(from: [importURL])

        XCTAssertEqual(state.presets.map(\.id), [first.id])
        XCTAssertEqual(state.presetOperationAlert?.title, "Some Presets Weren’t Imported")
        XCTAssertEqual(state.presetOperationAlert?.message, "Imported 1 preset. 1 preset couldn’t be imported.")
    }

    private func failingStore() -> PresetStore {
        PresetStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
