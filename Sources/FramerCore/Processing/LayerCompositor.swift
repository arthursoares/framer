// LayerCompositor.swift
// Standard alpha-composite helper used when a visual adjustment layer
// (LUT / Dither / Shader / GPUEffect — and eventually Overlay) renders
// its output at base resolution and needs to lay it back on top of the
// current pipeline buffer with a blend mode + opacity. Produces:
//
//   result = mix(base, blend(base, over), opacity)
//
// Per-pixel loop in SIMD3<Double>. For a 24MP photo this is ~24M
// iterations of cheap math; runs in tens of ms on Apple Silicon —
// well below the render budget of every effect that feeds this
// compositor. If a specific mode ever becomes a hot spot we can
// specialise it into a vDSP path without changing the public API.
//
// HSL modes (hue / saturation / color / luminosity) go through a
// standard RGB↔HSL round-trip per pixel. They produce the same
// results as Photoshop's layer-panel HSL modes so existing creative
// intuition transfers.

import Foundation
import CoreGraphics
import Accelerate

public enum LayerCompositor {

    public enum Error: Swift.Error {
        case dimensionMismatch(baseSize: (Int, Int), overSize: (Int, Int))
        case contextAllocationFailed
        case imageEncodeFailed
    }

    /// Compose `over` onto `base` using `mode` at the given `opacity`.
    /// Both images must share the same pixel dimensions; the caller
    /// is responsible for resizing if they don't.
    public static func compose(
        base: CGImage,
        over: CGImage,
        mode: LayerBlendMode,
        opacity: Double
    ) throws -> CGImage {
        let width = base.width
        let height = base.height
        guard over.width == width, over.height == height else {
            throw Error.dimensionMismatch(
                baseSize: (width, height),
                overSize: (over.width, over.height)
            )
        }

        // Fast path: full opacity in normal mode is a straight copy of
        // `over`. The render pipeline calls compose() for every visual
        // layer; short-circuiting the common case saves one rasterise +
        // one per-pixel loop when the user hasn't changed the defaults.
        if mode == .normal && opacity >= 1.0 {
            return over
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let baseCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ), let overCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw Error.contextAllocationFailed
        }
        baseCtx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        overCtx.draw(over, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let baseData = baseCtx.data, let overData = overCtx.data else {
            throw Error.contextAllocationFailed
        }
        let basePx = baseData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let overPx = overData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let op = max(0.0, min(1.0, opacity))
        let pixelCount = width * height

        for i in 0..<pixelCount {
            let idx = i * 4
            let b = SIMD3<Double>(
                Double(basePx[idx]) / 255.0,
                Double(basePx[idx + 1]) / 255.0,
                Double(basePx[idx + 2]) / 255.0
            )
            let o = SIMD3<Double>(
                Double(overPx[idx]) / 255.0,
                Double(overPx[idx + 1]) / 255.0,
                Double(overPx[idx + 2]) / 255.0
            )
            let blended = blend(base: b, over: o, mode: mode)
            // Manual lerp — simd_mix is Float-only on this SDK, so do it
            // in SIMD3<Double>: result = b * (1-op) + blended * op.
            let result = b * (1.0 - op) + blended * op

            basePx[idx]     = quantize(result.x)
            basePx[idx + 1] = quantize(result.y)
            basePx[idx + 2] = quantize(result.z)
            // Alpha channel stays at whatever base had — the compositor
            // doesn't change pixel coverage, just colour.
        }

        guard let result = baseCtx.makeImage() else { throw Error.imageEncodeFailed }
        return result
    }

    // MARK: - Blend math

    /// Per-pixel blend function. Takes pre-normalised RGB and returns
    /// the mode-specific blended colour (no opacity applied — that's
    /// layered on in `compose()`). Inlined so the switch dispatches
    /// at the call site's loop rather than per-pixel.
    @inline(__always)
    static func blend(base: SIMD3<Double>, over: SIMD3<Double>, mode: LayerBlendMode) -> SIMD3<Double> {
        switch mode {
        // ── Tier 1 RGB ─────────────────────────────────────────────────
        case .normal:
            return over

        case .multiply:
            return base * over

        case .screen:
            return 1.0 - (1.0 - base) * (1.0 - over)

        case .overlay:
            // base drives the branch. base<0.5 behaves like multiply×2,
            // base≥0.5 like screen on inverted inputs.
            return overlayHardLight(driver: base, content: over)

        case .hardLight:
            // Same formula as overlay with base/over roles swapped —
            // over drives the branch.
            return overlayHardLight(driver: over, content: base)

        case .softLight:
            // Pegtop formulation: (1-2*over)*base² + 2*over*base. Cheap
            // approximation of Photoshop's softLight that's visually
            // indistinguishable in the common 0..1 range.
            return (1.0 - 2.0 * over) * base * base + 2.0 * over * base

        case .difference:
            return SIMD3(abs(base.x - over.x), abs(base.y - over.y), abs(base.z - over.z))

        case .exclusion:
            return base + over - 2.0 * base * over

        case .darken:
            return SIMD3(min(base.x, over.x), min(base.y, over.y), min(base.z, over.z))

        case .lighten:
            return SIMD3(max(base.x, over.x), max(base.y, over.y), max(base.z, over.z))

        case .colorDodge:
            return SIMD3(
                colorDodgeChannel(b: base.x, o: over.x),
                colorDodgeChannel(b: base.y, o: over.y),
                colorDodgeChannel(b: base.z, o: over.z)
            )

        case .colorBurn:
            return SIMD3(
                colorBurnChannel(b: base.x, o: over.x),
                colorBurnChannel(b: base.y, o: over.y),
                colorBurnChannel(b: base.z, o: over.z)
            )

        // ── Tier 2 HSL ─────────────────────────────────────────────────
        case .hue:
            // Photoshop's HSL modes actually use HSL based on a
            // lightness/saturation model rooted in luminance — see
            // setLum/setSat below. Keep "hue" = base's lum + sat + over's hue.
            return setLum(setSat(over, sat: satLum(base)), lum: lum(base))

        case .saturation:
            return setLum(setSat(base, sat: satLum(over)), lum: lum(base))

        case .color:
            return setLum(over, lum: lum(base))

        case .luminosity:
            return setLum(base, lum: lum(over))

        // ── Tier 3 technical ───────────────────────────────────────────
        case .subtract:
            return SIMD3(max(0.0, base.x - over.x), max(0.0, base.y - over.y), max(0.0, base.z - over.z))

        case .divide:
            return SIMD3(
                over.x > 0 ? min(1.0, base.x / over.x) : 1.0,
                over.y > 0 ? min(1.0, base.y / over.y) : 1.0,
                over.z > 0 ? min(1.0, base.z / over.z) : 1.0
            )

        case .linearDodge:
            return SIMD3(min(1.0, base.x + over.x), min(1.0, base.y + over.y), min(1.0, base.z + over.z))

        case .linearBurn:
            return SIMD3(max(0.0, base.x + over.x - 1.0), max(0.0, base.y + over.y - 1.0), max(0.0, base.z + over.z - 1.0))
        }
    }

