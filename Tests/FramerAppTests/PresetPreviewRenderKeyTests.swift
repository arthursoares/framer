import XCTest
import FramerCore
@testable import Framer

final class PresetPreviewRenderKeyTests: XCTestCase {
    func test_changesWhenSelectedPhotoChanges() {
        let preset = Preset(name: "Balanced", config: .default)
        let rotation = 0
        let photoA = UUID()
        let photoB = UUID()

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: photoA, photoRotation: rotation, presets: [preset]),
            PresetPreviewRenderKey(photoID: photoB, photoRotation: rotation, presets: [preset])
        )
    }

    func test_changesWhenSelectedPhotoRotationChanges() {
        let preset = Preset(name: "Balanced", config: .default)
        let photoID = UUID()

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: photoID, photoRotation: 0, presets: [preset]),
            PresetPreviewRenderKey(photoID: photoID, photoRotation: 90, presets: [preset])
        )
    }

    func test_changesWhenPresetConfigurationChanges() {
        let presetID = UUID()
        let photoID = UUID()
        let original = Preset(id: presetID, name: "Balanced", config: .default)
        var updatedConfig = ProcessingConfig.default
        updatedConfig.outputFormat = .png
        let updated = Preset(id: presetID, name: "Balanced", config: updatedConfig)

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: photoID, photoRotation: 0, presets: [original]),
            PresetPreviewRenderKey(photoID: photoID, photoRotation: 0, presets: [updated])
        )
    }

    func test_changesWhenPresetNameChanges() {
        let presetID = UUID()
        let photoID = UUID()
        let original = Preset(id: presetID, name: "Balanced", config: .default)
        let renamed = Preset(id: presetID, name: "Editorial", config: .default)

        XCTAssertNotEqual(
            PresetPreviewRenderKey(photoID: photoID, photoRotation: 0, presets: [original]),
            PresetPreviewRenderKey(photoID: photoID, photoRotation: 0, presets: [renamed])
        )
    }
}
