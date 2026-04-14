import Foundation
import CoreGraphics

public struct EffectPreviewComparisonTolerance: Sendable {
    public let averageAbsoluteChannelDelta: Double

    public init(averageAbsoluteChannelDelta: Double) {
        self.averageAbsoluteChannelDelta = averageAbsoluteChannelDelta
    }

    public static let previewExportDefault = EffectPreviewComparisonTolerance(averageAbsoluteChannelDelta: 0.6)
}

public enum EffectPreviewComparator {
    public static func imagesMatch(
        _ preview: CGImage,
        _ exported: CGImage,
        tolerance: EffectPreviewComparisonTolerance
    ) throws -> Bool {
        try averageAbsoluteChannelDelta(preview, exported) <= tolerance.averageAbsoluteChannelDelta
    }

    public static func averageAbsoluteChannelDelta(
        _ preview: CGImage,
        _ exported: CGImage
    ) throws -> Double {
        let previewData = try normalizedPixelData(for: preview, targetSize: CGSize(width: preview.width, height: preview.height))
        let exportedData = try normalizedPixelData(for: exported, targetSize: CGSize(width: preview.width, height: preview.height))

        guard previewData.count == exportedData.count, !previewData.isEmpty else { return .infinity }

        var totalDelta: Double = 0
        for (lhs, rhs) in zip(previewData, exportedData) {
            totalDelta += abs(Double(lhs) - Double(rhs)) / 255.0
        }

        return totalDelta / Double(previewData.count)
    }

    private static func normalizedPixelData(for image: CGImage, targetSize: CGSize) throws -> [UInt8] {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FramerError.encodingFailed(URL(fileURLWithPath: "/effect-preview-comparator"))
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }
}
