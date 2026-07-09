import Foundation

public enum GPUEffectColorMode: String, Codable, Hashable, Sendable, CaseIterable {
    case source
    case foregroundBackground
    case monochrome
    case palette
}

public struct GPUEffectCommonParameters: Codable, Equatable, Sendable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var hueRotation: Double
    public var gamma: Double

    public init(
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        hueRotation: Double = 0,
        gamma: Double = 1
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hueRotation = hueRotation
        self.gamma = gamma
    }
}

public struct GPUEffectGeometryParameters: Codable, Equatable, Sendable {
    public var scale: Double
    public var spacing: Double
    public var outputWidth: Int

    public init(scale: Double = 1, spacing: Double = 1, outputWidth: Int = 320) {
        self.scale = scale
        self.spacing = spacing
        self.outputWidth = outputWidth
    }
}

public struct GPUEffectColorParameters: Codable, Equatable, Sendable {
    public var mode: GPUEffectColorMode
    public var backgroundIntensity: Double
    /// Quantization targets for `.palette` mode, ordered as displayed in the
    /// palette editor. `nil` (the default, and what every pre-palette file
    /// decodes to) falls back to `VintagePalette.gameBoy` at render time.
    /// Renderers upload at most `FramerColorUniformsLayout.maxPaletteColors`
    /// (16) entries.
    public var palette: [CodableColor]?

    public init(
        mode: GPUEffectColorMode = .source,
        backgroundIntensity: Double = 0,
        palette: [CodableColor]? = nil
    ) {
        self.mode = mode
        self.backgroundIntensity = backgroundIntensity
        self.palette = palette
    }
}

public enum GPUEffectCharacterSet: String, Codable, Hashable, Sendable, CaseIterable {
    case classicASCII
    case blocks
    case binary
    case dense
}

public enum TextCellVariant: String, Codable, Hashable, Sendable, CaseIterable {
    case ascii
    case matrixRain
    case blockify
    case dots
}

public enum TextCellFlowDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case down
    case up
    case left
    case right
}

public enum DotShape: String, Codable, Hashable, Sendable, CaseIterable {
    case circle
    case square
    case diamond
}

public enum DotGridType: String, Codable, Hashable, Sendable, CaseIterable {
    case square
    case hex
}

public enum BlockStyle: String, Codable, Hashable, Sendable, CaseIterable {
    case solid
    case shaded
    case outlined
}

public struct TextCellParameters: Equatable, Sendable {
    public var characterSet: GPUEffectCharacterSet
    public var variant: TextCellVariant
    public var speed: Double
    public var trailLength: Double
    public var direction: TextCellFlowDirection
    public var glow: Double
    public var backgroundOpacity: Double
    public var threshold: Double
    public var rainColor: CodableColor?
    public var intensity: Double
    public var foreground: CodableColor?
    public var background: CodableColor?
    public var dotShape: DotShape
    public var gridType: DotGridType
    public var invert: Bool
    public var blockStyle: BlockStyle
    public var borderWidth: Double
    public var borderColor: CodableColor?
    /// Dots: dot radius multiplier (shader formula
    /// `radius = baseSpacing * 0.4 * sizeMultiplier * (0.2 + luma*0.8)`).
    /// User-facing range [0.1, 2.0]; 1.0 matches the grainrad reference.
    public var sizeMultiplier: Double

