// Sources/FramerCore/Processing/LUTProvider.swift
import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#endif

// MARK: - LUTInfo

public struct LUTInfo: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let category: String
    public let url: URL

    public init(id: String, displayName: String, category: String, url: URL) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.url = url
    }
}

// MARK: - LUTProvider

public enum LUTProvider {
    private static var cache: [String: LUT3D] = [:]
    private static let cacheLock = NSLock()

    private static var lutsCache: [LUTInfo]?
    private static let lutsCacheLock = NSLock()

    #if os(macOS)
    private static var thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        return cache
    }()
    #endif

    private static var sampleImage: CGImage?

    // MARK: - Discovery

    public static func availableLUTs() -> [LUTInfo] {
        lutsCacheLock.lock()
        defer { lutsCacheLock.unlock() }
        if let cached = lutsCache {
            return cached
        }

        var luts: [LUTInfo] = []

        if let bundledLuts = bundledLUTs() {
            luts.append(contentsOf: bundledLuts)
        }

        if let userLuts = userLUTs() {
            luts.append(contentsOf: userLuts)
        }

        lutsCache = luts
        return luts
    }

    public static func luts(inCategory category: String) -> [LUTInfo] {
        availableLUTs().filter { $0.category == category }
    }

    // MARK: - Loading

    public static func loadLUT(named: String) -> LUT3D? {
        cacheLock.lock()
        if let cached = cache[named] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let url = lutURL(named: named) else {
            return nil
        }

        do {
            let lut = try CubeFileParser.parse(from: url)
            cacheLock.lock()
            cache[named] = lut
            cacheLock.unlock()
            return lut
        } catch {
            return nil
        }
    }

    // MARK: - Thumbnail Generation

    public static func thumbnail(for lutInfo: LUTInfo, size: Int = 48) -> CGImage? {
        let cacheKey = "\(lutInfo.id)_\(size)" as NSString

        #if os(macOS)
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        #endif

        guard let lut = loadLUT(named: lutInfo.id) else {
            return nil
        }

        let sample = getSampleImage(size: size)
        guard let sample = sample else {
            return nil
        }

        do {
            let rendered = try LUTRenderer.apply(to: sample, lut: lut, intensity: 1.0, previewBaseDimension: nil)
            #if os(macOS)
            let nsImage = NSImage(cgImage: rendered, size: NSSize(width: size, height: size))
            thumbnailCache.setObject(nsImage, forKey: cacheKey)
            #endif
            return rendered
        } catch {
            return nil
        }
    }

    public static func clearThumbnailCache() {
        #if os(macOS)
        thumbnailCache.removeAllObjects()
        #endif
    }

    private static func getSampleImage(size: Int) -> CGImage? {
        if let existing = sampleImage, existing.width == size {
            return existing
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)

        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 4
                let t = Double(x) / Double(size - 1)
                let s = Double(y) / Double(size - 1)
                data[idx] = UInt8(t * 255)
                data[idx + 1] = UInt8(s * 255)
                data[idx + 2] = UInt8(((t + s) / 2) * 255)
                data[idx + 3] = 255
            }
        }

        sampleImage = ctx.makeImage()
        return sampleImage
    }

    // MARK: - User Management

    public static func importLUT(from sourceURL: URL) throws -> LUTInfo {
        guard let userDir = userLUTDirectory() else {
            throw LUTProviderError.userDirectoryUnavailable
        }

        let fileName = sourceURL.lastPathComponent
        let destURL = userDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        invalidateCache()

        return try makeLUTInfo(from: destURL, category: "user")
    }

    public static func userLUTDirectory() -> URL? {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let framerDir = appSupport.appendingPathComponent("Framer/luts", isDirectory: true)
            if !fileManager.fileExists(atPath: framerDir.path) {
                try? fileManager.createDirectory(at: framerDir, withIntermediateDirectories: true)
            }
            return framerDir
        }
        return nil
    }

    public static func invalidateCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()

        lutsCacheLock.lock()
        lutsCache = nil
        lutsCacheLock.unlock()

        clearThumbnailCache()
    }

    // MARK: - Private

    private static func bundledLUTs() -> [LUTInfo]? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        let execDir = execURL.deletingLastPathComponent()
        let assetsDir = execDir.appendingPathComponent("assets/luts", isDirectory: true)

        guard FileManager.default.fileExists(atPath: assetsDir.path) else {
            return nil
        }

        var luts: [LUTInfo] = []
        if let enumerator = FileManager.default.enumerator(at: assetsDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "cube" {
                    if let info = try? makeLUTInfo(from: fileURL, category: "bundled") {
                        luts.append(info)
                    }
                }
            }
        }

        return luts
    }

    private static func userLUTs() -> [LUTInfo]? {
        guard let userDir = userLUTDirectory() else { return nil }
        guard FileManager.default.fileExists(atPath: userDir.path) else { return nil }

        var luts: [LUTInfo] = []
        if let enumerator = FileManager.default.enumerator(at: userDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "cube" {
                    if let info = try? makeLUTInfo(from: fileURL, category: "user") {
                        luts.append(info)
                    }
                }
            }
        }
        return luts
    }

    private static func lutURL(named: String) -> URL? {
        let luts = availableLUTs()
        return luts.first { $0.id == named }?.url
    }

    private static func makeLUTInfo(from url: URL, category: String) throws -> LUTInfo {
        let fileName = url.deletingPathExtension().lastPathComponent
        let id = fileName

        var displayName = fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        if let _ = try? CubeFileParser.parse(from: url),
           let titleLine = String(data: try Data(contentsOf: url), encoding: .utf8)?
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("TITLE") }) {
            let titleMatch = titleLine.split(separator: "\"")
            if titleMatch.count >= 2 {
                displayName = String(titleMatch[1])
            }
        }

        return LUTInfo(id: id, displayName: displayName, category: category, url: url)
    }
}

// MARK: - Errors

public enum LUTProviderError: LocalizedError {
    case userDirectoryUnavailable

    public var errorDescription: String? {
        switch self {
        case .userDirectoryUnavailable:
            return "Could not access user LUT directory"
        }
    }
}
