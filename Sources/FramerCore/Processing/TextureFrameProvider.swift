// Sources/FramerCore/Processing/TextureFrameProvider.swift
//
// Discovers and manages texture overlay files (frames, dust, light leaks, wet plates).
//
// ## How Overlay Blending Works
//
// Texture overlays use a **luminance-deviation-from-gray** alpha blending technique:
//
// 1. The overlay image uses mid-gray (RGB 128,128,128) as "transparent"
// 2. For each pixel, luminance is computed: L = 0.299*R + 0.587*G + 0.114*B
// 3. Alpha is derived from deviation: alpha = |L - 0.5| * 2.0 * opacity
//    - At exact mid-gray (L=0.5): alpha=0 -> photo shows through completely
//    - At pure white (L=1.0): alpha=1 -> overlay fully visible
//    - At pure black (L=0.0): alpha=1 -> overlay fully visible
// 4. The overlay pixel's RGB is composited over the photo at the computed alpha
//
// ## Directory Structure
//
// Overlays are discovered from these locations (in priority order):
// 1. App bundle Resources/textures/  (bundled with the app)
// 2. ~/Library/Application Support/Framer/overlays/  (user-installed)
//
// Files are categorized by filename prefix:
// - frame_*, frame__*  -> Frame (film borders, Polaroid edges)
// - dirt__*            -> Dust & Scratches
// - leak__*            -> Light Leaks
// - plate__*           -> Wet Plate / Tintype

import Foundation
import CoreGraphics
import ImageIO

public enum TextureFrameProvider {

    public struct OverlayInfo: Identifiable, Hashable, Sendable {
        public let id: String         // filename stem (e.g. "frame__01")
        public let url: URL
        public let displayName: String
        public let kind: OverlayKind
    }

    // MARK: - Search Paths

    public static var searchPaths: [URL] {
        var paths: [URL] = []

        // 1. Bundled textures in the macOS / iOS app resources (project.yml
        //    folder reference). Available when running as Framer.app.
        if let bundledDir = Bundle.main.resourceURL?.appendingPathComponent("textures") {
            paths.append(bundledDir)
        }

        // 2. Bundled textures in FramerCore's SPM resource bundle. Available
        //    when running via swift run / swift test / FramerCLI — contexts
        //    where Bundle.main is the test runner or CLI binary, not the app.
        if let coreDir = Bundle.module.resourceURL?.appendingPathComponent("textures") {
            paths.append(coreDir)
        }

        // 3. User overlays
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            paths.append(appSupport.appendingPathComponent("Framer/overlays"))
        }

        return paths
    }

    // MARK: - Caching

    private static let _lock = NSLock()
    private static var _cachedOverlays: [OverlayInfo]?
    private static var _cachedByKind: [OverlayKind: [OverlayInfo]]?
    private static let _thumbnailCache = NSCache<NSString, _CGImageBox>()
    private static let _fullImageCache: NSCache<NSString, _CGImageBox> = {
        let cache = NSCache<NSString, _CGImageBox>()
        cache.countLimit = 10
        return cache
    }()
    // URL lookup cache: overlay name -> URL
    private static var _urlCache: [String: URL]?

    /// NSCache requires NSObject values
    private final class _CGImageBox: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Clears all caches. Call when overlay files change on disk.
    public static func invalidateCache() {
        _lock.lock()
        _cachedOverlays = nil
        _cachedByKind = nil
        _urlCache = nil
        _thumbnailCache.removeAllObjects()
        _fullImageCache.removeAllObjects()
        _lock.unlock()
    }

    // MARK: - Discovery (cached)

    /// Returns all available overlays. Results are cached after first scan.
    public static func availableOverlays() -> [OverlayInfo] {
        _lock.lock()
        defer { _lock.unlock() }
        if let cached = _cachedOverlays { return cached }
        let overlays = scanOverlays()
        _cachedOverlays = overlays
        // Build URL lookup
        var urlMap: [String: URL] = [:]
        for o in overlays { urlMap[o.id] = o.url }
        _urlCache = urlMap
        // Build kind groups
        var byKind: [OverlayKind: [OverlayInfo]] = [:]
        for o in overlays { byKind[o.kind, default: []].append(o) }
        _cachedByKind = byKind
        return overlays
    }

    /// Returns overlays filtered by kind (uses cached grouping).
    public static func overlays(ofKind kind: OverlayKind) -> [OverlayInfo] {
        _ = availableOverlays() // ensure cache populated
        _lock.lock()
        let result = _cachedByKind?[kind] ?? []
        _lock.unlock()
        return result
    }

    // MARK: - Resolution (cached)

    /// Resolves an overlay name to its file URL using the cached lookup table.
    public static func overlayURL(forName name: String) -> URL? {
        _ = availableOverlays() // ensure cache populated
        _lock.lock()
        let url = _urlCache?[name]
        _lock.unlock()
        return url
    }

    // MARK: - Thumbnails (cached)

    /// Returns a cached thumbnail, loading from disk if needed.
    /// Thread-safe — safe to call from any thread.
    public static func cachedThumbnail(for overlay: OverlayInfo, maxSize: Int = 80) -> CGImage? {
        let key = "\(overlay.id)_\(maxSize)" as NSString
        if let cached = _thumbnailCache.object(forKey: key) {
            return cached.image
        }
        guard let thumb = loadThumbnailFromDisk(url: overlay.url, maxSize: maxSize) else { return nil }
        _thumbnailCache.setObject(_CGImageBox(thumb), forKey: key)
        return thumb
    }

    /// Loads a downscaled thumbnail using ImageIO (memory-efficient, no full decode).
    private static func loadThumbnailFromDisk(url: URL, maxSize: Int = 80) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Loads the full-resolution overlay image (cached).
    public static func loadFullImage(for url: URL) -> CGImage? {
        let key = url.path as NSString
        if let cached = _fullImageCache.object(forKey: key) {
            return cached.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        _fullImageCache.setObject(_CGImageBox(image), forKey: key)
        return image
    }

    // MARK: - User Directory

    /// Returns the user overlay directory, creating it if needed.
    public static func ensureUserOverlayDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }

        let dir = appSupport.appendingPathComponent("Framer/overlays")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Internal Scanning

    private static func scanOverlays() -> [OverlayInfo] {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff"]
        var seen = Set<String>()
        var results: [OverlayInfo] = []

        for searchPath in searchPaths {
            guard FileManager.default.fileExists(atPath: searchPath.path) else { continue }

            guard let enumerator = FileManager.default.enumerator(
                at: searchPath,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                let ext = url.pathExtension.lowercased()
                guard imageExts.contains(ext) else { continue }

                let stem = url.deletingPathExtension().lastPathComponent

                // Skip thumbnails directory
                if url.path.contains("/thumbnails/") { continue }

                // Deduplicate by stem (first-found wins — bundled has priority)
                guard !seen.contains(stem) else { continue }
                seen.insert(stem)

                let kind = OverlayKind.from(filename: stem)
                let displayName = Self.humanReadableName(from: stem)

                results.append(OverlayInfo(
                    id: stem,
                    url: url,
                    displayName: displayName,
                    kind: kind
                ))
            }
        }

        return results.sorted { $0.id < $1.id }
    }

    // MARK: - Helpers

    private static func humanReadableName(from stem: String) -> String {
        stem
            .replacingOccurrences(of: "frame__", with: "")
            .replacingOccurrences(of: "frame_", with: "")
            .replacingOccurrences(of: "dirt__", with: "")
            .replacingOccurrences(of: "leak__", with: "")
            .replacingOccurrences(of: "plate__", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}
