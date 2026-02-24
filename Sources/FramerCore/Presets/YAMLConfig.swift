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
        var background_color: String?
        var outer_padding: Int?
        var caption_padding: Int?
        var no_metadata: Bool?
        var print_width_mm: Double?
        var print_height_mm: Double?
        var print_dpi: Int?
    }

    public static func encode(_ config: ProcessingConfig) throws -> String {
        var schema = YAMLSchema()
        switch config.borderStyle {
        case .solid:
            schema.border_style = "solid"
        case .instagram:
            schema.border_style = "instagram"
        case .print(let format):
            schema.border_style = "print"
            schema.print_width_mm = format.widthMM
            schema.print_height_mm = format.heightMM
            schema.print_dpi = format.dpi
        }
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
        schema.background_color = config.backgroundColor.hex
        if config.outerPadding != 0 { schema.outer_padding = config.outerPadding }
        if config.captionPadding != 0 { schema.caption_padding = config.captionPadding }
        if config.noMetadata { schema.no_metadata = config.noMetadata }
        return try YAMLEncoder().encode(schema)
    }

    public static func decode(_ yaml: String) throws -> ProcessingConfig {
        let schema = try YAMLDecoder().decode(YAMLSchema.self, from: yaml)
        var config = ProcessingConfig.default

        if let s = schema.border_style {
            switch s {
            case "solid": config.borderStyle = .solid
            case "instagram": config.borderStyle = .instagram
            case "print10x15": config.borderStyle = .print(.print10x15)
            case "print":
                let format = PrintFormat(
                    widthMM: schema.print_width_mm ?? 148,
                    heightMM: schema.print_height_mm ?? 100,
                    dpi: schema.print_dpi ?? 300
                )
                config.borderStyle = .print(format)
            default: config.borderStyle = .solid
            }
        }
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
        if let bg = schema.background_color { config.backgroundColor = (try? CodableColor(hex: bg)) ?? config.backgroundColor }
        if let op = schema.outer_padding { config.outerPadding = op }
        if let cp = schema.caption_padding { config.captionPadding = cp }
        if let nm = schema.no_metadata { config.noMetadata = nm }

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
