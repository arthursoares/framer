import Foundation
import CryptoKit

public final class PresetStore {
    private let directory: URL

    /// Default initializer — uses ~/Library/Application Support/Framer/presets/
    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Framer/presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(directory: dir)
    }

    /// Testable initializer with custom directory
    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ preset: Preset) throws {
        let url = directory.appendingPathComponent("\(preset.id.uuidString).json")
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url, options: .atomic)

        // Retire the legacy file only after its replacement is safe. Match the
        // stored identity, since display names may change or contain path separators.
        // JSON already overrides YAML by ID, so cleanup failure is non-destructive.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for yamlURL in files where yamlURL.pathExtension == "yaml" {
            let name = yamlURL.deletingPathExtension().lastPathComponent
            if Self.deterministicUUID(from: name) == preset.id {
                try FileManager.default.removeItem(at: yamlURL)
            }
        }
    }

    public func load(id: UUID) throws -> Preset {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Preset.self, from: data)
    }

    public func list() throws -> [Preset] {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)
        var presetsById: [UUID: Preset] = [:]

        // Load YAML presets first (lower priority)
        for url in files where url.pathExtension == "yaml" {
            guard let yaml = try? String(contentsOf: url, encoding: .utf8),
                  let config = try? YAMLConfig.decode(yaml) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let id = Self.deterministicUUID(from: name)
            presetsById[id] = Preset(id: id, name: name, config: config)
        }

        // Load JSON presets second (override YAML if same ID).
        // Corrupted files are skipped (not re-thrown) so one bad file
        // doesn't wipe the entire preset list.
        for url in files where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let preset = try JSONDecoder().decode(Preset.self, from: data)
                presetsById[preset.id] = preset
            } catch {
                // Remove corrupted/empty JSON files so they don't persist.
                try? FileManager.default.removeItem(at: url)
            }
        }

        return presetsById.values.sorted { $0.name < $1.name }
    }

    public func delete(id: UUID) throws {
        let jsonURL = directory.appendingPathComponent("\(id.uuidString).json")
        var deleted = false
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            try FileManager.default.removeItem(at: jsonURL)
            deleted = true
        }
        // Also check for YAML files with matching deterministic UUID
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in files where url.pathExtension == "yaml" {
                let name = url.deletingPathExtension().lastPathComponent
                if Self.deterministicUUID(from: name) == id {
                    try FileManager.default.removeItem(at: url)
                    deleted = true
                }
            }
        }
        if !deleted {
            throw CocoaError(.fileNoSuchFile)
        }
    }

    // MARK: - Import / Export

    /// The directory where presets are stored.
    public var storageDirectory: URL { directory }

    /// Exports a preset as JSON data.
    public func exportData(for preset: Preset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preset)
    }

    /// Exports multiple presets as a JSON array.
    public func exportAllData() throws -> Data {
        let presets = try list()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(presets)
    }

    /// Imports presets from JSON data (single preset or array).
    /// Returns the number of presets imported.
    @discardableResult
    public func importData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        // Try array first
        if let presets = try? decoder.decode([Preset].self, from: data) {
            for preset in presets {
                try save(preset)
            }
            return presets.count
        }
        // Try single preset
        let preset = try decoder.decode(Preset.self, from: data)
        try save(preset)
        return 1
    }

    /// Creates a deterministic UUID from a name string (for stable YAML preset identity).
    private static func deterministicUUID(from name: String) -> UUID {
        let hash = Insecure.MD5.hash(data: Data(name.utf8))
        let bytes = Array(hash)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Writes default preset YAML files if the presets directory contains no .yaml files.
    @discardableResult
    public func initializeDefaults() -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                          includingPropertiesForKeys: nil) else {
            return false
        }
        let hasYAML = contents.contains { $0.pathExtension == "yaml" }
        if hasYAML { return false }

        let defaults: [(String, ProcessingConfig)] = [
            // Clean white border with EXIF caption
            ("film", ProcessingConfig(
                outputFormat: .jpeg(quality: 95),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(8), color: .white)),
                    .padding(PaddingLayerParams(thickness: 160, fill: .color(.white))),
                    .caption(CaptionLayerParams(
                        mode: .template("{{camera}}  {{focal}}  {{aperture}}  {{shutter}}  {{iso}}"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontColor: CodableColor(unchecked: "#444444"),
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            // 4:5 canvas with dominant color fill, gear caption
            ("instagram", ProcessingConfig(
                outputFormat: .jpeg(quality: 95),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(4), color: .white)),
                    .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .dominantColor())),
                    .caption(CaptionLayerParams(
                        mode: .template("{{camera}} | {{lens}}"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontColor: .white,
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            // Thin border, no caption
            ("minimal", ProcessingConfig(
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(12), color: .white)),
                ]
            )),
            // Print-ready 10x15cm at 300dpi with date caption
            ("print 10x15", ProcessingConfig(
                outputFormat: .jpeg(quality: 100),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(20), color: .white)),
                    .canvas(CanvasLayerParams(width: 1772, height: 1181, fill: .color(.white))),
                    .caption(CaptionLayerParams(
                        mode: .template(" - {{mon}} '{{year2}} -"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontStyle: .bold,
                        fontColor: CodableColor(unchecked: "#333333"),
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            // Dark background with gradient fill
            ("dark gradient", ProcessingConfig(
                outputFormat: .jpeg(quality: 95),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(4), color: .black)),
                    .padding(PaddingLayerParams(thickness: 180, fill: .gradientRadial())),
                    .caption(CaptionLayerParams(
                        mode: .template("{{camera}}  {{focal}}"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontColor: CodableColor(unchecked: "#CCCCCC"),
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            ("Shader ASCII", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .ascii,
                        intensity: 1.0,
                        params: .ascii(ASCIIShaderParams(
                            cellSize: 8,
                            edgeBias: 0.45,
                            colorMode: .dominantTwoTone(flipped: false, saturationShift: 8, lightnessShift: -6),
                            invert: false
                        ))
                    ))
                ]
            )),
            ("Shader Crimewave", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .ascii,
                        intensity: 1.0,
                        params: .ascii(ASCIIShaderParams(
                            cellSize: 8,
                            edgeBias: 0.2,
                            colorMode: .manual(
                                foreground: (try? CodableColor(hex: "#FF9760")) ?? .white,
                                background: (try? CodableColor(hex: "#110302")) ?? .black
                            ),
                            invert: false,
                            exposure: 1.78,
                            attenuation: 2.712
                        ))
                    ))
                ]
            )),
            ("Shader Narc", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .narc,
                        intensity: 1.0,
                        params: .narc(NarcShaderParams())
                    ))
                ]
            )),
            ("Shader Shiba", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .shiba,
                        intensity: 1.0,
                        params: .shiba(ShibaShaderParams())
                    ))
                ]
            )),
            ("Shader Pixel Sort", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .pixelSort,
                        intensity: 1.0,
                        params: .pixelSort(PixelSortShaderParams(threshold: 0.1, direction: .horizontal, span: 24, amount: 1.0))
                    ))
                ]
            )),
            ("Shader Ceiling", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .pixelSort,
                        intensity: 1.0,
                        params: .pixelSort(PixelSortShaderParams(
                            threshold: 0.19,
                            direction: .horizontal,
                            span: 256,
                            amount: 1.0
                        ))
                    ))
                ]
            )),
            ("Shader Distant Past", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .distantPast,
                        intensity: 1.0,
                        params: .distantPast(DistantPastShaderParams())
                    ))
                ]
            )),
            ("Shader CRT", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .crt,
                        intensity: 1.0,
                        params: .crt(CRTShaderParams())
                    ))
                ]
            )),
            ("Shader Halftone", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .halftone,
                        intensity: 1.0,
                        params: .halftone(HalftoneShaderParams())
                    ))
                ]
            )),
            ("Shader Kuwahara", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .shader(ShaderLayerParams(
                        style: .kuwahara,
                        intensity: 1.0,
                        params: .kuwahara(KuwaharaShaderParams())
                    ))
                ]
            )),
            ("GPU ASCII Matrix", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .gpuEffect(GPUEffectLayerParams(
                        kind: .matrixRain,
                        params: .textCell(
                            common: .init(brightness: 0.02, contrast: 1.1, saturation: 0.9, hueRotation: 0.0, gamma: 1.0),
                            geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                            color: .init(mode: .foregroundBackground, backgroundIntensity: 0.18),
                            textCell: .init(characterSet: .classicASCII, variant: .matrixRain)
                        )
                    ))
                ]
            )),
            ("GPU Halftone Print", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .gpuEffect(GPUEffectLayerParams(
                        kind: .halftone,
                        params: .printSampling(
                            common: .init(brightness: 0.0, contrast: 1.15, saturation: 1.0, hueRotation: 0.0, gamma: 1.0),
                            geometry: .init(scale: 0.9, spacing: 3.0, outputWidth: 240),
                            color: .init(mode: .source, backgroundIntensity: 0.0),
                            printSampling: .init(variant: .halftone, sampleDensity: 0.7, threshold: 0.4)
                        )
                    ))
                ]
            )),
            ("GPU Wave Field", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .gpuEffect(GPUEffectLayerParams(
                        kind: .waveLines,
                        params: .edgeField(
                            common: .init(brightness: 0.0, contrast: 1.0, saturation: 1.1, hueRotation: 0.06, gamma: 1.0),
                            geometry: .init(scale: 1.2, spacing: 4.0, outputWidth: 240),
                            color: .init(mode: .palette, backgroundIntensity: 0.2),
                            edgeField: .init(variant: .waveLines, lineStrength: 0.5, fieldIntensity: 0.9)
                        )
                    ))
                ]
            )),
            ("GPU VHS Static", ProcessingConfig(
                outputFormat: .png,
                layers: [
                    .gpuEffect(GPUEffectLayerParams(
                        kind: .vhs,
                        params: .glitch(
                            common: .init(brightness: 0.0, contrast: 1.2, saturation: 1.0, hueRotation: 0.0, gamma: 1.0),
                            geometry: .init(scale: 1.0, spacing: 2.0, outputWidth: 240),
                            color: .init(mode: .foregroundBackground, backgroundIntensity: 0.08),
                            glitch: .init(variant: .vhs, amount: 0.75, threshold: 0.5)
                        )
                    ))
                ]
            )),
        ]

        do {
            for (name, config) in defaults {
                let yaml = try YAMLConfig.encode(config)
                let fileURL = directory.appendingPathComponent("\(name).yaml")
                try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            return false
        }
        return true
    }
}
