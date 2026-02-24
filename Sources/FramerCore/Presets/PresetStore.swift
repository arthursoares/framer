import Foundation

public final class PresetStore {
    private let directory: URL

    /// Default initializer — uses ~/Library/Application Support/Framer/presets/
    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
        try data.write(to: url)
    }

    public func load(id: UUID) throws -> Preset {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Preset.self, from: data)
    }

    public func list() throws -> [Preset] {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    public func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
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
            ("vintage", ProcessingConfig(
                borderStyle: .solid,
                borderThickness: .pixels(50),
                borderColor: try! CodableColor(hex: "#F5F0E8"),
                padding: 200,
                captionMode: .template(" - {{mon}} '{{year2}} -"),
                fontName: "Courier New Bold",
                fontColor: try! CodableColor(hex: "#2C2C2C"),
                outputFormat: .jpeg(quality: 95)
            )),
            ("instagram", ProcessingConfig(
                borderStyle: .instagram,
                borderThickness: .pixels(20),
                borderColor: try! CodableColor(hex: "#FFFFFF"),
                padding: 150,
                captionMode: .template("{{camera}} | {{focal}} | {{aperture}} | {{iso}}"),
                fontName: "Courier New Bold",
                fontColor: try! CodableColor(hex: "#000000")
            )),
            ("minimal", ProcessingConfig(
                borderStyle: .solid,
                borderThickness: .pixels(10),
                borderColor: try! CodableColor(hex: "#FFFFFF"),
                padding: 50,
                captionMode: .none
            )),
            ("print10x15", ProcessingConfig(
                borderStyle: .print(.print10x15),
                borderThickness: .pixels(30),
                borderColor: try! CodableColor(hex: "#FFFFFF"),
                padding: 100,
                captionMode: .template(" - {{mon}} '{{year2}} -"),
                fontName: "Courier New Bold",
                fontColor: try! CodableColor(hex: "#333333"),
                backgroundColor: try! CodableColor(hex: "#FFFFFF"),
                outerPadding: 40,
                captionPadding: 20
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
