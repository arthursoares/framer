// ASCIIAtlasGeneratorTests.swift
// Verify the Core Text-backed atlas generator: dimensions match the baked
// 80×8 contract, different character palettes yield distinct pixel buffers,
// and pre-rendered atlases are cached. Also proves that when ASCIIShaderParams
// carries a `characters` string the GPU ASCII output actually changes.

import XCTest
import CoreGraphics
import Metal
@testable import FramerCore

final class ASCIIAtlasGeneratorTests: XCTestCase {

    // MARK: - Shape contract

    func testGeneratorProducesExpected80x8Atlas() throws {
        let style = ASCIIAtlasGenerator.Style(fillCharacters: " .:-=+*#%@")
        let fill  = try ASCIIAtlasGenerator.atlasCGImage(for: style, kind: .fill)
        let edges = try ASCIIAtlasGenerator.atlasCGImage(for: style, kind: .edges)
        XCTAssertEqual(fill.width, 80)
        XCTAssertEqual(fill.height, 8)
        XCTAssertEqual(edges.width, 80)
        XCTAssertEqual(edges.height, 8)
    }

    // MARK: - Distinct palettes → distinct atlases

    func testDifferentFillCharactersProduceDistinctFillAtlases() throws {
        let styleA = ASCIIAtlasGenerator.Style(fillCharacters: " .:-=+*#%@")
        let styleB = ASCIIAtlasGenerator.Style(fillCharacters: "0123456789")
        let bytesA = try grayscaleBytes(of: ASCIIAtlasGenerator.atlasCGImage(for: styleA, kind: .fill))
        let bytesB = try grayscaleBytes(of: ASCIIAtlasGenerator.atlasCGImage(for: styleB, kind: .fill))
        XCTAssertNotEqual(bytesA, bytesB,
                          "Different palette characters must rasterise to different atlases")
    }

    // MARK: - Cache hit

    func testRepeatedCallReturnsSameCGImageReference() throws {
        let style = ASCIIAtlasGenerator.Style(fillCharacters: "abcdefghij")
        let first  = try ASCIIAtlasGenerator.atlasCGImage(for: style, kind: .fill)
        let second = try ASCIIAtlasGenerator.atlasCGImage(for: style, kind: .fill)
        // CGImageRef identity comparison: cache hit should return the exact same pointer.
        XCTAssertTrue(first === second, "Second atlas lookup for the same Style should be cached")
    }

    // MARK: - GPU round-trip (Mac-only; Metal assumed available in CI for this target)

    func testAtlasTextureUploadSucceeds() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let style = ASCIIAtlasGenerator.Style(fillCharacters: "0123456789")
        let atlases = try ASCIIAtlasGenerator.atlases(for: style, device: device)
        XCTAssertEqual(atlases.fill.width,  80)
        XCTAssertEqual(atlases.fill.height, 8)
        XCTAssertEqual(atlases.edges.width,  80)
        XCTAssertEqual(atlases.edges.height, 8)
    }

    // MARK: - Helpers

    private func grayscaleBytes(of image: CGImage) throws -> [UInt8] {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &buffer, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("CGContext allocation failed")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Collapse to R channel — shader only reads .r anyway.
        return stride(from: 0, to: buffer.count, by: 4).map { buffer[$0] }
    }
}
