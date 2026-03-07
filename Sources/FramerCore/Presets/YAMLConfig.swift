// Sources/FramerCore/Presets/YAMLConfig.swift
// Stub — full implementation by presets-agent
import Foundation
import AppKit
import Yams

/// Reads and writes .framer.yaml config files — compatible with the Go CLI schema.
public enum YAMLConfig {
    struct YAMLSchema: Codable {
        var border_style: String?
        var border_thickness: String?
        var border_color: String?
        var padding: Int?
        var jpeg_quality: Int?
        var output_format: String?
        var instagram_max_size: Int?
        var post_process: String?
        var background_color: String?
        var outer_padding: Int?
        var no_metadata: Bool?
        var print_width_mm: Double?
        var print_height_mm: Double?
        var print_dpi: Int?
        var background_mode: String?
        var layers: [YAMLLayerSchema]?
    }

    struct YAMLLayerSchema: Codable {
        var type: String
        var thickness: String?
        var color: String?
        var fill: String?
        var fill_color: String?
        var width: Int?
        var height: Int?
        var max_width: Int?
        var max_height: Int?
        var overlay_name: String?
        var overlay_kind: String?
        var blend_mode: String?
        var opacity: Double?
        var orientation: String?
        var caption_mode: String?
        var caption_text: String?
        var font_name: String?
        var font_size: String?
        var font_bold: Bool?
        var font_italic: Bool?
        var font_color: String?
        var caption_alignment: String?
        var caption_position: String?
        var caption_offset_x: Int?
        var caption_offset_y: Int?
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
        if config.noMetadata { schema.no_metadata = config.noMetadata }
        if config.backgroundMode != .color { schema.background_mode = config.backgroundMode.rawValue }
        if let layers = config.layers {
            schema.layers = layers.map { encodeLayers($0) }
        }
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
        if let q = schema.jpeg_quality { config.outputFormat = .jpeg(quality: q) }
        if schema.output_format == "png" { config.outputFormat = .png }
        if let m = schema.instagram_max_size { config.instagramMaxSize = m }
        config.postProcess = schema.post_process
        if let bg = schema.background_color { config.backgroundColor = (try? CodableColor(hex: bg)) ?? config.backgroundColor }
        if let op = schema.outer_padding { config.outerPadding = op }
        if let nm = schema.no_metadata { config.noMetadata = nm }
        if let bm = schema.background_mode, let mode = BackgroundMode(rawValue: bm) {
            config.backgroundMode = mode
        }
        if let yamlLayers = schema.layers {
            config.layers = yamlLayers.compactMap { decodeLayers($0) }
        }

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

    // MARK: - Layer YAML Helpers

    private static func encodeLayers(_ layer: CompositionLayer) -> YAMLLayerSchema {
        switch layer {
        case .border(let p):
            var schema = YAMLLayerSchema(type: "border")
            switch p.thickness {
            case .pixels(let px): schema.thickness = String(px)
            case .percent(let pct): schema.thickness = "\(pct)%"
            }
            schema.color = p.color.hex
            return schema

        case .padding(let p):
            var schema = YAMLLayerSchema(type: "padding")
            schema.thickness = String(p.thickness)
            encodeFill(p.fill, into: &schema)
            return schema

        case .canvas(let p):
            var schema = YAMLLayerSchema(type: "canvas")
            schema.width = p.width
            schema.height = p.height
            encodeFill(p.fill, into: &schema)
            return schema

        case .resize(let p):
            var schema = YAMLLayerSchema(type: "resize")
            schema.max_width = p.maxWidth
            schema.max_height = p.maxHeight
            return schema

        case .overlay(let p):
            var schema = YAMLLayerSchema(type: "overlay")
            schema.overlay_name = p.overlayName
            schema.overlay_kind = p.kind.rawValue
            schema.blend_mode = p.blendMode.rawValue
            schema.opacity = p.opacity
            return schema

        case .orientation(let p):
            var schema = YAMLLayerSchema(type: "orientation")
            schema.orientation = p.target.rawValue
            return schema

        case .caption(let p):
            var schema = YAMLLayerSchema(type: "caption")
            switch p.mode {
            case .template(let t):
                schema.caption_mode = "template"
                schema.caption_text = t
            case .custom(let s):
                schema.caption_mode = "custom"
                schema.caption_text = s
            case .none:
                schema.caption_mode = "none"
            }
            schema.font_name = p.fontName
            switch p.fontSize {
            case .auto: schema.font_size = "auto"
            case .fixed(let s): schema.font_size = String(s)
            }
            if p.fontStyle.contains(.bold) { schema.font_bold = true }
            if p.fontStyle.contains(.italic) { schema.font_italic = true }
            schema.font_color = p.fontColor.hex
            schema.caption_alignment = p.alignment.rawValue
            schema.caption_position = p.position.rawValue
            if p.offsetX != 0 { schema.caption_offset_x = p.offsetX }
            if p.offsetY != 0 { schema.caption_offset_y = p.offsetY }
            return schema
        }
    }

