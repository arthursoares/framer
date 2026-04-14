import Foundation
import CoreGraphics

enum ShaderPixelSortRenderer {
    static func apply(
        to image: CGImage,
        params: ShaderLayerParams
    ) throws -> CGImage {
        guard case .pixelSort(let pixelSortParams) = params.params else {
            return image
        }

        let blendIntensity = ShaderPrimitives.clamp01(params.intensity * pixelSortParams.amount)
        guard blendIntensity > 0 else { return image }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let sourceCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let outputCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        sourceCtx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        outputCtx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let sourceData = sourceCtx.data, let outputData = outputCtx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let outputPixels = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let baseThreshold = ShaderPrimitives.clamp01(pixelSortParams.threshold)
        let span = max(1, min(256, pixelSortParams.span))
        let randomness = ShaderPrimitives.clamp01(pixelSortParams.randomness)
        let spanMode = pixelSortParams.spanMode
        let sortBy = pixelSortParams.sortBy
        let reverse = pixelSortParams.reverse

        struct PixelSample {
            let r: UInt8
            let g: UInt8
            let b: UInt8
            let a: UInt8
            /// Pre-computed sort key — value depends on `sortBy`
            /// (luminance / brightness=max(r,g,b) / hue).
            let sortKey: Double
        }

        @inline(__always)
        func pixelIndex(x: Int, y: Int) -> Int {
            (y * width + x) * 4
        }

        @inline(__always)
        func luminanceAt(x: Int, y: Int) -> Double {
            let idx = pixelIndex(x: x, y: y)
            let r = Double(sourcePixels[idx])
            let g = Double(sourcePixels[idx + 1])
            let b = Double(sourcePixels[idx + 2])
            return ((0.299 * r) + (0.587 * g) + (0.114 * b)) / 255.0
        }

        @inline(__always)
        func maxRGBAt(x: Int, y: Int) -> Double {
            let idx = pixelIndex(x: x, y: y)
            let r = Double(sourcePixels[idx])
            let g = Double(sourcePixels[idx + 1])
            let b = Double(sourcePixels[idx + 2])
            return max(r, max(g, b)) / 255.0
        }

        // Sort criterion — orthogonal to `spanMode`. Matches the
        // `psSortValue` switch in PixelSort.metal so CPU and GPU produce
        // identical sort orderings at matching parameters.
        @inline(__always)
        func sortKeyAt(x: Int, y: Int) -> Double {
            switch sortBy {
            case .luminance:
                return luminanceAt(x: x, y: y)
            case .brightness:
                return maxRGBAt(x: x, y: y)
            case .hue:
                let idx = pixelIndex(x: x, y: y)
                let r = Double(sourcePixels[idx]) / 255.0
                let g = Double(sourcePixels[idx + 1]) / 255.0
                let b = Double(sourcePixels[idx + 2]) / 255.0
                let cMax = max(r, max(g, b))
                let cMin = min(r, min(g, b))
                let delta = cMax - cMin
                if delta < 1e-5 { return 0 }
                var h: Double
                if      cMax == r { h = (g - b) / delta }
                else if cMax == g { h = 2.0 + (b - r) / delta }
                else              { h = 4.0 + (r - g) / delta }
                h /= 6.0
                return h < 0 ? h + 1.0 : h
            }
        }

        // Same hash recipe as the GPU shader (sin-based fract) so per-line
        // randomness produces identical jitter on CPU and GPU at matching
        // line coordinates.
        func jitteredThreshold(lineCoord: Int) -> Double {
            guard randomness > 0 else { return baseThreshold }
            let raw = sin(Double(lineCoord) * 0.173) * 43758.5453
            let frac = raw - floor(raw)
            return ShaderPrimitives.clamp01(
                baseThreshold * (1.0 + (frac - 0.5) * randomness * 0.5)
            )
        }

        // Span predicates (Kim Asendorf 2010):
        //   .luminance — Framer legacy, span continues while lum >= threshold
        //   .kimBlack  — span starts when lum > threshold * 0.25 (shadows)
        //   .kimWhite  — span starts when lum < 1 - threshold * 0.25 (highlights)
        //   .kimBright — span uses max(r,g,b) > threshold (saturated regions)
        //   .kimDark   — span uses max(r,g,b) < threshold (desaturated regions)
        @inline(__always)
        func isInSpan(x: Int, y: Int, threshold: Double) -> Bool {
            switch spanMode {
            case .luminance:
                return luminanceAt(x: x, y: y) >= threshold
            case .kimBlack:
                return luminanceAt(x: x, y: y) > threshold * 0.25
            case .kimWhite:
                return luminanceAt(x: x, y: y) < 1.0 - threshold * 0.25
            case .kimBright:
                return maxRGBAt(x: x, y: y) > threshold
            case .kimDark:
                return maxRGBAt(x: x, y: y) < threshold
            }
        }

        func sortAndBlit(coords: [(x: Int, y: Int)]) {
            // Sample, sort by the chosen criterion (luminance / brightness /
            // hue, ascending or descending), write back blended with the
            // original output buffer by intensity.
            let samples: [PixelSample] = coords.map { c in
                let idx = pixelIndex(x: c.x, y: c.y)
                return PixelSample(
                    r: sourcePixels[idx],
                    g: sourcePixels[idx + 1],
                    b: sourcePixels[idx + 2],
                    a: sourcePixels[idx + 3],
                    sortKey: sortKeyAt(x: c.x, y: c.y)
                )
            }
            let sorted = reverse
                ? samples.sorted { $0.sortKey > $1.sortKey }
                : samples.sorted { $0.sortKey < $1.sortKey }
            for (offset, c) in coords.enumerated() {
                let idx = pixelIndex(x: c.x, y: c.y)
                let s = sorted[offset]
                outputPixels[idx]     = ShaderPrimitives.mix(outputPixels[idx],     s.r, intensity: blendIntensity)
                outputPixels[idx + 1] = ShaderPrimitives.mix(outputPixels[idx + 1], s.g, intensity: blendIntensity)
                outputPixels[idx + 2] = ShaderPrimitives.mix(outputPixels[idx + 2], s.b, intensity: blendIntensity)
                outputPixels[idx + 3] = ShaderPrimitives.mix(outputPixels[idx + 3], s.a, intensity: blendIntensity)
            }
        }

        // Walk one ordered list of pixel coordinates ("line"), find spans
        // matching the predicate, sort each span up to `span` pixels long.
        func processLine(coords: [(x: Int, y: Int)], lineCoord: Int) {
            let lineThreshold = jitteredThreshold(lineCoord: lineCoord)
            var i = 0
            while i < coords.count {
                let p = coords[i]
                if !isInSpan(x: p.x, y: p.y, threshold: lineThreshold) {
                    i += 1
                    continue
                }
                var run: [(x: Int, y: Int)] = []
                while i < coords.count, run.count < span {
                    let q = coords[i]
                    if !isInSpan(x: q.x, y: q.y, threshold: lineThreshold) { break }
                    run.append(q)
                    i += 1
                }
                if run.count > 1 {
                    sortAndBlit(coords: run)
                }
            }
        }

        // Build the per-direction line iteration. Each iteration constructs
        // its coord list lazily (an array per line keeps memory bounded —
        // the sort path needs random access anyway).
        switch pixelSortParams.direction {
        case .horizontal:
            for y in 0..<height {
                try Task.checkCancellation()
                let coords = (0..<width).map { (x: $0, y: y) }
                processLine(coords: coords, lineCoord: y)
            }
        case .vertical:
            for x in 0..<width {
                try Task.checkCancellation()
                let coords = (0..<height).map { (x: x, y: $0) }
                processLine(coords: coords, lineCoord: x)
            }
        case .diagonal:
            // Anti-diagonals along `dir = (1, 1)`. lineCoord = floor(x - y),
            // ranging from -(height-1) up to (width-1) inclusive. Each line
            // starts at (max(0, d), max(0, -d)) and walks +1 in each axis
            // until it exits the image.
            let dMin = -(height - 1)
            let dMax = width - 1
            for d in dMin...dMax {
                try Task.checkCancellation()
                let startX = max(0, d)
                let startY = max(0, -d)
                let length = min(width - startX, height - startY)
                guard length > 0 else { continue }
                let coords = (0..<length).map { (x: startX + $0, y: startY + $0) }
                processLine(coords: coords, lineCoord: d)
            }
        }

        guard let result = outputCtx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        return result
    }
}
