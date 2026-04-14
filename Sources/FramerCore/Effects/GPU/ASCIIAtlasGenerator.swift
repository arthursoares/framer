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

/// Human-facing character palette choices. Not persisted directly — the UI
/// translates presets to / from `ASCIIShaderParams.characters`:
///
///   - `.default`: nil `characters` (uses the baked `fillASCII.png` atlas,
///     which is hand-tuned pixel art at the 8×8 cell size — higher quality
///     than Core-Text-rasterised 8pt glyphs for the classic ramp).
///   - preset case: `characters` = the preset's literal string; the atlas
///     generator rasterises it at load time.
///   - `.custom`: `characters` holds an arbitrary user string that doesn't
///     match any preset.
public enum ASCIIPreset: String, CaseIterable, Sendable {
    case `default` = "Default"
    case classic   = "Classic"
    case blocks    = "Blocks"
    case binary    = "Binary"
    case dense     = "Dense"
    case custom    = "Custom"

    /// Returns `nil` for `.default` (caller should store nil on the params)
    /// and `nil` for `.custom` (caller preserves the user's live string).
    /// Every other case returns its literal palette string.
    public var characters: String? {
        switch self {
        case .default: return nil
        case .classic: return " .:-=+*#%@"
        case .blocks:  return " ░▒▓█"
        case .binary:  return " 01"
        case .dense:   return " .·•●"
        case .custom:  return nil
        }
    }

    /// Derive the preset that matches a stored `characters` value. Used to
    /// initialise the picker selection from a saved layer: `nil` → Default,
    /// any string matching a known preset → that preset, anything else →
    /// Custom.
    public static func matching(_ characters: String?) -> ASCIIPreset {
        guard let characters else { return .default }
        for preset in ASCIIPreset.allCases where preset != .custom && preset != .default {
            if preset.characters == characters { return preset }
        }
        return .custom
    }
}

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
            glyphs = Self.mappedFillGlyphs(style.fillCharacters)
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

    /// Distribute N user characters across the 10 luminance slots so any
    /// palette size produces a coherent ramp. Slot i (0..9, dim → bright)
    /// samples `chars[floor(i * N / 10)]`. One-character strings therefore
    /// render a solid field of that character at every luminance level;
    /// three-character `"0.@"` splits into 4/3/3 dark/mid/bright bands;
    /// exactly ten characters is a one-to-one mapping. More than ten
    /// characters truncate to the first ten.
    ///
    /// The old implementation padded short strings with leading spaces,
    /// which meant `"@"` rendered as mostly blank output — confusing
    /// failure mode for a beginner exploring the UI. This replacement
    /// makes any N ≥ 1 produce a visibly active ramp.
    public static func mappedFillGlyphs(_ s: String) -> [Character] {
        let chars = Array(s)
        guard !chars.isEmpty else { return Array(repeating: " ", count: totalCells) }
        let n = min(chars.count, totalCells)
        return (0..<totalCells).map { slot in
            let idx = min(n - 1, slot * n / totalCells)
            return chars[idx]
        }
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

    /// Render at `superSampleScale × atlasSize`, then downsample to the
    /// shader-required 80×8. Core Text at 8pt produces unreadable blobs;
    /// at 32pt (4× scale) glyphs are crisp, and high-quality interpolation
    /// during the downsample averages 16 source pixels per output pixel
    /// for clean anti-aliasing. Atlas size + format stay byte-identical to
    /// the baked PNGs so the shader math is unchanged.
    private static let superSampleScale = 4

    private static func renderAtlasCGImage(
        glyphs: [Character],
        leadingBlankCells: Int,
        fontName: String?
    ) throws -> CGImage {
        let scale = superSampleScale
        let hiW = atlasWidth * scale
        let hiH = atlasHeight * scale
        let hiCellSize = cellSize * scale
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let hiCtx = CGContext(
            data: nil,
            width: hiW,
            height: hiH,
            bitsPerComponent: 8,
            bytesPerRow: hiW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MetalEffectError.textureLoadFailed("ASCIIAtlasGenerator: hi-res CGContext allocation failed")
        }

        // Black background; glyphs drawn in white. Shader reads `.r` and
        // treats it as 0..1 intensity, matching the baked atlas PNGs.
        hiCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        hiCtx.fill(CGRect(x: 0, y: 0, width: hiW, height: hiH))

        hiCtx.setShouldAntialias(true)
        hiCtx.setAllowsAntialiasing(true)
        hiCtx.setShouldSubpixelQuantizeFonts(false)  // smooth edges over snapping
        hiCtx.setShouldSmoothFonts(true)
        hiCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        let font = resolvedFont(named: fontName, size: CGFloat(hiCellSize))

        for (i, glyph) in glyphs.enumerated() {
            let cellIndex = leadingBlankCells + i
            if cellIndex >= totalCells { break }
            if glyph == " " { continue }
            drawGlyph(glyph, into: hiCtx, cellIndex: cellIndex, cellSizePx: hiCellSize, font: font)
        }

        guard let hiImage = hiCtx.makeImage() else {
            throw MetalEffectError.textureLoadFailed("ASCIIAtlasGenerator: hi-res CGImage conversion failed")
        }

        // Downsample to the shader's expected 80×8 with high-quality
        // interpolation. Each output pixel is the average of 16 hi-res
        // pixels — produces clean anti-aliased glyphs at the small atlas
        // size without the muddy blob you'd get from rendering 8pt directly.
        guard let loCtx = CGContext(
            data: nil,
            width: atlasWidth,
            height: atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: atlasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MetalEffectError.textureLoadFailed("ASCIIAtlasGenerator: downsample CGContext allocation failed")
        }
        loCtx.interpolationQuality = .high
        loCtx.draw(hiImage, in: CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))

        guard let cgImage = loCtx.makeImage() else {
            throw MetalEffectError.textureLoadFailed("ASCIIAtlasGenerator: CGImage conversion failed")
        }
        return cgImage
    }

    /// Prefer Menlo (always available, predictable monospace metrics).
    /// `size` is in points but we drive it from the cell-pixel size at
    /// hi-res render time.
    private static func resolvedFont(named name: String?, size: CGFloat) -> CTFont {
        if let name {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        let sysDesc = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Menlo",
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(sysDesc, size, nil)
    }

    /// Draw a single character centred inside `cellSizePx × cellSizePx`.
    /// CTLine gives us the correct baseline and advance without manual
    /// glyph measurement — matters for proportional-width characters that
    /// sneak into user strings (e.g. unicode block elements).
    private static func drawGlyph(_ char: Character, into ctx: CGContext, cellIndex: Int, cellSizePx: Int, font: CTFont) {
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

        let cellOriginX = CGFloat(cellIndex * cellSizePx)
        let drawX = cellOriginX + (CGFloat(cellSizePx) - CGFloat(width)) / 2
        // Baseline: descent from bottom, centred within cell vertically.
        let totalGlyphHeight = ascent + descent
        let verticalPadding = (CGFloat(cellSizePx) - totalGlyphHeight) / 2
        let drawY = verticalPadding + descent

        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, ctx)
    }
}
