// Sources/FramerCore/Presets/YAMLConfig.swift
// Stub — full implementation by presets-agent
import Foundation
import Yams

/// Reads and writes .framer.yaml config files — compatible with the Go CLI schema.
public enum YAMLConfig {
    struct YAMLSchema: Codable {
        var border_style: String?
        var border_thickness: String?
        var border_color: String?
        var padding: Int?
        var caption: String?
        var caption_template: String?
        var no_caption: Bool?
        var font_name: String?
        var font_size: String?
        var font_color: String?
        var jpeg_quality: Int?
        var output_format: String?
        var instagram_max_size: Int?
        var post_process: String?
    }

    public static func encode(_ config: ProcessingConfig) throws -> String {
        var schema = YAMLSchema()
        schema.border_style = config.borderStyle.rawValue
        switch config.borderThickness {
        case .pixels(let px): schema.border_thickness = String(px)
        case .percent(let pct): schema.border_thickness = "\(pct)%"
        }
        schema.border_color = config.borderColor.hex
        schema.padding = config.padding
        switch config.captionMode {
        case .template(let t): schema.caption_template = t
        case .custom(let s): schema.caption = s
        case .none: schema.no_caption = true
        }
        schema.font_name = config.fontName
        switch config.fontSize {
        case .auto: break
        case .fixed(let s): schema.font_size = String(s)
        }
        schema.font_color = config.fontColor.hex
        switch config.outputFormat {
        case .jpeg(let q):
            schema.output_format = "jpeg"
            schema.jpeg_quality = q
        case .png:
            schema.output_format = "png"
        }
        schema.instagram_max_size = config.instagramMaxSize
        schema.post_process = config.postProcess
        return try YAMLEncoder().encode(schema)
    }

    public static func decode(_ yaml: String) throws -> ProcessingConfig {
        let schema = try YAMLDecoder().decode(YAMLSchema.self, from: yaml)
        var config = ProcessingConfig.default

        if let s = schema.border_style { config.borderStyle = BorderStyle(rawValue: s) ?? .solid }
        if let t = schema.border_thickness { config.borderThickness = BorderSize(string: t) }
        if let c = schema.border_color { config.borderColor = (try? CodableColor(hex: c)) ?? config.borderColor }
        if let p = schema.padding { config.padding = p }
        if schema.no_caption == true {
            config.captionMode = .none
        } else if let t = schema.caption_template {
            config.captionMode = .template(t)
        } else if let s = schema.caption {
            config.captionMode = .custom(s)
        }
        if let fn = schema.font_name { config.fontName = fn }
        if let fs = schema.font_size, let i = Int(fs) { config.fontSize = .fixed(i) }
        if let fc = schema.font_color { config.fontColor = (try? CodableColor(hex: fc)) ?? config.fontColor }
        if let q = schema.jpeg_quality { config.outputFormat = .jpeg(quality: q) }
        if schema.output_format == "png" { config.outputFormat = .png }
        if let m = schema.instagram_max_size { config.instagramMaxSize = m }
        config.postProcess = schema.post_process

        return config
    }

    /// Loads config from a file URL
    public static func load(from url: URL) throws -> ProcessingConfig {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try decode(yaml)
    }

    /// Finds and loads .framer.yaml using priority order (same as Go CLI)
    public static func loadDefault(configPath: URL? = nil, preset: String? = nil) -> ProcessingConfig {
        // 1. Explicit --config path
        if let path = configPath, let config = try? load(from: path) { return config }

        // 2. --preset from ~/Library/Application Support/Framer/presets/<name>.yaml
        if let name = preset {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let presetURL = appSupport.appendingPathComponent("Framer/presets/\(name).yaml")
            if let config = try? load(from: presetURL) { return config }
        }

        // 3. ./.framer.yaml (current directory)
        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".framer.yaml")
        if let config = try? load(from: localURL) { return config }

        // 4. ~/.config/framer/default.yaml
        let homeConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/framer/default.yaml")
        if let config = try? load(from: homeConfig) { return config }

        return .default
    }
}
