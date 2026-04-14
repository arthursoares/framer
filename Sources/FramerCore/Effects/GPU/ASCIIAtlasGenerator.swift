// ASCIIAtlasGenerator.swift
// Runtime generator for the ASCII LUT atlases (fill + edges). Replaces the
// baked `fillASCII.png` / `edgesASCII.png` resources when an
// `ASCIIShaderParams.characters` string is supplied, so users can pick their
// own glyph palette without shipping extra PNG assets.
//
// Contract — must match the baked atlas layout exactly so TextCell.metal's
// sampling math (`xCoord = gx8 + level*8` for fill, `xCoord = gx8 +
// (direction+1)*8` for edges) keeps working unchanged:
//
//   - 80 × 8 pixels, grayscale (RGBA8 with R carrying intensity; shader
//     reads `.r` only).
//   - Fill atlas: 10 glyphs laid out horizontally, one per luminance level
//     (dim → bright). Glyph i occupies columns [i*8, i*8+8).
//   - Edges atlas: 4 edge glyphs (horizontal, vertical, diagonal1,
//     diagonal2) at columns 8..39. Columns 0..7 are unused by the shader
//     but filled with zeros to keep the texture well-defined.
//
// Atlases are cached by (characters, edgeCharacters, fontName) so repeated
// reads on the same parameters don't re-rasterise. The cache is small and
// lives for the process lifetime — glyph set changes are rare compared to
// frame rate, so eviction hasn't been needed.

import Foundation
import CoreGraphics
import CoreText
import Metal

public enum ASCIIAtlasGenerator {

    // MARK: - Public API

    public struct Style: Hashable, Sendable {
        /// Exactly 10 characters, ordered dim → bright. Shorter strings are
        /// padded with spaces; longer strings are truncated.
        public let fillCharacters: String
        /// 4 characters mapped to detected edge directions (horizontal,
        /// vertical, diagonal1, diagonal2). Defaults to `-|/\`.
        public let edgeCharacters: String
        /// PostScript font name. `nil` picks the system monospaced font.
        public let fontName: String?

        public init(
            fillCharacters: String,
            edgeCharacters: String = "-|/\\",
            fontName: String? = nil
        ) {
            self.fillCharacters = fillCharacters
            self.edgeCharacters = edgeCharacters
            self.fontName = fontName
        }
    }

    public struct Atlases {
        public let fill: MTLTexture
        public let edges: MTLTexture
    }

    public static func atlases(for style: Style, device: MTLDevice) throws -> Atlases {
        cacheLock.lock()
        if let hit = textureCache[style] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        // Do the CGImage lookups / Metal uploads *without* the lock held, so
        // the two cache calls don't deadlock against each other. Small window
        // where a concurrent caller could re-do the work; the upload is cheap
        // enough (80×8 RGBA = 2.5 KB) that double work is fine.
        let fillImage  = try atlasCGImage(for: style, kind: .fill)
        let edgesImage = try atlasCGImage(for: style, kind: .edges)
        let built = Atlases(
            fill:  try MetalTextureSupport.makeTexture(from: fillImage,  device: device),
            edges: try MetalTextureSupport.makeTexture(from: edgesImage, device: device)
        )
        cacheLock.lock()
        textureCache[style] = built
        cacheLock.unlock()
        return built
    }

    /// CGImage variant for the CPU ASCII renderer (`ShaderASCIIRenderer`).
    /// Cached independently from the MTLTexture cache since CPU consumers
    /// don't always have a Metal device to upload to.
    public static func atlasCGImage(for style: Style, kind: AtlasKind) throws -> CGImage {
        let cacheKey = CGImageCacheKey(style: style, kind: kind)
        cacheLock.lock()
        if let hit = cgImageCache[cacheKey] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let glyphs: [Character]
        let leading: Int
        switch kind {
        case .fill:
            glyphs = paddedFillGlyphs(style.fillCharacters)
            leading = 0
        case .edges:
            glyphs = paddedEdgeGlyphs(style.edgeCharacters)
            leading = 1  // columns 0..7 unused per shader contract
        }
        let image = try renderAtlasCGImage(
            glyphs: glyphs,
            leadingBlankCells: leading,
            fontName: style.fontName
        )
        cacheLock.lock()
        cgImageCache[cacheKey] = image
        cacheLock.unlock()
        return image
    }

