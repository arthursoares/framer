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
        var presets: [Preset] = []

        // Load JSON presets
        presets += files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }

        // Load YAML presets
        presets += files
            .filter { $0.pathExtension == "yaml" }
            .compactMap { url -> Preset? in
                guard let yaml = try? String(contentsOf: url, encoding: .utf8),
                      let config = try? YAMLConfig.decode(yaml) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                let id = Self.deterministicUUID(from: name)
                return Preset(id: id, name: name, config: config)
            }

        return presets.sorted { $0.name < $1.name }
    }

    public func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }

    /// Creates a deterministic UUID from a name string (for stable YAML preset identity).
    private static func deterministicUUID(from name: String) -> UUID {
        var bytes = Array(name.utf8.prefix(16))
        while bytes.count < 16 { bytes.append(0) }
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
