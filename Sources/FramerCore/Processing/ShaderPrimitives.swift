import Foundation

enum ShaderPrimitives {
    @inline(__always)
    static func clamp01(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    @inline(__always)
    static func mix(_ original: UInt8, _ effect: UInt8, intensity: Double) -> UInt8 {
        let t = clamp01(intensity)
        let blended = Double(original) * (1.0 - t) + Double(effect) * t
        return UInt8(max(0, min(255, blended.rounded())))
    }

    @inline(__always)
    static func reducePaletteComponent(_ value: UInt8, levels: Int) -> UInt8 {
        let clampedLevels = max(2, min(32, levels))
        let stepCount = Double(clampedLevels - 1)
        let normalized = Double(value) / 255.0
        let bucket = (normalized * stepCount).rounded()
        let reduced = bucket / stepCount
        return UInt8(max(0, min(255, (reduced * 255.0).rounded())))
    }
}
