import XCTest
import CoreGraphics
@testable import FramerCore

final class LUTProviderTests: XCTestCase {
    private var importedURL: URL?
    private var metadataURL: URL? {
        LUTProvider.userLUTDirectory()?.appendingPathComponent(".lut-metadata.json")
    }

    override func tearDown() {
        if let importedURL {
            try? FileManager.default.removeItem(at: importedURL)
        }
        if let metadataURL {
            try? FileManager.default.removeItem(at: metadataURL)
        }
        LUTProvider.clearThumbnailCache()
        LUTProvider.invalidateCache()
        super.tearDown()
    }

    func test_importLUT_replacingSameFilenameRefreshesLoadedData() throws {
        let lutName = "lut-provider-cache-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(lutName).cube")

        try makeCube(low: 0.1, high: 0.9).write(to: sourceURL, atomically: true, encoding: .utf8)
        let info = try LUTProvider.importLUT(from: sourceURL)
        importedURL = LUTProvider.userLUTDirectory()?.appendingPathComponent("\(lutName).cube")

        let first = try XCTUnwrap(LUTProvider.loadLUT(named: info.id))
        XCTAssertEqual(first.data[0], 0.1, accuracy: 0.0001)

        try makeCube(low: 0.6, high: 0.95).write(to: sourceURL, atomically: true, encoding: .utf8)
        _ = try LUTProvider.importLUT(from: sourceURL)

        let second = try XCTUnwrap(LUTProvider.loadLUT(named: info.id))
        XCTAssertEqual(second.data[0], 0.6, accuracy: 0.0001)
    }

    func test_thumbnail_withSourceImage_usesProvidedImageInsteadOfGenericSample() throws {
        let lutName = "lut-provider-source-thumb-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(lutName).cube")
        try makeIdentityCube(size: 2).write(to: sourceURL, atomically: true, encoding: .utf8)
        let info = try LUTProvider.importLUT(from: sourceURL)
        importedURL = LUTProvider.userLUTDirectory()?.appendingPathComponent("\(lutName).cube")

        let sourceImage = makeSolidImage(width: 4, height: 4, r: 12, g: 34, b: 56)
        let thumbnail = try XCTUnwrap(LUTProvider.thumbnail(for: info, sourceImage: sourceImage, size: 4))
        let pixels = extractPixels(from: thumbnail)

        XCTAssertEqual(Set(pixels.map { $0.r }), [12])
        XCTAssertEqual(Set(pixels.map { $0.g }), [34])
        XCTAssertEqual(Set(pixels.map { $0.b }), [56])
    }

    func test_renameUserLUT_persistsCustomDisplayName() throws {
        let lutName = "lut-provider-rename-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(lutName).cube")
        try makeIdentityCube(size: 2).write(to: sourceURL, atomically: true, encoding: .utf8)
        let info = try LUTProvider.importLUT(from: sourceURL)
        importedURL = LUTProvider.userLUTDirectory()?.appendingPathComponent("\(lutName).cube")

        try LUTProvider.renameUserLUT(named: info.id, displayName: "My Favorite LUT")

        let renamed = try XCTUnwrap(LUTProvider.availableLUTs().first(where: { $0.id == info.id }))
        XCTAssertEqual(renamed.displayName, "My Favorite LUT")
    }

    func test_deleteUserLUT_removesFileAndListing() throws {
        let lutName = "lut-provider-delete-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(lutName).cube")
        try makeIdentityCube(size: 2).write(to: sourceURL, atomically: true, encoding: .utf8)
        let info = try LUTProvider.importLUT(from: sourceURL)
        importedURL = LUTProvider.userLUTDirectory()?.appendingPathComponent("\(lutName).cube")

        try LUTProvider.deleteUserLUT(named: info.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: importedURL?.path ?? ""))
        XCTAssertFalse(LUTProvider.availableLUTs().contains(where: { $0.id == info.id }))
        importedURL = nil
    }

    private func makeCube(low: Float, high: Float) -> String {
        """
        LUT_3D_SIZE 2
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        \(low) \(low) \(low)
        \(high) \(high) \(high)
        """
    }

    private func makeIdentityCube(size: Int) -> String {
        var lines = ["LUT_3D_SIZE \(size)"]
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1)
                    let gf = Float(g) / Float(size - 1)
                    let bf = Float(b) / Float(size - 1)
                    lines.append("\(rf) \(gf) \(bf)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func makeSolidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let idx = i * 4
            data[idx] = r
            data[idx + 1] = g
            data[idx + 2] = b
            data[idx + 3] = 255
        }
        return ctx.makeImage()!
    }

    private func extractPixels(from image: CGImage) -> [(r: UInt8, g: UInt8, b: UInt8)] {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var result = [(r: UInt8, g: UInt8, b: UInt8)]()
        result.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let idx = i * 4
            result.append((r: data[idx], g: data[idx + 1], b: data[idx + 2]))
        }
        return result
    }
}
