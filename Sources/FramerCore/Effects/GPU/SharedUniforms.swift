// SharedUniforms.swift
// Swift mirrors of the common header structs declared in ShaderCommon.h.
// Every effect's Swift uniform struct should embed these (in the same order)
// when its MSL counterpart embeds the matching MSL types — this keeps memory
// layout symmetrical without re-declaring the header in every Swift file.
//
// Layout discipline:
//   - Field order, types, and explicit padding must match the MSL structs
//     exactly (see Sources/FramerCore/Effects/Metal/ShaderCommon.h).
//   - SIMD4<Float> has 16-byte alignment in both Swift and MSL, so `_pad`
//     fields exist where the alignment requires extra bytes.
//   - When you change the C header, change the Swift mirror in the same patch.
//
// These layouts are present even when an effect doesn't use them, so the rest
// of its uniform struct sits at the same offset in MSL and Swift.

import Foundation

public struct FramerCommonUniformsLayout {
    public var brightness: Float = 0
    public var contrast: Float = 0
    public var saturation: Float = 1
    public var hueRotation: Float = 0
    /// Retired — `GPUEffectCommonParameters.sharpness` was removed (no
    /// shader ever consumed it). The slot stays, always 0, because the
    /// Metal-side struct layout (ShaderCommon.h) still declares it.
    public var sharpness: Float = 0
    public var gamma: Float = 1

    public init() {}
}

public struct FramerGeometryUniformsLayout {
    public var scale: Float = 1
    public var spacing: Float = 1
    public var outputWidth: Float = 0
    public var _pad: Float = 0

    public init() {}
}

public struct FramerColorUniformsLayout {
    /// Mirrors FRAMER_MAX_PALETTE in ShaderCommon.h.
    public static let maxPaletteColors = 16

    public var mode: UInt32 = 0
    public var backgroundIntensity: Float = 1
    public var paletteCount: UInt32 = 0
    public var _pad1: Float = 0
    public var foregroundRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    public var backgroundRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)
    /// Quantization targets for palette mode (mode == 3). 16 × float4 =
    /// 256 bytes; slot order matches the MSL `palette[]` indexing.
    public var palette: (
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    ) = (
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero
    )

    public init() {}

    /// Upload up to `maxPaletteColors` entries and set `paletteCount`.
    public mutating func setPalette(_ colors: [SIMD4<Float>]) {
        let capped = Array(colors.prefix(Self.maxPaletteColors))
        paletteCount = UInt32(capped.count)
        for (i, c) in capped.enumerated() {
            switch i {
            case 0:  palette.0  = c
            case 1:  palette.1  = c
            case 2:  palette.2  = c
            case 3:  palette.3  = c
            case 4:  palette.4  = c
            case 5:  palette.5  = c
            case 6:  palette.6  = c
            case 7:  palette.7  = c
            case 8:  palette.8  = c
            case 9:  palette.9  = c
            case 10: palette.10 = c
            case 11: palette.11 = c
            case 12: palette.12 = c
            case 13: palette.13 = c
            case 14: palette.14 = c
            default: palette.15 = c
            }
        }
    }
}