    public init(
        characterSet: GPUEffectCharacterSet = .classicASCII,
        variant: TextCellVariant = .ascii,
        speed: Double = 0,
        trailLength: Double = 0,
        direction: TextCellFlowDirection = .down,
        glow: Double = 0,
        backgroundOpacity: Double = 0,
        threshold: Double = 0.5,
        rainColor: CodableColor? = nil,
        intensity: Double = 1,
        foreground: CodableColor? = nil,
        background: CodableColor? = nil,
        dotShape: DotShape = .circle,
        gridType: DotGridType = .square,
        invert: Bool = false,
        blockStyle: BlockStyle = .solid,
        borderWidth: Double = 0,
        borderColor: CodableColor? = nil,
        sizeMultiplier: Double = 1
    ) {
        self.characterSet = characterSet
        self.variant = variant
        self.speed = speed
        self.trailLength = trailLength
        self.direction = direction
        self.glow = glow
        self.backgroundOpacity = backgroundOpacity
        self.threshold = threshold
        self.rainColor = rainColor
        self.intensity = intensity
        self.foreground = foreground
        self.background = background
        self.dotShape = dotShape
        self.gridType = gridType
        self.invert = invert
        self.blockStyle = blockStyle
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.sizeMultiplier = sizeMultiplier
    }
}

extension TextCellParameters: Codable {
    // Every field decoded via `decodeIfPresent` with a default so saved
    // projects from earlier builds (pre-sizeMultiplier, pre-blockStyle, etc.)
    // round-trip cleanly instead of failing with `keyNotFound`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            characterSet: try c.decodeIfPresent(GPUEffectCharacterSet.self, forKey: .characterSet) ?? .classicASCII,
            variant: try c.decodeIfPresent(TextCellVariant.self, forKey: .variant) ?? .ascii,
            speed: try c.decodeIfPresent(Double.self, forKey: .speed) ?? 0,
            trailLength: try c.decodeIfPresent(Double.self, forKey: .trailLength) ?? 0,
            direction: try c.decodeIfPresent(TextCellFlowDirection.self, forKey: .direction) ?? .down,
            glow: try c.decodeIfPresent(Double.self, forKey: .glow) ?? 0,
            backgroundOpacity: try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0,
            threshold: try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.5,
            rainColor: try c.decodeIfPresent(CodableColor.self, forKey: .rainColor),
            intensity: try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1,
            foreground: try c.decodeIfPresent(CodableColor.self, forKey: .foreground),
            background: try c.decodeIfPresent(CodableColor.self, forKey: .background),
            dotShape: try c.decodeIfPresent(DotShape.self, forKey: .dotShape) ?? .circle,
            gridType: try c.decodeIfPresent(DotGridType.self, forKey: .gridType) ?? .square,
            invert: try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false,
            blockStyle: try c.decodeIfPresent(BlockStyle.self, forKey: .blockStyle) ?? .solid,
            borderWidth: try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0,
            borderColor: try c.decodeIfPresent(CodableColor.self, forKey: .borderColor),
            sizeMultiplier: try c.decodeIfPresent(Double.self, forKey: .sizeMultiplier) ?? 1
        )
    }
}

public enum PrintSamplingVariant: String, Codable, Hashable, Sendable, CaseIterable {
    case dithering
    case halftone
    case threshold
    case crosshatch
}

public enum GPUDitherAlgorithm: String, Codable, Hashable, Sendable, CaseIterable {
    case bayer8x8
    case bayer4x4
    case floydSteinberg
}

public enum HalftoneShape: String, Codable, Hashable, Sendable, CaseIterable {
    case circle
    case square
    case diamond
}

public struct PrintSamplingParameters: Codable, Equatable, Sendable {
    public var variant: PrintSamplingVariant
    /// Scales intensity of CPU fallback output for halftone/threshold/
    /// crosshatch. Not consumed by any user-facing GPU shader; only
    /// affects the CPU path when Metal is unavailable. Kept because it's
    /// still meaningful there.
    public var sampleDensity: Double
    public var threshold: Double
    public var algorithm: GPUDitherAlgorithm
    public var foreground: CodableColor?
    public var background: CodableColor?
    public var halftoneShape: HalftoneShape
    public var halftoneAngle: Double
    public var invert: Bool
    public var hatchDensity: Double
    public var hatchLayers: Int
    public var hatchAngle: Double
    public var hatchLineWidth: Double
    public var hatchRandomness: Double
    public var thresholdLevels: Int
    public var thresholdDither: Bool

