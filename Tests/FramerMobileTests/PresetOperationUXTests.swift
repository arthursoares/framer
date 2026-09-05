import XCTest
import FramerCore
@testable import FramerMobile

@MainActor
final class PresetOperationUXTests: XCTestCase {
    func test_failedSaveDoesNotActivateOrRefreshPreset() {
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

    func test_duplicateRenameIsRejectedWithoutChangingActiveName() {
        let state = AppState(presetStore: failingStore(), initializeDefaults: false)
        let first = Preset(name: "First", config: .default)
        let second = Preset(name: "Second", config: .default)
        state.presets = [first, second]
        state.activePresetName = first.name

        XCTAssertEqual(
            state.presetNameProblem(" second ", excluding: first.id),
            "A preset named “Second” already exists."
        )
        XCTAssertFalse(state.renamePreset(first, to: " second "))
        XCTAssertEqual(state.activePresetName, first.name)
        XCTAssertEqual(state.presets, [first, second])
        XCTAssertEqual(state.presetOperationAlert?.title, "Choose Another Name")
    }

    func test_safeExportFilenameCannotEscapeTemporaryDirectory() {
        let filename = AppState.safePresetFilename(for: "../../ Night / Film ")

        XCTAssertEqual(filename, "Night_Film.json")
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(".."))
    }

    func test_allFailedImportsReportFailureWithoutChangingActivePreset() throws {
        let directory = try temporaryDirectory()
        let state = AppState(
            presetStore: PresetStore(directory: directory),
            initializeDefaults: false
        )
        state.activePresetName = "Still Active"
        let invalidURL = directory.appendingPathComponent("invalid.json")
        try Data("not json".utf8).write(to: invalidURL)

        state.importPresets(from: [invalidURL])

        XCTAssertTrue(state.presets.isEmpty)
        XCTAssertEqual(state.activePresetName, "Still Active")
        XCTAssertEqual(state.presetOperationAlert?.title, "Presets Not Imported")
        XCTAssertEqual(state.presetOperationAlert?.message, "The selected file couldn’t be imported.")
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
