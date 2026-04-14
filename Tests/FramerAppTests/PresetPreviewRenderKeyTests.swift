import XCTest
import FramerCore
@testable import Framer

final class PresetPreviewRenderKeyTests: XCTestCase {
    func test_changesWhenSelectedPhotoChanges() {
        let preset = Preset(name: "Balanced", config: .default)
        let photoA = UUID()
        let photoB = UUID()

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: photoA, presets: [preset]),
            PresetPreviewRenderKey(photoID: photoB, presets: [preset])
        )
    }

    func test_changesWhenPresetConfigurationChanges() {
        let presetID = UUID()
        let original = Preset(id: presetID, name: "Balanced", config: .default)
        var updatedConfig = ProcessingConfig.default
        updatedConfig.outputFormat = .png
        let updated = Preset(id: presetID, name: "Balanced", config: updatedConfig)

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: UUID(), presets: [original]),
            PresetPreviewRenderKey(photoID: UUID(), presets: [updated])
        )
    }

    func test_changesWhenPresetNameChanges() {
        let presetID = UUID()
        let original = Preset(id: presetID, name: "Balanced", config: .default)
        let renamed = Preset(id: presetID, name: "Editorial", config: .default)

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: UUID(), presets: [original]),
            PresetPreviewRenderKey(photoID: UUID(), presets: [renamed])
        )
    }
}
