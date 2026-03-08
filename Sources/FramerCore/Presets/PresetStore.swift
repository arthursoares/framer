import Foundation
import CryptoKit

public final class PresetStore {
    private let directory: URL

    /// Default initializer — uses ~/Library/Application Support/Framer/presets/
    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Framer/presets", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(directory: dir)
    }

    /// Testable initializer with custom directory
    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ preset: Preset) throws {
        // Remove any YAML file for this preset name (e.g. upgrading a default preset)
        let yamlURL = directory.appendingPathComponent("\(preset.name).yaml")
        if FileManager.default.fileExists(atPath: yamlURL.path) {
            try? FileManager.default.removeItem(at: yamlURL)
        }

        let url = directory.appendingPathComponent("\(preset.id.uuidString).json")
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url, options: .atomic)
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
                    .canvas(CanvasLayerParams(width: 1080, height: 1350, fill: .dominantColor)),
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