    public init(
        variant: PrintSamplingVariant = .dithering,
        sampleDensity: Double = 0.5,
        threshold: Double = 0.5,
        algorithm: GPUDitherAlgorithm = .bayer8x8,
        foreground: CodableColor? = nil,
        background: CodableColor? = nil,
        halftoneShape: HalftoneShape = .circle,
        halftoneAngle: Double = 0,
        invert: Bool = false,
        hatchDensity: Double = 0.5,
        hatchLayers: Int = 2,
        hatchAngle: Double = 45,
        hatchLineWidth: Double = 0.25,
        hatchRandomness: Double = 0,
        thresholdLevels: Int = 2,
        thresholdDither: Bool = false
    ) {
        self.variant = variant
        self.sampleDensity = sampleDensity
        self.threshold = threshold
        self.algorithm = algorithm
        self.foreground = foreground
        self.background = background
        self.halftoneShape = halftoneShape
        self.halftoneAngle = halftoneAngle
        self.invert = invert
        self.hatchDensity = hatchDensity
        self.hatchLayers = hatchLayers
        self.hatchAngle = hatchAngle
        self.hatchLineWidth = hatchLineWidth
        self.hatchRandomness = hatchRandomness
        self.thresholdLevels = thresholdLevels
        self.thresholdDither = thresholdDither
    }
}

extension PrintSamplingParameters {
    // Same back-compat strategy as TextCellParameters: every field decodes
    // via `decodeIfPresent` with the init default so saved projects from
    // builds that predate a field round-trip cleanly instead of failing
    // with `keyNotFound`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            variant: try c.decodeIfPresent(PrintSamplingVariant.self, forKey: .variant) ?? .dithering,
            sampleDensity: try c.decodeIfPresent(Double.self, forKey: .sampleDensity) ?? 0.5,
            threshold: try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.5,
            algorithm: try c.decodeIfPresent(GPUDitherAlgorithm.self, forKey: .algorithm) ?? .bayer8x8,
            foreground: try c.decodeIfPresent(CodableColor.self, forKey: .foreground),
            background: try c.decodeIfPresent(CodableColor.self, forKey: .background),
            halftoneShape: try c.decodeIfPresent(HalftoneShape.self, forKey: .halftoneShape) ?? .circle,
            halftoneAngle: try c.decodeIfPresent(Double.self, forKey: .halftoneAngle) ?? 0,
            invert: try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false,
            hatchDensity: try c.decodeIfPresent(Double.self, forKey: .hatchDensity) ?? 0.5,
            hatchLayers: try c.decodeIfPresent(Int.self, forKey: .hatchLayers) ?? 2,
            hatchAngle: try c.decodeIfPresent(Double.self, forKey: .hatchAngle) ?? 45,
            hatchLineWidth: try c.decodeIfPresent(Double.self, forKey: .hatchLineWidth) ?? 0.25,
            hatchRandomness: try c.decodeIfPresent(Double.self, forKey: .hatchRandomness) ?? 0,
            thresholdLevels: try c.decodeIfPresent(Int.self, forKey: .thresholdLevels) ?? 2,
            thresholdDither: try c.decodeIfPresent(Bool.self, forKey: .thresholdDither) ?? false
        )
    }
}

public enum EdgeFieldVariant: String, Codable, Hashable, Sendable, CaseIterable {
    case contour
    case edgeDetection
    case waveLines
    case voronoi
    case noiseField
}

public enum EdgeFieldDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

public enum NoiseFieldType: String, Codable, Hashable, Sendable, CaseIterable {
    case value
    case simplex
    case cellular
}

public enum EdgeAlgorithm: String, Codable, Hashable, Sendable, CaseIterable {
    case sobel
    case laplacian
}

public enum ContourFillMode: String, Codable, Hashable, Sendable, CaseIterable {
    case linesOnly
    case filledBands
}

