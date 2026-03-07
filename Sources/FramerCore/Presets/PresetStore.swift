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
            // Clean white border with EXIF caption
            ("film", ProcessingConfig(
                outputFormat: .jpeg(quality: 95),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(8), color: try! CodableColor(hex: "#FFFFFF"))),
                    .padding(PaddingLayerParams(thickness: 160, fill: .color(try! CodableColor(hex: "#FFFFFF")))),
                    .caption(CaptionLayerParams(
                        mode: .template("{{camera}}  {{focal}}  {{aperture}}  {{shutter}}  {{iso}}"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontColor: try! CodableColor(hex: "#444444"),
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            // 4:5 canvas with dominant color fill, gear caption
            ("instagram", ProcessingConfig(
                outputFormat: .jpeg(quality: 95),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(4), color: try! CodableColor(hex: "#FFFFFF"))),
                    .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .dominantColor)),
                    .caption(CaptionLayerParams(
                        mode: .template("{{camera}} | {{lens}}"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontColor: try! CodableColor(hex: "#FFFFFF"),
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            // Thin border, no caption
            ("minimal", ProcessingConfig(
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(12), color: try! CodableColor(hex: "#FFFFFF"))),
                ]
            )),
            // Print-ready 10x15cm at 300dpi with date caption
            ("print 10x15", ProcessingConfig(
                outputFormat: .jpeg(quality: 100),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(20), color: try! CodableColor(hex: "#FFFFFF"))),
                    .canvas(CanvasLayerParams(width: 1772, height: 1181, fill: .color(try! CodableColor(hex: "#FFFFFF")))),
                    .caption(CaptionLayerParams(
                        mode: .template(" - {{mon}} '{{year2}} -"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontStyle: .bold,
                        fontColor: try! CodableColor(hex: "#333333"),
                        alignment: .center,
                        position: .bottom
                    ))
                ]
            )),
            // Dark background with gradient fill
            ("dark gradient", ProcessingConfig(
                outputFormat: .jpeg(quality: 95),
                layers: [
                    .border(BorderLayerParams(thickness: .pixels(4), color: try! CodableColor(hex: "#000000"))),
                    .padding(PaddingLayerParams(thickness: 180, fill: .gradientRadial())),
                    .caption(CaptionLayerParams(
                        mode: .template("{{camera}}  {{focal}}"),
                        fontName: "Courier New",
                        fontSize: .auto,
                        fontColor: try! CodableColor(hex: "#CCCCCC"),
                        alignment: .center,
                        position: .bottom
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