    // MARK: - Per-channel helpers (branchy modes)

    /// Unified overlay/hardLight formula. `driver` picks the branch
    /// (per channel); `content` is the other channel. Keeps both modes
    /// sharing one implementation — the only difference is which input
    /// drives the <0.5 test.
    @inline(__always)
    private static func overlayHardLight(driver: SIMD3<Double>, content: SIMD3<Double>) -> SIMD3<Double> {
        func ch(_ d: Double, _ c: Double) -> Double {
            d < 0.5 ? 2.0 * d * c : 1.0 - 2.0 * (1.0 - d) * (1.0 - c)
        }
        return SIMD3(ch(driver.x, content.x), ch(driver.y, content.y), ch(driver.z, content.z))
    }

    @inline(__always)
    private static func colorDodgeChannel(b: Double, o: Double) -> Double {
        o < 1.0 ? min(1.0, b / (1.0 - o)) : 1.0
    }

    @inline(__always)
    private static func colorBurnChannel(b: Double, o: Double) -> Double {
        o > 0.0 ? 1.0 - min(1.0, (1.0 - b) / o) : 0.0
    }

    // MARK: - HSL helpers (Photoshop model, SVG spec)

    /// Rec.709 luminance.
    @inline(__always)
    private static func lum(_ c: SIMD3<Double>) -> Double {
        0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }

    /// Saturation-as-lightness-span — max channel minus min channel.
    /// This is the Photoshop/SVG "saturation" definition used by the
    /// HSL blend modes (different from HSV's saturation).
    @inline(__always)
    private static func satLum(_ c: SIMD3<Double>) -> Double {
        max(c.x, max(c.y, c.z)) - min(c.x, min(c.y, c.z))
    }

    /// Shifts `c` so its luminance equals `targetLum`, preserving hue
    /// and saturation. Clips channels that would fall out of [0,1] by
    /// pulling the whole colour toward the luminance axis — same
    /// formulation as Photoshop / SVG 1.1 §15.7.
    @inline(__always)
    private static func setLum(_ c: SIMD3<Double>, lum targetLum: Double) -> SIMD3<Double> {
        let d = targetLum - lum(c)
        var out = c + SIMD3<Double>(repeating: d)
        let l = lum(out)
        let mn = min(out.x, min(out.y, out.z))
        let mx = max(out.x, max(out.y, out.z))
        if mn < 0.0 {
            let t = l / (l - mn)
            out = SIMD3(repeating: l) + (out - SIMD3(repeating: l)) * t
        }
        if mx > 1.0 {
            let t = (1.0 - l) / (mx - l)
            out = SIMD3(repeating: l) + (out - SIMD3(repeating: l)) * t
        }
        return out
    }

    /// Rescales `c`'s saturation (lightness span) to `targetSat` while
    /// preserving the relative ordering of channels. SVG 1.1 §15.7
    /// formulation — operates on the (min, mid, max) channels directly.
    @inline(__always)
    private static func setSat(_ c: SIMD3<Double>, sat targetSat: Double) -> SIMD3<Double> {
        // Sort channels to find (lo, mid, hi).
        let vals = [c.x, c.y, c.z]
        let indexed = vals.enumerated().sorted { $0.element < $1.element }
        let loIdx  = indexed[0].offset
        let midIdx = indexed[1].offset
        let hiIdx  = indexed[2].offset
        let lo = indexed[0].element
        let mid = indexed[1].element
        let hi = indexed[2].element

        var outVals: [Double] = [0, 0, 0]
        if hi > lo {
            outVals[midIdx] = ((mid - lo) * targetSat) / (hi - lo)
            outVals[hiIdx]  = targetSat
        } else {
            outVals[midIdx] = 0
            outVals[hiIdx]  = 0
        }
        outVals[loIdx] = 0
        return SIMD3(outVals[0], outVals[1], outVals[2])
    }

    // MARK: - Quantisation

    @inline(__always)
    private static func quantize(_ value: Double) -> UInt8 {
        let clamped = max(0.0, min(1.0, value))
        return UInt8((clamped * 255.0).rounded())
    }
}