public struct EdgeFieldParameters: Codable, Equatable, Sendable {
    public var variant: EdgeFieldVariant
    public var lineStrength: Double
    public var fieldIntensity: Double
    public var lineCount: Double
    public var amplitude: Double
    public var frequency: Double
    public var thickness: Double
    public var direction: EdgeFieldDirection
    public var noiseType: NoiseFieldType
    public var octaves: Int
    public var edgeAlgorithm: EdgeAlgorithm
    public var edgeThreshold: Double
    public var invert: Bool
    public var edgeColor: CodableColor?
    public var contourFillMode: ContourFillMode
    public var contourLevels: Int
    public var cellSize: Double
    public var edgeWidth: Double
    public var randomize: Bool

    public init(
        variant: EdgeFieldVariant = .contour,
        lineStrength: Double = 0.5,
        fieldIntensity: Double = 0.5,
        lineCount: Double = 12,
        amplitude: Double = 0.5,
        frequency: Double = 1.0,
        thickness: Double = 0.3,
        direction: EdgeFieldDirection = .horizontal,
        noiseType: NoiseFieldType = .value,
        octaves: Int = 1,
        edgeAlgorithm: EdgeAlgorithm = .sobel,
        edgeThreshold: Double = 0.5,
        invert: Bool = false,
        edgeColor: CodableColor? = nil,
        contourFillMode: ContourFillMode = .linesOnly,
        contourLevels: Int = 8,
        cellSize: Double = 16,
        edgeWidth: Double = 0.25,
        randomize: Bool = false
    ) {
        self.variant = variant
        self.lineStrength = lineStrength
        self.fieldIntensity = fieldIntensity
        self.lineCount = lineCount
        self.amplitude = amplitude
        self.frequency = frequency
        self.thickness = thickness
        self.direction = direction
        self.noiseType = noiseType
        self.octaves = octaves
        self.edgeAlgorithm = edgeAlgorithm
        self.edgeThreshold = edgeThreshold
        self.invert = invert
        self.edgeColor = edgeColor
        self.contourFillMode = contourFillMode
        self.contourLevels = contourLevels
        self.cellSize = cellSize
        self.edgeWidth = edgeWidth
        self.randomize = randomize
    }
}

extension EdgeFieldParameters {
    // Same back-compat strategy as TextCellParameters: every field decodes
    // via `decodeIfPresent` with the init default so saved projects from
    // builds that predate a field round-trip cleanly instead of failing
    // with `keyNotFound`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            variant: try c.decodeIfPresent(EdgeFieldVariant.self, forKey: .variant) ?? .contour,
            lineStrength: try c.decodeIfPresent(Double.self, forKey: .lineStrength) ?? 0.5,
            fieldIntensity: try c.decodeIfPresent(Double.self, forKey: .fieldIntensity) ?? 0.5,
            lineCount: try c.decodeIfPresent(Double.self, forKey: .lineCount) ?? 12,
            amplitude: try c.decodeIfPresent(Double.self, forKey: .amplitude) ?? 0.5,
            frequency: try c.decodeIfPresent(Double.self, forKey: .frequency) ?? 1.0,
            thickness: try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 0.3,
            direction: try c.decodeIfPresent(EdgeFieldDirection.self, forKey: .direction) ?? .horizontal,
            noiseType: try c.decodeIfPresent(NoiseFieldType.self, forKey: .noiseType) ?? .value,
            octaves: try c.decodeIfPresent(Int.self, forKey: .octaves) ?? 1,
            edgeAlgorithm: try c.decodeIfPresent(EdgeAlgorithm.self, forKey: .edgeAlgorithm) ?? .sobel,
            edgeThreshold: try c.decodeIfPresent(Double.self, forKey: .edgeThreshold) ?? 0.5,
            invert: try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false,
            edgeColor: try c.decodeIfPresent(CodableColor.self, forKey: .edgeColor),
            contourFillMode: try c.decodeIfPresent(ContourFillMode.self, forKey: .contourFillMode) ?? .linesOnly,
            contourLevels: try c.decodeIfPresent(Int.self, forKey: .contourLevels) ?? 8,
            cellSize: try c.decodeIfPresent(Double.self, forKey: .cellSize) ?? 16,
            edgeWidth: try c.decodeIfPresent(Double.self, forKey: .edgeWidth) ?? 0.25,
            randomize: try c.decodeIfPresent(Bool.self, forKey: .randomize) ?? false
        )
    }
}

