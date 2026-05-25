import Foundation
import CoreGraphics

public enum GlitchRenderer {
    public static func renderPreview(
        input: CGImage,
        effect: GPUEffectKind,
        parameters: GPUEffectParameters,
        outputSize: CGSize
    ) throws -> CGImage {
        guard case let .glitch(common, geometry, color, payload) = parameters else {
            return input
        }

        // GPU fast paths. Each maps to its Metal shader; both fall back to
        // the CPU pixel loop below on `MetalEffectError` (headless hosts,
        // missing device, etc).
        //
        //   - VHS → Effects/Metal/Glitch.metal::glitchFragment (variant 0)
        //   - PixelSort → Effects/Metal/PixelSort.metal::pixelSortFragment,
        //     same shader the .shader layer's PixelSort style uses. The
        //     bucket routes through a separate GlitchGPURenderer entry
        //     point that maps the leaner GlitchParameters onto the shader's
        //     uniforms (no Kim-Asendorf span modes, fixed intensity=amount).
        if effect == .vhs {
            do {
                return try GlitchGPURenderer.renderVHS(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        } else if effect == .pixelSort {
            do {
                return try GlitchGPURenderer.renderPixelSort(
                    input: input, common: common, geometry: geometry,
                    color: color, params: payload, outputSize: outputSize)
            } catch is MetalEffectError {
                // fall through to CPU
            }
        }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        let bytesPerRow = width * 4
        guard let sourcePixels = EffectBitmapSupport.rasterize(input, width: width, height: height) else { return input }

        var outputPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let span = max(1, Int((geometry.scale * 8.0 + geometry.spacing * 2.0).rounded()))

        if payload.variant == .pixelSort {
            if payload.direction == .horizontal {
                for y in 0..<height {
                    applyPixelSortRow(
                        y: y,
                        width: width,
                        sourcePixels: sourcePixels,
                        outputPixels: &outputPixels,
                        span: span,
                        payload: payload
                    )
                }
            } else {
                for x in 0..<width {
                    applyPixelSortColumn(
                        x: x,
                        width: width,
                        height: height,
                        sourcePixels: sourcePixels,
                        outputPixels: &outputPixels,
                        span: span,
                        payload: payload
                    )
                }
            }
        } else {
            for y in 0..<height {
                let rowShift = rowOffset(y: y, span: span, amount: payload.amount + payload.distortion, threshold: payload.threshold + payload.trackingError, variant: payload.variant)
                for x in 0..<width {
                    let sourceX = min(width - 1, max(0, x + rowShift))
                    let sourceIndex = (y * width + sourceX) * 4
                    let outputIndex = (y * width + x) * 4

                    switch payload.variant {
                    case .pixelSort:
                        break
                    case .vhs:
                        let bleedOffset = max(1, Int((payload.colorBleed * 4.0).rounded()))
                        let redX = min(width - 1, max(0, sourceX + bleedOffset))
                        let blueX = min(width - 1, max(0, sourceX - bleedOffset))
                        let redIndex = (y * width + redX) * 4
                        let blueIndex = (y * width + blueX) * 4
                        outputPixels[outputIndex] = sourcePixels[redIndex]
                        outputPixels[outputIndex + 1] = sourcePixels[sourceIndex + 1]
                        outputPixels[outputIndex + 2] = sourcePixels[blueIndex + 2]
                    }

                    let alpha = sourcePixels[sourceIndex + 3]
                    outputPixels[outputIndex + 3] = alpha
                }
                if payload.variant == .vhs && y % max(2, Int(max(1.0, payload.scanlines * Double(span)))) == 0 {
                    applyScanline(to: &outputPixels, row: y, width: width, colorMode: color.mode, backgroundIntensity: color.backgroundIntensity, common: common, effect: effect)
                }
            }
        }

        return EffectBitmapSupport.makeImage(from: &outputPixels, width: width, height: height) ?? input
    }

    private static func rowOffset(y: Int, span: Int, amount: Double, threshold: Double, variant: GlitchVariant) -> Int {
        let wave = sin(Double(y) / Double(max(1, span)))
        let magnitude = Int((wave * amount * Double(span) * (1.0 + threshold)).rounded())
        switch variant {
        case .pixelSort:
            return magnitude
        case .vhs:
            return magnitude / 2
        }
    }

    /// Pixel-sort segment size as a fraction of the sort-axis dimension, so it
    /// is resolution-independent (mirrors the GPU `spanCap` mapping in
    /// `GlitchGPURenderer.renderPixelSort`). Clamped to the same walk bound.
    private static func pixelSortStep(streakLength: Double, dimension: Int) -> Int {
        let proportional = streakLength * streakLength * Double(dimension)
        return max(1, min(GlitchGPURenderer.maxSpanWalk, Int(proportional.rounded())))
    }

    private static func applyPixelSortColumn(
        x: Int,
        width: Int,
        height: Int,
        sourcePixels: [UInt8],
        outputPixels: inout [UInt8],
        span: Int,
        payload: GlitchParameters
    ) {
        let step = pixelSortStep(streakLength: payload.streakLength, dimension: height)
        for start in stride(from: 0, to: height, by: step) {
            let end = min(height, start + step)
            applyPixelSortSegment(
                positions: Array(start..<end),
                sourcePixels: sourcePixels,
                outputPixels: &outputPixels,
                offsetForPosition: { position in (position * width + x) * 4 },
                payload: payload,
                seedBase: x * 37 + start
            )
        }
    }

    private static func applyPixelSortRow(
        y: Int,
        width: Int,
        sourcePixels: [UInt8],
        outputPixels: inout [UInt8],
        span: Int,
        payload: GlitchParameters
    ) {
        let rowStart = y * width * 4
        let step = pixelSortStep(streakLength: payload.streakLength, dimension: width)
        for start in stride(from: 0, to: width, by: step) {
            let end = min(width, start + step)
            applyPixelSortSegment(
                positions: Array(start..<end),
                sourcePixels: sourcePixels,
                outputPixels: &outputPixels,
                offsetForPosition: { position in rowStart + position * 4 },
                payload: payload,
                seedBase: y * 31 + start
            )
        }
    }

    private static func applyPixelSortSegment(
        positions: [Int],
        sourcePixels: [UInt8],
        outputPixels: inout [UInt8],
        offsetForPosition: (Int) -> Int,
        payload: GlitchParameters,
        seedBase: Int
    ) {
        let scored = positions.map { position -> (position: Int, score: Double) in
            let offset = offsetForPosition(position)
            return (position, pixelScore(at: offset, in: sourcePixels, mode: payload.sortMode))
        }

        // Active positions in their original order (the ones that pass the
        // threshold — these are the ones that get sorted).
        let activeScored = scored.filter { $0.score >= payload.threshold }
        let activeInOriginalOrder = activeScored.map(\.position)
        // Same positions, re-ordered by score. `activeInOriginalOrder[i]` is
        // the fragment whose sorted counterpart lives at
        // `sortedActivePositions[i]`.
        let sortedActivePositions = activeScored.sorted { lhs, rhs in
            payload.reverse ? lhs.score > rhs.score : lhs.score < rhs.score
        }.map(\.position)

        // Map original-order rank per active position for O(1) lookup below.
        var originalRank: [Int: Int] = [:]
        originalRank.reserveCapacity(activeInOriginalOrder.count)
        for (rank, p) in activeInOriginalOrder.enumerated() {
            originalRank[p] = rank
        }

        // `amount` is the blend factor between original and sorted, matching
        // `mix(currentColor, sortedColor, saturate(uniforms.intensity))` in
        // Effects/Metal/PixelSort.metal. Previously the CPU path treated
        // `amount` as a sort-rank scaling (`baseIndex = normalized × count × max(0.2, amount)`),
        // which made amount=0 render the darkest ~20% of every span instead
        // of passing through the original pixels. GPU and CPU now agree on
        // semantics: amount=0 → original, amount=1 → fully sorted (subject
        // to `randomness` jitter).
        let alpha = max(0.0, min(1.0, payload.amount))
        let randomness = max(0.0, min(1.0, payload.randomness))

        for (index, position) in positions.enumerated() {
            let outputIndex = offsetForPosition(position)
            let originalIdx = offsetForPosition(position)

            guard let rank = originalRank[position], !sortedActivePositions.isEmpty else {
                // Below threshold or no active positions — pass through
                // original unchanged. Matches the shader's early-return for
                // `!psInSpan(currentColor, effective, uniforms.spanMode)`.
                outputPixels[outputIndex]     = sourcePixels[originalIdx]
                outputPixels[outputIndex + 1] = sourcePixels[originalIdx + 1]
                outputPixels[outputIndex + 2] = sourcePixels[originalIdx + 2]
                outputPixels[outputIndex + 3] = sourcePixels[originalIdx + 3]
                continue
            }

            // Apply per-index jitter within sorted rank space so `randomness`
            // produces the same visible noise on CPU and GPU.
            let jitter = Int((sin(Double(seedBase + index * 17)) * randomness * Double(sortedActivePositions.count)).rounded())
            let clamped = min(sortedActivePositions.count - 1, max(0, rank + jitter))
            let sortedIdx = offsetForPosition(sortedActivePositions[clamped])

            outputPixels[outputIndex]     = blendChannel(sourcePixels[originalIdx],     sourcePixels[sortedIdx],     alpha: alpha)
            outputPixels[outputIndex + 1] = blendChannel(sourcePixels[originalIdx + 1], sourcePixels[sortedIdx + 1], alpha: alpha)
            outputPixels[outputIndex + 2] = blendChannel(sourcePixels[originalIdx + 2], sourcePixels[sortedIdx + 2], alpha: alpha)
            outputPixels[outputIndex + 3] = blendChannel(sourcePixels[originalIdx + 3], sourcePixels[sortedIdx + 3], alpha: alpha)
        }
    }

    @inline(__always)
    private static func blendChannel(_ original: UInt8, _ sorted: UInt8, alpha: Double) -> UInt8 {
        let mixed = (1.0 - alpha) * Double(original) + alpha * Double(sorted)
        return UInt8(max(0.0, min(255.0, mixed)).rounded())
    }

    /// CPU counterpart of `psSortValue` in `Effects/Metal/PixelSort.metal`.
    /// All three modes return a value in `[0, 1]` so the sort comparator
    /// stays well-ordered and the threshold dial (also `[0, 1]`) has the
    /// intended effect on every sort criterion.
    ///
    /// Pre-pass-3 this function had two bugs that made the CPU fallback
    /// diverge from the GPU shader:
    ///   - `.brightness` returned the Rec.709 luminance formula (same as
    ///     `.luminance`). The GPU shader returns `max(r, g, b)`, so sorting
    ///     preserved saturated colours on GPU but desaturated them on CPU.
    ///   - `.hue` returned the raw HSV sector value in `[-1, 6)` instead of
    ///     a normalised hue in `[0, 1]`. Negative scores (blue-dominant
    ///     pixels) always fell below any positive threshold, leaving whole
    ///     hue ranges unsorted.
    private static func pixelScore(at index: Int, in pixels: [UInt8], mode: PixelSortMode) -> Double {
        let r = Double(pixels[index]) / 255.0
        let g = Double(pixels[index + 1]) / 255.0
        let b = Double(pixels[index + 2]) / 255.0
        switch mode {
        case .luminance:
            return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        case .brightness:
            return max(r, max(g, b))
        case .hue:
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let delta = maxValue - minValue
            guard delta > 1e-5 else { return 0 }
            var h: Double
            if      maxValue == r { h = (g - b) / delta }
            else if maxValue == g { h = 2.0 + (b - r) / delta }
            else                  { h = 4.0 + (r - g) / delta }
            h /= 6.0
            return h < 0 ? h + 1.0 : h
        }
    }

    private static func applyScanline(
        to outputPixels: inout [UInt8],
        row: Int,
        width: Int,
        colorMode: GPUEffectColorMode,
        backgroundIntensity: Double,
        common: GPUEffectCommonParameters,
        effect: GPUEffectKind
    ) {
        let attenuation = max(0.4, min(0.95, 0.75 - common.brightness * 0.2))
        let tint = UInt8(max(0, min(255, Int((backgroundIntensity * 255.0).rounded()))))
        for x in 0..<width {
            let idx = (row * width + x) * 4
            outputPixels[idx] = UInt8(Double(outputPixels[idx]) * attenuation)
            outputPixels[idx + 1] = UInt8(Double(outputPixels[idx + 1]) * attenuation)
            switch (colorMode, effect) {
            case (.foregroundBackground, .vhs):
                outputPixels[idx + 2] = max(tint, UInt8(Double(outputPixels[idx + 2]) * attenuation))
            default:
                outputPixels[idx + 2] = UInt8(Double(outputPixels[idx + 2]) * attenuation)
            }
        }
    }
}
