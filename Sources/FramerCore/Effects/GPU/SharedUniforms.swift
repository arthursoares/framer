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
    public var mode: UInt32 = 0
    public var backgroundIntensity: Float = 1
    public var _pad0: Float = 0
    public var _pad1: Float = 0
    public var foregroundRGBA: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    public var backgroundRGBA: SIMD4<Float> = SIMD4(0, 0, 0, 1)

    public init() {}
}
