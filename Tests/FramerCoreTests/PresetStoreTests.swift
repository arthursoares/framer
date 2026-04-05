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
        XCTAssertEqual(config.backgroundColor, decoded.backgroundColor)
        XCTAssertEqual(config.outerPadding, decoded.outerPadding)
        XCTAssertEqual(config.noMetadata, decoded.noMetadata)
    }

    func test_yamlConfig_decodesNewFields() throws {
        let config = ProcessingConfig(
            backgroundColor: CodableColor(unchecked: "#FF0000"),
            outerPadding: 42,
            noMetadata: true
        )
        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)
        XCTAssertEqual(decoded.backgroundColor.hex, "#FF0000")
        XCTAssertEqual(decoded.outerPadding, 42)
        XCTAssertEqual(decoded.noMetadata, true)
    }

    func test_yamlConfig_preservesDisabledLayers() throws {
        let config = ProcessingConfig(
            layers: [
                .border(BorderLayerParams(enabled: false, thickness: .pixels(12), color: .white)),
                .lut(LUTLayerParams(enabled: true, lutName: "Film", lutFileName: "film.cube", intensity: 0.8))
            ]
        )

        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)

        XCTAssertEqual(decoded.layers?.count, 2)
        XCTAssertEqual(decoded.layers?.first?.isEnabled, false)
        XCTAssertEqual(decoded.layers?.last?.isEnabled, true)
    }

    func test_yamlConfig_dominantTwoTonePreservesColorShifts() throws {
        var config = ProcessingConfig.default
        config.layers = [
            .dither(DitherLayerParams(
                algorithm: .atkinson,
                colorMode: .dominantTwoTone(
                    flipped: true,
                    saturationShift: 12,
                    lightnessShift: -8
                )
            ))
        ]

        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)

        guard
            let layers = decoded.layers,
            case .dither(let params) = layers.first,
            case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift) = params.colorMode
        else {
            return XCTFail("Expected dither dominantTwoTone layer")
        }

        XCTAssertTrue(flipped)
        XCTAssertEqual(saturationShift, 12, accuracy: 0.0001)
        XCTAssertEqual(lightnessShift, -8, accuracy: 0.0001)
    }

    func test_yamlConfig_shaderLayer_roundtrips() throws {
        var config = ProcessingConfig.default
        config.layers = [
            .shader(ShaderLayerParams(
                style: .crimewave,
                intensity: 0.8,
                params: .crimewave(CrimewaveShaderParams(neon: 0.9, softness: 0.6, contrast: 1.2, grain: 0.3))
            ))
        ]

        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)

        guard
            let layer = decoded.layers?.first,
            case .shader(let params) = layer
        else {
            return XCTFail("Expected decoded shader layer")
        }

        XCTAssertEqual(params.style, .crimewave)
        XCTAssertEqual(params.intensity, 0.8)
        XCTAssertEqual(
            params.params,
            .crimewave(CrimewaveShaderParams(neon: 0.9, softness: 0.6, contrast: 1.2, grain: 0.3))
        )
    }

    func test_yamlConfig_preservesDisabledShaderLayer() throws {
        var config = ProcessingConfig.default
        config.layers = [
            .shader(ShaderLayerParams(
                enabled: false,
                style: .ascii,
                intensity: 1.0,
                params: .ascii(ASCIIShaderParams())
            ))
        ]

        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)

        XCTAssertEqual(decoded.layers?.first?.isEnabled, false)
    }

    func test_yamlConfig_asciiShaderDominantTwoTonePreservesColorShifts() throws {
        var config = ProcessingConfig.default
        config.layers = [
            .shader(ShaderLayerParams(
                style: .ascii,
                intensity: 0.9,
                params: .ascii(ASCIIShaderParams(
                    cellSize: 9,
                    edgeBias: 0.35,
                    colorMode: .dominantTwoTone(flipped: true, saturationShift: 18, lightnessShift: -12),
                    invert: false
                ))
            ))
        ]

        let yaml = try YAMLConfig.encode(config)
        let decoded = try YAMLConfig.decode(yaml)

        guard
            let layer = decoded.layers?.first,
            case .shader(let params) = layer,
            case .ascii(let asciiParams) = params.params,
            case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift) = asciiParams.colorMode
        else {
            return XCTFail("Expected ascii shader with dominant two-tone color mode")
        }

        XCTAssertTrue(flipped)
        XCTAssertEqual(saturationShift, 18, accuracy: 0.0001)
        XCTAssertEqual(lightnessShift, -12, accuracy: 0.0001)
    }

    func test_yamlConfig_print10x15BackwardCompat() throws {
        let yaml = """
        border_style: print10x15
        border_thickness: "30"
        border_color: "#FFFFFF"
        padding: 100
        """
        let decoded = try YAMLConfig.decode(yaml)
        XCTAssertEqual(decoded.borderStyle, .print(.print10x15))
    }

    func test_yamlConfig_printWithDimensions() throws {
        let yaml = """
        border_style: print
        print_width_mm: 200.0
        print_height_mm: 150.0
        print_dpi: 600
        border_thickness: "30"
        border_color: "#FFFFFF"
        padding: 100
        """
        let decoded = try YAMLConfig.decode(yaml)
        if case .print(let format) = decoded.borderStyle {
            XCTAssertEqual(format.widthMM, 200.0)
            XCTAssertEqual(format.heightMM, 150.0)
            XCTAssertEqual(format.dpi, 600)
        } else {
            XCTFail("Expected .print border style, got \(decoded.borderStyle)")
        }
    }

    func test_listPresets_includesYAMLPresets() throws {
        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()

        let all = try store.list()
        XCTAssertEqual(all.count, 12)
        let names = Set(all.map(\.name))
        XCTAssertTrue(names.contains("film"))
        XCTAssertTrue(names.contains("instagram"))
        XCTAssertTrue(names.contains("minimal"))
        XCTAssertTrue(names.contains("print 10x15"))
        XCTAssertTrue(names.contains("dark gradient"))
        XCTAssertTrue(names.contains("Shader ASCII"))
        XCTAssertTrue(names.contains("Shader Crimewave"))
        XCTAssertTrue(names.contains("Shader Narc"))
        XCTAssertTrue(names.contains("Shader Shiba"))
        XCTAssertTrue(names.contains("Shader Pixel Sort"))
        XCTAssertTrue(names.contains("Shader Distant Past"))
    }

    func test_listPresets_mixedJSONAndYAML() throws {
        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()
        // Also save a JSON preset
        let jsonPreset = Preset(name: "Custom", config: .default)
        try store.save(jsonPreset)

        let all = try store.list()
        XCTAssertEqual(all.count, 13)
    }

    func test_initializeDefaults_creates11Files() throws {
        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir,
                                                                 includingPropertiesForKeys: nil)
        let yamlFiles = files.filter { $0.pathExtension == "yaml" }
        XCTAssertEqual(yamlFiles.count, 12)

        let names = Set(yamlFiles.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertTrue(names.contains("film"))
        XCTAssertTrue(names.contains("instagram"))
        XCTAssertTrue(names.contains("minimal"))
        XCTAssertTrue(names.contains("print 10x15"))
        XCTAssertTrue(names.contains("dark gradient"))
        XCTAssertTrue(names.contains("Shader ASCII"))
        XCTAssertTrue(names.contains("Shader Crimewave"))
        XCTAssertTrue(names.contains("Shader Narc"))
        XCTAssertTrue(names.contains("Shader Shiba"))
        XCTAssertTrue(names.contains("Shader Pixel Sort"))
        XCTAssertTrue(names.contains("Shader Distant Past"))
    }

    func test_initializeDefaults_includesShaderPresets() throws {
        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()

        let all = try store.list()
        let names = Set(all.map(\.name))

        XCTAssertTrue(names.contains("Shader ASCII"))
        XCTAssertTrue(names.contains("Shader Crimewave"))
        XCTAssertTrue(names.contains("Shader Narc"))
        XCTAssertTrue(names.contains("Shader Shiba"))
        XCTAssertTrue(names.contains("Shader Pixel Sort"))
        XCTAssertTrue(names.contains("Shader Distant Past"))
    }

    func test_initializeDefaults_shaderPresetsHaveExpectedConfigs() throws {
        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()

        let presetsByName = Dictionary(uniqueKeysWithValues: try store.list().map { ($0.name, $0) })

        for name in [
            "Shader ASCII",
            "Shader Crimewave",
            "Shader Narc",
            "Shader Shiba",
            "Shader Pixel Sort",
            "Shader Ceiling",
            "Shader Distant Past",
        ] {
            guard let preset = presetsByName[name] else {
                return XCTFail("Missing preset \(name)")
            }
            XCTAssertEqual(preset.config.outputFormat, .png)
            XCTAssertEqual(preset.config.layers?.count, 1)
        }

        if
            let preset = presetsByName["Shader ASCII"],
            let layer = preset.config.layers?.first,
            case .shader(let params) = layer,
            case .ascii(let asciiParams) = params.params
        {
            XCTAssertEqual(params.style, .ascii)
            XCTAssertEqual(params.intensity, 1.0)
            XCTAssertEqual(asciiParams.cellSize, 8)
            XCTAssertEqual(asciiParams.edgeBias, 0.45, accuracy: 0.0001)
            XCTAssertEqual(
                asciiParams.colorMode,
                .dominantTwoTone(flipped: false, saturationShift: 8, lightnessShift: -6)
            )
        } else {
            XCTFail("Shader ASCII preset did not decode to expected shader config")
        }

        if
            let preset = presetsByName["Shader Crimewave"],
            let layer = preset.config.layers?.first,
            case .shader(let params) = layer,
            case .ascii(let asciiParams) = params.params
        {
            XCTAssertEqual(params.style, .ascii)
            XCTAssertEqual(asciiParams.exposure, 1.78, accuracy: 0.001)
            XCTAssertEqual(asciiParams.attenuation, 2.712, accuracy: 0.001)
        } else {
            XCTFail("Shader Crimewave preset did not decode to expected shader config")
        }

        if
            let preset = presetsByName["Shader Narc"],
            let layer = preset.config.layers?.first,
            case .shader(let params) = layer
        {
            XCTAssertEqual(params.style, .narc)
        } else {
            XCTFail("Shader Narc preset did not decode to expected shader config")
        }

        if
            let preset = presetsByName["Shader Shiba"],
            let layer = preset.config.layers?.first,
            case .shader(let params) = layer
        {
            XCTAssertEqual(params.style, .shiba)
        } else {
            XCTFail("Shader Shiba preset did not decode to expected shader config")
        }

        if
            let preset = presetsByName["Shader Pixel Sort"],
            let layer = preset.config.layers?.first,
            case .shader(let params) = layer,
            case .pixelSort(let pixelSortParams) = params.params
        {
            XCTAssertEqual(params.style, .pixelSort)
            XCTAssertEqual(pixelSortParams.direction, .horizontal)
            XCTAssertEqual(pixelSortParams.span, 24)
        } else {
            XCTFail("Shader Pixel Sort preset did not decode to expected shader config")
        }

        if
            let preset = presetsByName["Shader Distant Past"],
            let layer = preset.config.layers?.first,
            case .shader(let params) = layer
        {
            XCTAssertEqual(params.style, .distantPast)
        } else {
            XCTFail("Shader Distant Past preset did not decode to expected shader config")
        }
    }

    func test_initializeDefaults_createsShaderPresetFiles() throws {
        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let yamlFiles = files.filter { $0.pathExtension == "yaml" }

        XCTAssertEqual(yamlFiles.count, 12)
    }

    func test_initializeDefaults_doesNotOverwrite() throws {
        // Write a file first
        let existingURL = tempDir.appendingPathComponent("vintage.yaml")
        let originalContent = "border_style: solid\npadding: 999\n"
        try originalContent.write(to: existingURL, atomically: true, encoding: .utf8)

        let store = PresetStore(directory: tempDir)
        store.initializeDefaults()

        // The existing file should be unchanged because initializeDefaults skips
        // when .yaml files already exist
        let content = try String(contentsOf: existingURL, encoding: .utf8)
        XCTAssertEqual(content, originalContent)

        // No additional yaml files should have been created
        let files = try FileManager.default.contentsOfDirectory(at: tempDir,
                                                                 includingPropertiesForKeys: nil)
        let yamlFiles = files.filter { $0.pathExtension == "yaml" }
        XCTAssertEqual(yamlFiles.count, 1)
    }
}