public enum GlitchVariant: String, Codable, Hashable, Sendable, CaseIterable {
    case pixelSort
    case vhs
}

public enum GlitchDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

public enum PixelSortMode: String, Codable, Hashable, Sendable, CaseIterable {
    case brightness
    case luminance
    case hue
}

public struct GlitchParameters: Codable, Equatable, Sendable {
    public var variant: GlitchVariant
    public var amount: Double
    public var threshold: Double
    public var direction: GlitchDirection
    public var sortMode: PixelSortMode
    public var streakLength: Double
    public var randomness: Double
    public var reverse: Bool
    public var distortion: Double
    public var colorBleed: Double
    public var scanlines: Double
    public var trackingError: Double

    public init(
        variant: GlitchVariant = .pixelSort,
        amount: Double = 0.5,
        threshold: Double = 0.5,
        direction: GlitchDirection = .horizontal,
        sortMode: PixelSortMode = .brightness,
        streakLength: Double = 0.5,
        randomness: Double = 0,
        reverse: Bool = false,
        distortion: Double = 0,
        colorBleed: Double = 0,
        scanlines: Double = 0,
        trackingError: Double = 0
    ) {
        self.variant = variant
        self.amount = amount
        self.threshold = threshold
        self.direction = direction
        self.sortMode = sortMode
        self.streakLength = streakLength
        self.randomness = randomness
        self.reverse = reverse
        self.distortion = distortion
        self.colorBleed = colorBleed
        self.scanlines = scanlines
        self.trackingError = trackingError
    }
}

extension GlitchParameters {
    // Same back-compat strategy as TextCellParameters: every field decodes
    // via `decodeIfPresent` with the init default so saved projects from
    // builds that predate a field round-trip cleanly instead of failing
    // with `keyNotFound`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            variant: try c.decodeIfPresent(GlitchVariant.self, forKey: .variant) ?? .pixelSort,
            amount: try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0.5,
            threshold: try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.5,
            direction: try c.decodeIfPresent(GlitchDirection.self, forKey: .direction) ?? .horizontal,
            sortMode: try c.decodeIfPresent(PixelSortMode.self, forKey: .sortMode) ?? .brightness,
            streakLength: try c.decodeIfPresent(Double.self, forKey: .streakLength) ?? 0.5,
            randomness: try c.decodeIfPresent(Double.self, forKey: .randomness) ?? 0,
            reverse: try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? false,
            distortion: try c.decodeIfPresent(Double.self, forKey: .distortion) ?? 0,
            colorBleed: try c.decodeIfPresent(Double.self, forKey: .colorBleed) ?? 0,
            scanlines: try c.decodeIfPresent(Double.self, forKey: .scanlines) ?? 0,
            trackingError: try c.decodeIfPresent(Double.self, forKey: .trackingError) ?? 0
        )
    }
}

public enum GPUEffectParameters: Codable, Equatable, Sendable {
    case textCell(common: GPUEffectCommonParameters, geometry: GPUEffectGeometryParameters, color: GPUEffectColorParameters, textCell: TextCellParameters)
    case printSampling(common: GPUEffectCommonParameters, geometry: GPUEffectGeometryParameters, color: GPUEffectColorParameters, printSampling: PrintSamplingParameters)
    case edgeField(common: GPUEffectCommonParameters, geometry: GPUEffectGeometryParameters, color: GPUEffectColorParameters, edgeField: EdgeFieldParameters)
    case glitch(common: GPUEffectCommonParameters, geometry: GPUEffectGeometryParameters, color: GPUEffectColorParameters, glitch: GlitchParameters)

    private enum CodingKeys: String, CodingKey {
        case family, common, geometry, color, textCell, printSampling, edgeField, glitch
    }