    public enum AtlasKind: Hashable {
        case fill
        case edges
    }

    // MARK: - Cache

    private struct CGImageCacheKey: Hashable {
        let style: Style
        let kind: AtlasKind
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var textureCache: [Style: Atlases] = [:]
    nonisolated(unsafe) private static var cgImageCache: [CGImageCacheKey: CGImage] = [:]

    // MARK: - Rendering

    private static let cellSize = 8
    private static let totalCells = 10      // atlas width / cellSize
    private static let atlasWidth = 80      // cellSize * totalCells
    private static let atlasHeight = 8

    /// Pad or truncate the fill string to exactly 10 characters, preserving
    /// the user's dim-to-bright ordering. Short strings fill the tail with
    /// spaces (dim), so `"@"` alone becomes `"        @ "` — entirely blank
    /// until the brightest level lights up the `@`.
    private static func paddedFillGlyphs(_ s: String) -> [Character] {
        var chars = Array(s)
        if chars.count >= totalCells {
            return Array(chars.prefix(totalCells))
        }
        while chars.count < totalCells {
            chars.insert(" ", at: 0)  // dim end of ramp
        }
        return chars
    }

    /// Edges always occupy slots 1..4 in the atlas (per shader offset). Pad
    /// up to 4 with spaces, fill remaining slots with spaces so the texture
    /// has a consistent 10-cell width.
    private static func paddedEdgeGlyphs(_ s: String) -> [Character] {
        var chars = Array(s)
        while chars.count < 4 { chars.append(" ") }
        if chars.count > 4 { chars = Array(chars.prefix(4)) }
        // Result layout inside the atlas: [_,E0,E1,E2,E3,_,_,_,_,_]
        // `renderAtlas` places glyphs starting at `leadingBlankCells`.
        return chars
    }

    private static func renderAtlasCGImage(
        glyphs: [Character],
        leadingBlankCells: Int,
        fontName: String?
    ) throws -> CGImage {
        let w = atlasWidth
        let h = atlasHeight
        let bytesPerRow = w * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MetalEffectError.textureLoadFailed("ASCIIAtlasGenerator: CGContext allocation failed")
        }

        // Black background; glyphs drawn in white. Shader reads `.r` and
        // treats it as 0..1 intensity, which matches the baked atlas PNGs.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Anti-aliasing off would give crispest pixel-art glyphs, but Core
        // Text at this size produces near-illegible output without AA. Keep
        // AA on; nearest sampling at consumer time preserves the "ASCII"
        // look when the atlas is stretched across larger cells.
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        let font = resolvedFont(named: fontName)

        for (i, glyph) in glyphs.enumerated() {
            let cellIndex = leadingBlankCells + i
            if cellIndex >= totalCells { break }
            if glyph == " " { continue }
            drawGlyph(glyph, into: ctx, cellIndex: cellIndex, font: font)
        }

        guard let cgImage = ctx.makeImage() else {
            throw MetalEffectError.textureLoadFailed("ASCIIAtlasGenerator: CGImage conversion failed")
        }
        return cgImage
    }

    /// Prefer the system monospaced font (macOS `.monospacedSystemFont`
    /// analogue) since it's always available and kerns predictably at tiny
    /// sizes. Fall back to Menlo, then any CoreText default.
    private static func resolvedFont(named name: String?) -> CTFont {
        let size: CGFloat = 8
        if let name {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        let sysDesc = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Menlo",
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(sysDesc, size, nil)
    }

    /// Draw a single character centred inside its 8×8 cell. CTLine gives us
    /// the correct baseline and advance without us having to measure glyphs
    /// manually — important for proportional-width characters that sneak
    /// into user strings.
    private static func drawGlyph(_ char: Character, into ctx: CGContext, cellIndex: Int, font: CTFont) {
        let string = String(char) as NSString
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let attributed = NSAttributedString(string: string as String, attributes: attr)
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let cellOriginX = CGFloat(cellIndex * cellSize)
        let drawX = cellOriginX + (CGFloat(cellSize) - CGFloat(width)) / 2
        // Baseline: descent from bottom, centred within cell vertically.
        let totalGlyphHeight = ascent + descent
        let verticalPadding = (CGFloat(cellSize) - totalGlyphHeight) / 2
        let drawY = verticalPadding + descent

        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, ctx)
    }
}
