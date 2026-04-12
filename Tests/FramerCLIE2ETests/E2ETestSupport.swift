import Foundation
import ImageIO
import XCTest

struct SingleExportManifest: Decodable {
    let outputFilename: String
    let expectedWidth: Int
    let expectedHeight: Int
    let format: String
    let preservesMetadata: Bool
}

enum E2ETestSupport {
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var fixturesRoot: URL {
        repoRoot.appendingPathComponent("Tests/E2EFixtures", isDirectory: true)
    }

    static var builtCLI: URL {
        repoRoot.appendingPathComponent(".build/debug/framer")
    }

    static func imageSize(at url: URL) throws -> CGSize {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw XCTSkip("Unable to read image properties for \(url.path)")
        }
        return CGSize(width: width, height: height)
    }

    static func makeTemporaryDirectory(named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func hasExifDate(at url: URL) throws -> Bool {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else {
            return false
        }

        return exif[kCGImagePropertyExifDateTimeOriginal] != nil
    }
}