    private enum Family: String, Codable {
        case textCell, printSampling, edgeField, glitch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let family = try container.decode(Family.self, forKey: .family)
        let common = try container.decode(GPUEffectCommonParameters.self, forKey: .common)
        let geometry = try container.decode(GPUEffectGeometryParameters.self, forKey: .geometry)
        let color = try container.decode(GPUEffectColorParameters.self, forKey: .color)

        switch family {
        case .textCell:
            let payload = try container.decode(TextCellParameters.self, forKey: .textCell)
            self = .textCell(common: common, geometry: geometry, color: color, textCell: payload)
        case .printSampling:
            let payload = try container.decode(PrintSamplingParameters.self, forKey: .printSampling)
            self = .printSampling(common: common, geometry: geometry, color: color, printSampling: payload)
        case .edgeField:
            let payload = try container.decode(EdgeFieldParameters.self, forKey: .edgeField)
            self = .edgeField(common: common, geometry: geometry, color: color, edgeField: payload)
        case .glitch:
            let payload = try container.decode(GlitchParameters.self, forKey: .glitch)
            self = .glitch(common: common, geometry: geometry, color: color, glitch: payload)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .textCell(let common, let geometry, let color, let payload):
            try container.encode(Family.textCell, forKey: .family)
            try container.encode(common, forKey: .common)
            try container.encode(geometry, forKey: .geometry)
            try container.encode(color, forKey: .color)
            try container.encode(payload, forKey: .textCell)
        case .printSampling(let common, let geometry, let color, let payload):
            try container.encode(Family.printSampling, forKey: .family)
            try container.encode(common, forKey: .common)
            try container.encode(geometry, forKey: .geometry)
            try container.encode(color, forKey: .color)
            try container.encode(payload, forKey: .printSampling)
        case .edgeField(let common, let geometry, let color, let payload):
            try container.encode(Family.edgeField, forKey: .family)
            try container.encode(common, forKey: .common)
            try container.encode(geometry, forKey: .geometry)
            try container.encode(color, forKey: .color)
            try container.encode(payload, forKey: .edgeField)
        case .glitch(let common, let geometry, let color, let payload):
            try container.encode(Family.glitch, forKey: .family)
            try container.encode(common, forKey: .common)
            try container.encode(geometry, forKey: .geometry)
            try container.encode(color, forKey: .color)
            try container.encode(payload, forKey: .glitch)
        }
    }
}

public struct GPUEffectLayerParams: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var kind: GPUEffectKind
    public var params: GPUEffectParameters
    /// Layer-stack opacity consumed by `LayerCompositor.compose` when
    /// laying the effect's rendered output onto the current pipeline
    /// buffer. Default 1.0 preserves pre-blend-modes behaviour.
    /// Orthogonal to per-variant intensity fields (e.g.
    /// `TextCellParameters.intensity`) which control the shader's
    /// internal mix before the compose step.
    public var opacity: Double
    /// Blend mode used by the final compose. `.normal` at opacity 1.0
    /// matches the pre-blend-modes pipeline exactly.
    public var blendMode: LayerBlendMode

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        kind: GPUEffectKind,
        params: GPUEffectParameters,
        opacity: Double = 1.0,
        blendMode: LayerBlendMode = .normal
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.params = params
        self.opacity = max(0, min(1, opacity))
        self.blendMode = blendMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, kind, params, opacity, blendMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            kind: try c.decode(GPUEffectKind.self, forKey: .kind),
            params: try c.decode(GPUEffectParameters.self, forKey: .params),
            opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0,
            blendMode: try c.decodeIfPresent(LayerBlendMode.self, forKey: .blendMode) ?? .normal
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(kind, forKey: .kind)
        try c.encode(params, forKey: .params)
        if opacity != 1.0 { try c.encode(opacity, forKey: .opacity) }
        if blendMode != .normal { try c.encode(blendMode, forKey: .blendMode) }
    }
}