    private static func encodeFill(_ fill: LayerFill, into schema: inout YAMLLayerSchema) {
        switch fill {
        case .color(let c):
            schema.fill = "color"
            schema.fill_color = c.hex
        case .dominantColor:
            schema.fill = "dominant"
        case .gradientLinear:
            schema.fill = "gradient_linear"
        case .gradientRadial:
            schema.fill = "gradient_radial"
        }
    }

    private static func decodeLayers(_ schema: YAMLLayerSchema) -> CompositionLayer? {
        switch schema.type {
        case "border":
            let thickness = schema.thickness.map { BorderSize(string: $0) } ?? .pixels(20)
            let color = schema.color.flatMap { try? CodableColor(hex: $0) } ?? (try! CodableColor(hex: "#FFFFFF"))
            return .border(BorderLayerParams(thickness: thickness, color: color))

        case "padding":
            let thickness = schema.thickness.flatMap { Int($0) } ?? 150
            let fill = decodeFill(schema)
            return .padding(PaddingLayerParams(thickness: thickness, fill: fill))

        case "canvas":
            let fill = decodeFill(schema)
            return .canvas(CanvasLayerParams(
                width: schema.width ?? 1080,
                height: schema.height ?? 1350,
                fill: fill
            ))

        case "resize":
            return .resize(ResizeLayerParams(
                maxWidth: schema.max_width ?? 1000,
                maxHeight: schema.max_height ?? 1000
            ))

        case "overlay":
            let kind: OverlayKind
            if let kindStr = schema.overlay_kind, let k = OverlayKind(rawValue: kindStr) {
                kind = k
            } else {
                kind = .frame
            }
            let blendMode: OverlayBlendMode?
            if let modeStr = schema.blend_mode, let m = OverlayBlendMode(rawValue: modeStr) {
                blendMode = m
            } else {
                blendMode = nil
            }
            return .overlay(OverlayLayerParams(
                overlayName: schema.overlay_name ?? "",
                kind: kind,
                blendMode: blendMode,
                opacity: schema.opacity ?? 100
            ))

        case "orientation":
            let target: OrientationTarget
            if let str = schema.orientation, let t = OrientationTarget(rawValue: str) {
                target = t
            } else {
                target = .landscape
            }
            return .orientation(OrientationLayerParams(target: target))

        case "caption":
            let mode: CaptionMode
            switch schema.caption_mode {
            case "custom": mode = .custom(schema.caption_text ?? "")
            case "none": mode = .none
            default: mode = .template(schema.caption_text ?? " - {{mon}} '{{year2}} -")
            }
            var fontStyle: FontStyle = []
            if schema.font_bold == true { fontStyle.insert(.bold) }
            if schema.font_italic == true { fontStyle.insert(.italic) }
            let fontSize: FontSize
            if let fs = schema.font_size, let i = Int(fs) {
                fontSize = .fixed(i)
            } else {
                fontSize = .auto
            }
            return .caption(CaptionLayerParams(
                mode: mode,
                fontName: schema.font_name ?? "Courier New",
                fontSize: fontSize,
                fontStyle: fontStyle,
                fontColor: (schema.font_color.flatMap { try? CodableColor(hex: $0) }) ?? (try! CodableColor(hex: "#000000")),
                alignment: schema.caption_alignment.flatMap { CaptionAlignment(rawValue: $0) } ?? .center,
                position: schema.caption_position.flatMap { CaptionPosition(rawValue: $0) } ?? .bottom,
                offsetX: schema.caption_offset_x ?? 0,
                offsetY: schema.caption_offset_y ?? 0
            ))

        default:
            return nil
        }
    }

    private static func decodeFill(_ schema: YAMLLayerSchema) -> LayerFill {
        switch schema.fill {
        case "dominant":
            return .dominantColor
        case "gradient_linear":
            return .gradientLinear
        case "gradient_radial":
            return .gradientRadial
        case "color":
            if let hex = schema.fill_color, let c = try? CodableColor(hex: hex) {
                return .color(c)
            }
            return .color(try! CodableColor(hex: "#FFFFFF"))
        default:
            if let hex = schema.fill_color, let c = try? CodableColor(hex: hex) {
                return .color(c)
            }
            return .color(try! CodableColor(hex: "#FFFFFF"))
        }
    }
}
