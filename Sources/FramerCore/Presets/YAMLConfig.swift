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
        var enabled: Bool?
        var thickness: String?
        var color: String?
        var fill: String?
        var fill_color: String?
        var gradient_saturation: Double?
        var gradient_lightness: Double?
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
        var algorithm: String?
        var bayer_level: Int?
        var pixel_scale: Int?
        var color_mode: String?
        var color_levels: Int?
        var dither_fg: String?
        var dither_bg: String?
        var dither_threshold: Double?
        var dither_sharpen: Double?
        var dither_contrast: Double?
        var dither_flipped: Bool?
        var dither_palette: [String]?
        var ratio: String?
        var offset_x: Double?
        var offset_y: Double?
        var lut_name: String?
        var lut_filename: String?
        var intensity: Double?
        var shader_style: String?
        var shader_cell_size: Int?
        var shader_edge_bias: Double?
        var shader_color_mode: String?
        var shader_foreground: String?
        var shader_background: String?
        var shader_flipped: Bool?
        var shader_saturation_shift: Double?
        var shader_lightness_shift: Double?
        var shader_invert: Bool?
        var shader_exposure: Double?
        var shader_attenuation: Double?
        var shader_black_level: Double?
        var shader_color1: String?
        var shader_color2: String?
        var shader_neon: Double?
        var shader_softness: Double?
        var shader_contrast: Double?
        var shader_grain: Double?
        var shader_crush: Double?
        var shader_temperature: Double?
        var shader_warmth: Double?
        var shader_saturation: Double?
        var shader_threshold: Double?
        var shader_direction: String?
        var shader_span: Int?
        var shader_amount: Double?
        var shader_palette_depth: Int?
        var shader_fade: Double?
        var shader_curvature: Double?
        var shader_line_size: Int?
        var shader_line_strength: Double?
        var shader_brightness: Double?
        var shader_vignette: Double?
        var shader_dot_size: Double?
        var shader_monochrome: Bool?
        var shader_kernel_size: Int?
        var shader_sharpness: Double?
        var gpu_effect_kind: String?
        var gpu_common_brightness: Double?
        var gpu_common_contrast: Double?
        var gpu_common_saturation: Double?
        var gpu_common_hue_rotation: Double?
        var gpu_common_sharpness: Double?
        var gpu_common_gamma: Double?
        var gpu_scale: Double?
        var gpu_spacing: Double?
        var gpu_output_width: Int?
        var gpu_color_mode: String?
        var gpu_background_intensity: Double?
        var gpu_character_set: String?
        var gpu_text_variant: String?
        var gpu_text_speed: Double?
        var gpu_text_trail_length: Double?
        var gpu_text_direction: String?
        var gpu_text_glow: Double?
        var gpu_text_background_opacity: Double?
        var gpu_text_threshold: Double?
        var gpu_text_rain_color: String?
        var gpu_text_intensity: Double?
        var gpu_text_foreground_color: String?
        var gpu_text_background_color: String?
        var gpu_dot_shape: String?
        var gpu_dot_grid_type: String?
        var gpu_text_invert: Bool?
        var gpu_block_style: String?
        var gpu_block_border_width: Double?
        var gpu_block_border_color: String?
        var gpu_sampling_variant: String?
        var gpu_sample_density: Double?
        var gpu_sampling_threshold: Double?
        var gpu_dither_algorithm: String?
        var gpu_modulation: Double?
        var gpu_sharpen: Double?
        var gpu_chromatic_enabled: Bool?
        var gpu_chromatic_max_displace: Double?
        var gpu_chromatic_red_shift: Double?
        var gpu_chromatic_green_shift: Double?
        var gpu_chromatic_blue_shift: Double?
        var gpu_foreground_color: String?
        var gpu_background_color: String?
        var gpu_halftone_shape: String?
        var gpu_halftone_angle: Double?
        var gpu_invert: Bool?
        var gpu_hatch_density: Double?
        var gpu_hatch_layers: Int?
        var gpu_hatch_angle: Double?
        var gpu_hatch_line_width: Double?
        var gpu_hatch_randomness: Double?
        var gpu_threshold_levels: Int?
        var gpu_threshold_dither: Bool?
        var gpu_edge_variant: String?
        var gpu_line_strength: Double?
        var gpu_field_intensity: Double?
        var gpu_edge_line_count: Double?
        var gpu_edge_amplitude: Double?
        var gpu_edge_frequency: Double?
        var gpu_edge_thickness: Double?
        var gpu_edge_direction: String?
        var gpu_edge_animate: Bool?
        var gpu_noise_type: String?
        var gpu_noise_octaves: Int?
        var gpu_noise_speed: Double?
        var gpu_noise_distort_only: Bool?
        var gpu_edge_algorithm: String?
        var gpu_edge_threshold: Double?
        var gpu_edge_invert: Bool?
        var gpu_edge_color: String?
        var gpu_contour_fill_mode: String?
        var gpu_contour_levels: Int?
        var gpu_voronoi_cell_size: Double?
        var gpu_voronoi_edge_width: Double?
        var gpu_voronoi_randomize: Bool?
        var gpu_glitch_variant: String?
        var gpu_glitch_amount: Double?
        var gpu_glitch_threshold: Double?
        var gpu_glitch_direction: String?
        var gpu_glitch_sort_mode: String?
        var gpu_glitch_streak_length: Double?
        var gpu_glitch_randomness: Double?
        var gpu_glitch_reverse: Bool?
        var gpu_glitch_distortion: Double?
        var gpu_glitch_color_bleed: Double?
        var gpu_glitch_scanlines: Double?
        var gpu_glitch_tracking_error: Double?
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

        // 4. ~/.config/framer/default.yaml (macOS only)
        #if os(macOS)
        let homeConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/framer/default.yaml")
        if let config = try? load(from: homeConfig) { return config }
        #endif

        return .default
    }

    // MARK: - Layer YAML Helpers

    private static func encodeLayers(_ layer: CompositionLayer) -> YAMLLayerSchema {
        switch layer {
        case .border(let p):
            var schema = YAMLLayerSchema(type: "border")
            if !p.enabled { schema.enabled = false }
            switch p.thickness {
            case .pixels(let px): schema.thickness = String(px)
            case .percent(let pct): schema.thickness = "\(pct)%"
            }
            schema.color = p.color.hex
            return schema

        case .padding(let p):
            var schema = YAMLLayerSchema(type: "padding")
            if !p.enabled { schema.enabled = false }
            schema.thickness = String(p.thickness)
            encodeFill(p.fill, into: &schema)
            return schema

        case .canvas(let p):
            var schema = YAMLLayerSchema(type: "canvas")
            if !p.enabled { schema.enabled = false }
            schema.width = p.width
            schema.height = p.height
            encodeFill(p.fill, into: &schema)
            return schema

        case .resize(let p):
            var schema = YAMLLayerSchema(type: "resize")
            if !p.enabled { schema.enabled = false }
            schema.max_width = p.maxWidth
            schema.max_height = p.maxHeight
            return schema

        case .overlay(let p):
            var schema = YAMLLayerSchema(type: "overlay")
            if !p.enabled { schema.enabled = false }
            schema.overlay_name = p.overlayName
            schema.overlay_kind = p.kind.rawValue
            schema.blend_mode = p.blendMode.rawValue
            schema.opacity = p.opacity
            return schema

        case .orientation(let p):
            var schema = YAMLLayerSchema(type: "orientation")
            if !p.enabled { schema.enabled = false }
            schema.orientation = p.target.rawValue
            return schema

        case .caption(let p):
            var schema = YAMLLayerSchema(type: "caption")
            if !p.enabled { schema.enabled = false }
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
            switch p.fontColorMode {
            case .fixed(let c): schema.font_color = c.hex
            case .dominant: schema.font_color = "dominant"
            case .dominantInverted: schema.font_color = "dominant_inverted"
            // Note: saturation/lightness shifts for caption dominant colors
            // are persisted in the JSON Codable path, not YAML (YAML is legacy)
            }
            schema.caption_alignment = p.alignment.rawValue
            schema.caption_position = p.position.rawValue
            if p.offsetX != 0 { schema.caption_offset_x = p.offsetX }
            if p.offsetY != 0 { schema.caption_offset_y = p.offsetY }
            return schema

        case .dither(let p):
            var schema = YAMLLayerSchema(type: "dither")
            if !p.enabled { schema.enabled = false }
            schema.algorithm = p.algorithm.rawValue
            schema.bayer_level = p.bayerLevel
            schema.pixel_scale = p.pixelScale
            if p.threshold != 0.5 { schema.dither_threshold = p.threshold }
            if p.sharpen > 0 { schema.dither_sharpen = p.sharpen }
            if p.contrast > 0 { schema.dither_contrast = p.contrast }
            switch p.colorMode {
            case .bw:
                schema.color_mode = "bw"
            case .twoTone(let fg, let bg):
                schema.color_mode = "twoTone"
                schema.dither_fg = fg.hex
                schema.dither_bg = bg.hex
            case .dominantTwoTone(let flipped, let sat, let light):
                schema.color_mode = "dominantTwoTone"
                if flipped { schema.dither_flipped = true }
                if sat != 0 { schema.gradient_saturation = sat }
                if light != 0 { schema.gradient_lightness = light }
            case .color(let levels):
                schema.color_mode = "color"
                schema.color_levels = levels
            case .palette(let colors):
                schema.color_mode = "palette"
                schema.dither_palette = colors.map { $0.hex }
            }
            return schema

        case .aspectRatio(let p):
            var schema = YAMLLayerSchema(type: "aspect_ratio")
            if !p.enabled { schema.enabled = false }
            schema.ratio = "\(p.ratioWidth):\(p.ratioHeight)"
            if p.offsetX != 0 { schema.offset_x = p.offsetX }
            if p.offsetY != 0 { schema.offset_y = p.offsetY }
            return schema

        case .lut(let p):
            var schema = YAMLLayerSchema(type: "lut")
            if !p.enabled { schema.enabled = false }
            schema.lut_name = p.lutName
            schema.lut_filename = p.lutFileName
            schema.intensity = p.intensity
            return schema

        case .shader(let p):
            var schema = YAMLLayerSchema(type: "shader")
            if !p.enabled { schema.enabled = false }
            schema.intensity = p.intensity
            schema.shader_style = p.style.rawValue
            encodeShaderParams(p.params, into: &schema)
            return schema

        case .gpuEffect(let p):
            var schema = YAMLLayerSchema(type: "gpu_effect")
            if !p.enabled { schema.enabled = false }
            schema.gpu_effect_kind = p.kind.rawValue
            encodeGPUEffectParams(p.params, into: &schema)
            return schema
        }
    }

    private static func encodeFill(_ fill: LayerFill, into schema: inout YAMLLayerSchema) {
        switch fill {
        case .color(let c):
            schema.fill = "color"
            schema.fill_color = c.hex
        case .dominantColor(let p):
            schema.fill = "dominant"
            if p.saturationShift != 0 { schema.gradient_saturation = p.saturationShift }
            if p.lightnessShift != 0 { schema.gradient_lightness = p.lightnessShift }
        case .gradientLinear(let p):
            schema.fill = "gradient_linear"
            if p.saturationShift != 0 { schema.gradient_saturation = p.saturationShift }
            if p.lightnessShift != 0 { schema.gradient_lightness = p.lightnessShift }
        case .gradientRadial(let p):
            schema.fill = "gradient_radial"
            if p.saturationShift != 0 { schema.gradient_saturation = p.saturationShift }
            if p.lightnessShift != 0 { schema.gradient_lightness = p.lightnessShift }
        }
    }

    private static func decodeLayers(_ schema: YAMLLayerSchema) -> CompositionLayer? {
        let enabled = schema.enabled ?? true
        switch schema.type {
        case "border":
            let thickness = schema.thickness.map { BorderSize(string: $0) } ?? .pixels(20)
            let color = schema.color.flatMap { try? CodableColor(hex: $0) } ?? .white
            return .border(BorderLayerParams(enabled: enabled, thickness: thickness, color: color))

        case "padding":
            let thickness = schema.thickness.flatMap { Int($0) } ?? 150
            let fill = decodeFill(schema)
            return .padding(PaddingLayerParams(enabled: enabled, thickness: thickness, fill: fill))

        case "canvas":
            let fill = decodeFill(schema)
            return .canvas(CanvasLayerParams(
                enabled: enabled,
                width: schema.width ?? 1080,
                height: schema.height ?? 1350,
                fill: fill
            ))

        case "resize":
            return .resize(ResizeLayerParams(
                enabled: enabled,
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
                enabled: enabled,
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
            return .orientation(OrientationLayerParams(enabled: enabled, target: target))

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
                enabled: enabled,
                mode: mode,
                fontName: schema.font_name ?? "Courier New",
                fontSize: fontSize,
                fontStyle: fontStyle,
                fontColorMode: {
                    switch schema.font_color {
                    case "dominant": return .dominant()
                    case "dominant_inverted": return .dominantInverted()
                    default: return .fixed((schema.font_color.flatMap { try? CodableColor(hex: $0) }) ?? .black)
                    }
                }(),
                alignment: schema.caption_alignment.flatMap { CaptionAlignment(rawValue: $0) } ?? .center,
                position: schema.caption_position.flatMap { CaptionPosition(rawValue: $0) } ?? .bottom,
                offsetX: schema.caption_offset_x ?? 0,
                offsetY: schema.caption_offset_y ?? 0
            ))

        case "dither":
            let algo = schema.algorithm.flatMap { DitherAlgorithm(rawValue: $0) } ?? .atkinson
            let colorMode: DitherColorMode
            switch schema.color_mode {
            case "twoTone":
                let fg = (schema.dither_fg.flatMap { try? CodableColor(hex: $0) }) ?? .black
                let bg = (schema.dither_bg.flatMap { try? CodableColor(hex: $0) }) ?? .white
                colorMode = .twoTone(foreground: fg, background: bg)
            case "dominantTwoTone":
                colorMode = .dominantTwoTone(
                    flipped: schema.dither_flipped ?? false,
                    saturationShift: schema.gradient_saturation ?? 0,
                    lightnessShift: schema.gradient_lightness ?? 0
                )
            case "color":
                colorMode = .color(levels: schema.color_levels ?? 4)
            case "palette":
                let colors = (schema.dither_palette ?? []).compactMap { try? CodableColor(hex: $0) }
                colorMode = colors.isEmpty ? .bw : .palette(colors)
            default:
                colorMode = .bw
            }
            return .dither(DitherLayerParams(
                enabled: enabled,
                algorithm: algo,
                colorMode: colorMode,
                bayerLevel: schema.bayer_level ?? 2,
                pixelScale: schema.pixel_scale ?? 1,
                threshold: schema.dither_threshold ?? 0.5,
                sharpen: schema.dither_sharpen ?? 0,
                contrast: schema.dither_contrast ?? 0
            ))

        case "aspect_ratio":
            let (rw, rh) = parseRatio(schema.ratio ?? "1:1")
            return .aspectRatio(AspectRatioLayerParams(
                enabled: enabled,
                ratioWidth: rw,
                ratioHeight: rh,
                offsetX: schema.offset_x ?? 0,
                offsetY: schema.offset_y ?? 0
            ))

        case "lut":
            return .lut(LUTLayerParams(
                enabled: enabled,
                lutName: schema.lut_name ?? "",
                lutFileName: schema.lut_filename ?? "",
                intensity: schema.intensity ?? 1.0
            ))

        case "shader":
            guard let styleRaw = schema.shader_style, let style = ShaderStyle(rawValue: styleRaw) else {
                return nil
            }
            return .shader(ShaderLayerParams(
                enabled: enabled,
                style: style,
                intensity: schema.intensity ?? 1.0,
                params: decodeShaderParams(style: style, schema: schema)
            ))

        case "gpu_effect":
            guard let rawKind = schema.gpu_effect_kind, let kind = GPUEffectKind(rawValue: rawKind) else {
                return nil
            }
            return .gpuEffect(GPUEffectLayerParams(
                enabled: enabled,
                kind: kind,
                params: decodeGPUEffectParams(kind: kind, schema: schema)
            ))

        default:
            return nil
        }
    }

    private static func encodeGPUEffectParams(_ params: GPUEffectParameters, into schema: inout YAMLLayerSchema) {
        func encodeCommon(_ common: GPUEffectCommonParameters) {
            schema.gpu_common_brightness = common.brightness
            schema.gpu_common_contrast = common.contrast
            schema.gpu_common_saturation = common.saturation
            schema.gpu_common_hue_rotation = common.hueRotation
            schema.gpu_common_sharpness = common.sharpness
            schema.gpu_common_gamma = common.gamma
        }

        func encodeGeometry(_ geometry: GPUEffectGeometryParameters) {
            schema.gpu_scale = geometry.scale
            schema.gpu_spacing = geometry.spacing
            schema.gpu_output_width = geometry.outputWidth
        }

        func encodeColor(_ color: GPUEffectColorParameters) {
            schema.gpu_color_mode = color.mode.rawValue
            schema.gpu_background_intensity = color.backgroundIntensity
        }

        switch params {
        case .textCell(let common, let geometry, let color, let payload):
            encodeCommon(common)
            encodeGeometry(geometry)
            encodeColor(color)
            schema.gpu_character_set = payload.characterSet.rawValue
            schema.gpu_text_variant = payload.variant.rawValue
            schema.gpu_text_speed = payload.speed
            schema.gpu_text_trail_length = payload.trailLength
            schema.gpu_text_direction = payload.direction.rawValue
            schema.gpu_text_glow = payload.glow
            schema.gpu_text_background_opacity = payload.backgroundOpacity
            schema.gpu_text_threshold = payload.threshold
            schema.gpu_text_rain_color = payload.rainColor?.hex
            schema.gpu_text_intensity = payload.intensity
            schema.gpu_text_foreground_color = payload.foreground?.hex
            schema.gpu_text_background_color = payload.background?.hex
            schema.gpu_dot_shape = payload.dotShape.rawValue
            schema.gpu_dot_grid_type = payload.gridType.rawValue
            schema.gpu_text_invert = payload.invert
            schema.gpu_block_style = payload.blockStyle.rawValue
            schema.gpu_block_border_width = payload.borderWidth
            schema.gpu_block_border_color = payload.borderColor?.hex
        case .printSampling(let common, let geometry, let color, let payload):
            encodeCommon(common)
            encodeGeometry(geometry)
            encodeColor(color)
            schema.gpu_sampling_variant = payload.variant.rawValue
            schema.gpu_sample_density = payload.sampleDensity
            schema.gpu_sampling_threshold = payload.threshold
            schema.gpu_dither_algorithm = payload.algorithm.rawValue
            schema.gpu_modulation = payload.modulation
            schema.gpu_sharpen = payload.sharpen
            schema.gpu_chromatic_enabled = payload.chromaticAberration.enabled
            schema.gpu_chromatic_max_displace = payload.chromaticAberration.maxDisplace
            schema.gpu_chromatic_red_shift = payload.chromaticAberration.redShift
            schema.gpu_chromatic_green_shift = payload.chromaticAberration.greenShift
            schema.gpu_chromatic_blue_shift = payload.chromaticAberration.blueShift
            schema.gpu_foreground_color = payload.foreground?.hex
            schema.gpu_background_color = payload.background?.hex
            schema.gpu_halftone_shape = payload.halftoneShape.rawValue
            schema.gpu_halftone_angle = payload.halftoneAngle
            schema.gpu_invert = payload.invert
            schema.gpu_hatch_density = payload.hatchDensity
            schema.gpu_hatch_layers = payload.hatchLayers
            schema.gpu_hatch_angle = payload.hatchAngle
            schema.gpu_hatch_line_width = payload.hatchLineWidth
            schema.gpu_hatch_randomness = payload.hatchRandomness
            schema.gpu_threshold_levels = payload.thresholdLevels
            schema.gpu_threshold_dither = payload.thresholdDither
        case .edgeField(let common, let geometry, let color, let payload):
            encodeCommon(common)
            encodeGeometry(geometry)
            encodeColor(color)
            schema.gpu_edge_variant = payload.variant.rawValue
            schema.gpu_line_strength = payload.lineStrength
            schema.gpu_field_intensity = payload.fieldIntensity
            schema.gpu_edge_line_count = payload.lineCount
            schema.gpu_edge_amplitude = payload.amplitude
            schema.gpu_edge_frequency = payload.frequency
            schema.gpu_edge_thickness = payload.thickness
            schema.gpu_edge_direction = payload.direction.rawValue
            schema.gpu_edge_animate = payload.animate
            schema.gpu_noise_type = payload.noiseType.rawValue
            schema.gpu_noise_octaves = payload.octaves
            schema.gpu_noise_speed = payload.speed
            schema.gpu_noise_distort_only = payload.distortOnly
            schema.gpu_edge_algorithm = payload.edgeAlgorithm.rawValue
            schema.gpu_edge_threshold = payload.edgeThreshold
            schema.gpu_edge_invert = payload.invert
            schema.gpu_edge_color = payload.edgeColor?.hex
            schema.gpu_contour_fill_mode = payload.contourFillMode.rawValue
            schema.gpu_contour_levels = payload.contourLevels
            schema.gpu_voronoi_cell_size = payload.cellSize
            schema.gpu_voronoi_edge_width = payload.edgeWidth
            schema.gpu_voronoi_randomize = payload.randomize
        case .glitch(let common, let geometry, let color, let payload):
            encodeCommon(common)
            encodeGeometry(geometry)
            encodeColor(color)
            schema.gpu_glitch_variant = payload.variant.rawValue
            schema.gpu_glitch_amount = payload.amount
            schema.gpu_glitch_threshold = payload.threshold
            schema.gpu_glitch_direction = payload.direction.rawValue
            schema.gpu_glitch_sort_mode = payload.sortMode.rawValue
            schema.gpu_glitch_streak_length = payload.streakLength
            schema.gpu_glitch_randomness = payload.randomness
            schema.gpu_glitch_reverse = payload.reverse
            schema.gpu_glitch_distortion = payload.distortion
            schema.gpu_glitch_color_bleed = payload.colorBleed
            schema.gpu_glitch_scanlines = payload.scanlines
            schema.gpu_glitch_tracking_error = payload.trackingError
        }
    }

    private static func decodeGPUEffectParams(kind: GPUEffectKind, schema: YAMLLayerSchema) -> GPUEffectParameters {
        let common = GPUEffectCommonParameters(
            brightness: schema.gpu_common_brightness ?? 0,
            contrast: schema.gpu_common_contrast ?? 1,
            saturation: schema.gpu_common_saturation ?? 1,
            hueRotation: schema.gpu_common_hue_rotation ?? 0,
            sharpness: schema.gpu_common_sharpness ?? 0,
            gamma: schema.gpu_common_gamma ?? 1
        )
        let geometry = GPUEffectGeometryParameters(
            scale: schema.gpu_scale ?? 1,
            spacing: schema.gpu_spacing ?? 1,
            outputWidth: schema.gpu_output_width ?? 320
        )
        let color = GPUEffectColorParameters(
            mode: schema.gpu_color_mode.flatMap(GPUEffectColorMode.init(rawValue:)) ?? .source,
            backgroundIntensity: schema.gpu_background_intensity ?? 0
        )

        switch kind {
        case .ascii, .matrixRain, .blockify, .dots:
            let variant = schema.gpu_text_variant.flatMap(TextCellVariant.init(rawValue:)) ?? textCellVariant(for: kind)
            let characterSet = schema.gpu_character_set.flatMap(GPUEffectCharacterSet.init(rawValue:)) ?? .classicASCII
            return .textCell(
                common: common,
                geometry: geometry,
                color: color,
                textCell: TextCellParameters(
                    characterSet: characterSet,
                    variant: variant,
                    speed: schema.gpu_text_speed ?? 0,
                    trailLength: schema.gpu_text_trail_length ?? 0,
                    direction: schema.gpu_text_direction.flatMap(TextCellFlowDirection.init(rawValue:)) ?? .down,
                    glow: schema.gpu_text_glow ?? 0,
                    backgroundOpacity: schema.gpu_text_background_opacity ?? 0,
                    threshold: schema.gpu_text_threshold ?? 0.5,
                    rainColor: schema.gpu_text_rain_color.flatMap { try? CodableColor(hex: $0) },
                    intensity: schema.gpu_text_intensity ?? 1,
                    foreground: schema.gpu_text_foreground_color.flatMap { try? CodableColor(hex: $0) },
                    background: schema.gpu_text_background_color.flatMap { try? CodableColor(hex: $0) },
                    dotShape: schema.gpu_dot_shape.flatMap(DotShape.init(rawValue:)) ?? .circle,
                    gridType: schema.gpu_dot_grid_type.flatMap(DotGridType.init(rawValue:)) ?? .square,
                    invert: schema.gpu_text_invert ?? false,
                    blockStyle: schema.gpu_block_style.flatMap(BlockStyle.init(rawValue:)) ?? .solid,
                    borderWidth: schema.gpu_block_border_width ?? 0,
                    borderColor: schema.gpu_block_border_color.flatMap { try? CodableColor(hex: $0) }
                )
            )
        case .dithering, .halftone, .threshold, .crosshatch:
            let variant = schema.gpu_sampling_variant.flatMap(PrintSamplingVariant.init(rawValue:)) ?? printSamplingVariant(for: kind)
            return .printSampling(
                common: common,
                geometry: geometry,
                color: color,
                printSampling: PrintSamplingParameters(
                    variant: variant,
                    sampleDensity: schema.gpu_sample_density ?? 0.5,
                    threshold: schema.gpu_sampling_threshold ?? 0.5,
                    algorithm: schema.gpu_dither_algorithm.flatMap(GPUDitherAlgorithm.init(rawValue:)) ?? .bayer8x8,
                    modulation: schema.gpu_modulation ?? 0,
                    sharpen: schema.gpu_sharpen ?? 0,
                    chromaticAberration: .init(
                        enabled: schema.gpu_chromatic_enabled ?? false,
                        maxDisplace: schema.gpu_chromatic_max_displace ?? 0,
                        redShift: schema.gpu_chromatic_red_shift ?? 0,
                        greenShift: schema.gpu_chromatic_green_shift ?? 0,
                        blueShift: schema.gpu_chromatic_blue_shift ?? 0
                    ),
                    foreground: schema.gpu_foreground_color.flatMap { try? CodableColor(hex: $0) },
                    background: schema.gpu_background_color.flatMap { try? CodableColor(hex: $0) },
                    halftoneShape: schema.gpu_halftone_shape.flatMap(HalftoneShape.init(rawValue:)) ?? .circle,
                    halftoneAngle: schema.gpu_halftone_angle ?? 0,
                    invert: schema.gpu_invert ?? false,
                    hatchDensity: schema.gpu_hatch_density ?? 0.5,
                    hatchLayers: schema.gpu_hatch_layers ?? 2,
                    hatchAngle: schema.gpu_hatch_angle ?? 45,
                    hatchLineWidth: schema.gpu_hatch_line_width ?? 0.25,
                    hatchRandomness: schema.gpu_hatch_randomness ?? 0,
                    thresholdLevels: schema.gpu_threshold_levels ?? 2,
                    thresholdDither: schema.gpu_threshold_dither ?? false
                )
            )
        case .contour, .edgeDetection, .waveLines, .noiseField, .voronoi:
            let variant = schema.gpu_edge_variant.flatMap(EdgeFieldVariant.init(rawValue:)) ?? edgeFieldVariant(for: kind)
            return .edgeField(
                common: common,
                geometry: geometry,
                color: color,
                edgeField: EdgeFieldParameters(
                    variant: variant,
                    lineStrength: schema.gpu_line_strength ?? 0.5,
                    fieldIntensity: schema.gpu_field_intensity ?? 0.5,
                    lineCount: schema.gpu_edge_line_count ?? 12,
                    amplitude: schema.gpu_edge_amplitude ?? 0.5,
                    frequency: schema.gpu_edge_frequency ?? 1.0,
                    thickness: schema.gpu_edge_thickness ?? 0.3,
                    direction: schema.gpu_edge_direction.flatMap(EdgeFieldDirection.init(rawValue:)) ?? .horizontal,
                    animate: schema.gpu_edge_animate ?? false,
                    noiseType: schema.gpu_noise_type.flatMap(NoiseFieldType.init(rawValue:)) ?? .value,
                    octaves: schema.gpu_noise_octaves ?? 1,
                    speed: schema.gpu_noise_speed ?? 0,
                    distortOnly: schema.gpu_noise_distort_only ?? false,
                    edgeAlgorithm: schema.gpu_edge_algorithm.flatMap(EdgeAlgorithm.init(rawValue:)) ?? .sobel,
                    edgeThreshold: schema.gpu_edge_threshold ?? 0.5,
                    invert: schema.gpu_edge_invert ?? false,
                    edgeColor: schema.gpu_edge_color.flatMap { try? CodableColor(hex: $0) },
                    contourFillMode: schema.gpu_contour_fill_mode.flatMap(ContourFillMode.init(rawValue:)) ?? .linesOnly,
                    contourLevels: schema.gpu_contour_levels ?? 8,
                    cellSize: schema.gpu_voronoi_cell_size ?? 16,
                    edgeWidth: schema.gpu_voronoi_edge_width ?? 0.25,
                    randomize: schema.gpu_voronoi_randomize ?? false
                )
            )
        case .pixelSort, .vhs:
            let variant = schema.gpu_glitch_variant.flatMap(GlitchVariant.init(rawValue:)) ?? glitchVariant(for: kind)
            return .glitch(
                common: common,
                geometry: geometry,
                color: color,
                glitch: GlitchParameters(
                    variant: variant,
                    amount: schema.gpu_glitch_amount ?? 0.5,
                    threshold: schema.gpu_glitch_threshold ?? 0.5,
                    direction: schema.gpu_glitch_direction.flatMap(GlitchDirection.init(rawValue:)) ?? .horizontal,
                    sortMode: schema.gpu_glitch_sort_mode.flatMap(PixelSortMode.init(rawValue:)) ?? .brightness,
                    streakLength: schema.gpu_glitch_streak_length ?? 0.5,
                    randomness: schema.gpu_glitch_randomness ?? 0,
                    reverse: schema.gpu_glitch_reverse ?? false,
                    distortion: schema.gpu_glitch_distortion ?? 0,
                    colorBleed: schema.gpu_glitch_color_bleed ?? 0,
                    scanlines: schema.gpu_glitch_scanlines ?? 0,
                    trackingError: schema.gpu_glitch_tracking_error ?? 0
                )
            )
        }
    }

    private static func textCellVariant(for kind: GPUEffectKind) -> TextCellVariant {
        switch kind {
        case .matrixRain: return .matrixRain
        case .blockify: return .blockify
        case .dots: return .dots
        default: return .ascii
        }
    }

    private static func printSamplingVariant(for kind: GPUEffectKind) -> PrintSamplingVariant {
        switch kind {
        case .halftone: return .halftone
        case .threshold: return .threshold
        case .crosshatch: return .crosshatch
        default: return .dithering
        }
    }

    private static func edgeFieldVariant(for kind: GPUEffectKind) -> EdgeFieldVariant {
        switch kind {
        case .edgeDetection: return .edgeDetection
        case .waveLines: return .waveLines
        case .voronoi: return .voronoi
        case .noiseField: return .noiseField
        default: return .contour
        }
    }

    private static func glitchVariant(for kind: GPUEffectKind) -> GlitchVariant {
        switch kind {
        case .vhs: return .vhs
        default: return .pixelSort
        }
    }

    private static func encodeShaderParams(_ params: ShaderStyleParams, into schema: inout YAMLLayerSchema) {
        switch params {
        case .ascii(let p):
            schema.shader_cell_size = p.cellSize
            schema.shader_edge_bias = p.edgeBias
            switch p.colorMode {
            case .manual(let foreground, let background):
                schema.shader_color_mode = "manual"
                schema.shader_foreground = foreground.hex
                schema.shader_background = background.hex
            case .dominantTwoTone(let flipped, let saturationShift, let lightnessShift):
                schema.shader_color_mode = "dominantTwoTone"
                if flipped { schema.shader_flipped = true }
                if saturationShift != 0 { schema.shader_saturation_shift = saturationShift }
                if lightnessShift != 0 { schema.shader_lightness_shift = lightnessShift }
            case .source(let background):
                schema.shader_color_mode = "source"
                schema.shader_background = background.hex
            case .gradient(let color1, let color2, let background):
                schema.shader_color_mode = "gradient"
                schema.shader_color1 = color1.hex
                schema.shader_color2 = color2.hex
                schema.shader_background = background.hex
            }
            schema.shader_invert = p.invert
            if p.exposure != 1.0 { schema.shader_exposure = p.exposure }
            if p.attenuation != 1.0 { schema.shader_attenuation = p.attenuation }
            if p.blackLevel != 0.0 { schema.shader_black_level = p.blackLevel }
        case .crimewave(let p):
            schema.shader_neon = p.neon
            schema.shader_softness = p.softness
            schema.shader_contrast = p.contrast
            schema.shader_grain = p.grain
        case .narc(let p):
            schema.shader_contrast = p.contrast
            schema.shader_crush = p.crush
            schema.shader_temperature = p.temperature
            schema.shader_grain = p.grain
        case .shiba(let p):
            schema.shader_warmth = p.warmth
            schema.shader_softness = p.softness
            schema.shader_saturation = p.saturation
            schema.shader_grain = p.grain
        case .pixelSort(let p):
            schema.shader_threshold = p.threshold
            schema.shader_direction = p.direction.rawValue
            schema.shader_span = p.span
            schema.shader_amount = p.amount
        case .distantPast(let p):
            schema.shader_palette_depth = p.paletteDepth
            schema.shader_fade = p.fade
            schema.shader_softness = p.softness
            schema.shader_grain = p.grain
        case .crt(let p):
            schema.shader_curvature = p.curvature
            schema.shader_line_size = p.lineSize
            schema.shader_line_strength = p.lineStrength
            schema.shader_brightness = p.brightness
            schema.shader_vignette = p.vignette
        case .halftone(let p):
            schema.shader_dot_size = p.dotSize
            schema.shader_contrast = p.contrast
            if p.monochrome { schema.shader_monochrome = true }
        case .kuwahara(let p):
            schema.shader_kernel_size = p.kernelSize
            schema.shader_sharpness = p.sharpness
        }
    }

    private static func decodeShaderParams(style: ShaderStyle, schema: YAMLLayerSchema) -> ShaderStyleParams {
        switch style {
        case .ascii:
            let colorMode: ASCIIColorMode
            switch schema.shader_color_mode ?? "manual" {
            case "dominantTwoTone":
                colorMode = .dominantTwoTone(
                    flipped: schema.shader_flipped ?? false,
                    saturationShift: schema.shader_saturation_shift ?? 0,
                    lightnessShift: schema.shader_lightness_shift ?? 0
                )
            case "source":
                colorMode = .source(
                    background: (schema.shader_background.flatMap { try? CodableColor(hex: $0) }) ?? .black
                )
            case "gradient":
                colorMode = .gradient(
                    color1: (schema.shader_color1.flatMap { try? CodableColor(hex: $0) }) ?? .black,
                    color2: (schema.shader_color2.flatMap { try? CodableColor(hex: $0) }) ?? .white,
                    background: (schema.shader_background.flatMap { try? CodableColor(hex: $0) }) ?? .black
                )
            default:
                colorMode = .manual(
                    foreground: (schema.shader_foreground.flatMap { try? CodableColor(hex: $0) }) ?? .white,
                    background: (schema.shader_background.flatMap { try? CodableColor(hex: $0) }) ?? .black
                )
            }
            return .ascii(ASCIIShaderParams(
                cellSize: schema.shader_cell_size ?? 10,
                edgeBias: schema.shader_edge_bias ?? 0.5,
                colorMode: colorMode,
                invert: schema.shader_invert ?? false,
                exposure: schema.shader_exposure ?? 1.0,
                attenuation: schema.shader_attenuation ?? 1.0,
                blackLevel: schema.shader_black_level ?? 0.0
            ))
        case .crimewave:
            return .crimewave(CrimewaveShaderParams(
                neon: schema.shader_neon ?? 0.7,
                softness: schema.shader_softness ?? 0.4,
                contrast: schema.shader_contrast ?? 1.15,
                grain: schema.shader_grain ?? 0.2
            ))
        case .narc:
            return .narc(NarcShaderParams(
                contrast: schema.shader_contrast ?? 1.25,
                crush: schema.shader_crush ?? 0.35,
                temperature: schema.shader_temperature ?? -0.1,
                grain: schema.shader_grain ?? 0.25
            ))
        case .shiba:
            return .shiba(ShibaShaderParams(
                warmth: schema.shader_warmth ?? 0.2,
                softness: schema.shader_softness ?? 0.3,
                saturation: schema.shader_saturation ?? 0.15,
                grain: schema.shader_grain ?? 0.1
            ))
        case .pixelSort:
            return .pixelSort(PixelSortShaderParams(
                threshold: schema.shader_threshold ?? 0.65,
                direction: schema.shader_direction.flatMap(PixelSortDirection.init(rawValue:)) ?? .horizontal,
                span: schema.shader_span ?? 24,
                amount: schema.shader_amount ?? 1.0
            ))
        case .distantPast:
            return .distantPast(DistantPastShaderParams(
                paletteDepth: schema.shader_palette_depth ?? 6,
                fade: schema.shader_fade ?? 0.3,
                softness: schema.shader_softness ?? 0.2,
                grain: schema.shader_grain ?? 0.15
            ))
        case .crt:
            return .crt(CRTShaderParams(
                curvature: schema.shader_curvature ?? 6.0,
                lineSize: schema.shader_line_size ?? 1,
                lineStrength: schema.shader_line_strength ?? 1.0,
                brightness: schema.shader_brightness ?? 0.0,
                vignette: schema.shader_vignette ?? 30.0
            ))
        case .halftone:
            return .halftone(HalftoneShaderParams(
                dotSize: schema.shader_dot_size ?? 1.0,
                contrast: schema.shader_contrast ?? 1.0,
                monochrome: schema.shader_monochrome ?? false
            ))
        case .kuwahara:
            return .kuwahara(KuwaharaShaderParams(
                kernelSize: schema.shader_kernel_size ?? 4,
                sharpness: schema.shader_sharpness ?? 8.0
            ))
        }
    }

    private static func parseRatio(_ str: String) -> (Int, Int) {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return (1, 1) }
        return (parts[0], parts[1])
    }

    private static func decodeFill(_ schema: YAMLLayerSchema) -> LayerFill {
        switch schema.fill {
        case "dominant":
            return .dominantColor(GradientParams(
                saturationShift: schema.gradient_saturation ?? 0,
                lightnessShift: schema.gradient_lightness ?? 0
            ))
        case "gradient_linear":
            return .gradientLinear(GradientParams(
                saturationShift: schema.gradient_saturation ?? 0,
                lightnessShift: schema.gradient_lightness ?? 0
            ))
        case "gradient_radial":
            return .gradientRadial(GradientParams(
                saturationShift: schema.gradient_saturation ?? 0,
                lightnessShift: schema.gradient_lightness ?? 0
            ))
        case "color":
            if let hex = schema.fill_color, let c = try? CodableColor(hex: hex) {
                return .color(c)
            }
            return .color(.white)
        default:
            if let hex = schema.fill_color, let c = try? CodableColor(hex: hex) {
                return .color(c)
            }
            return .color(.white)
        }
    }
}
