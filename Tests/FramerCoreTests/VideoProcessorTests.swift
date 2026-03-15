import XCTest
import AVFoundation
import CoreImage
@testable import FramerCore

final class VideoProcessorTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoProcessorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Test: No layers produces valid output

    func testProcessVideoNoLayers() async throws {
        let inputURL = tempDir.appendingPathComponent("input.mp4")
        let outputURL = tempDir.appendingPathComponent("output_no_layers.mp4")

        try await createTestVideo(at: inputURL, duration: 1.0, fps: 30)

        let processor = VideoProcessor()
        let config = ProcessingConfig(layers: [])
        let videoExport = VideoExportConfig(codec: .h264)

        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoExport
        )

        // Verify output exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        // Verify duration > 0.5s
        let asset = AVAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0.5)
    }

    // MARK: - Test: Trim produces correct duration

    func testProcessVideoWithTrim() async throws {
        let inputURL = tempDir.appendingPathComponent("input_trim.mp4")
        let outputURL = tempDir.appendingPathComponent("output_trim.mp4")

        try await createTestVideo(at: inputURL, duration: 3.0, fps: 30)

        let processor = VideoProcessor()
        let config = ProcessingConfig(layers: [])
        let trim = try TrimRange(start: 0.5, end: 1.5)
        let videoExport = VideoExportConfig(codec: .h264, trim: trim)

        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoExport
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let asset = AVAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        // Trim is 1.0s; allow tolerance
        XCTAssertGreaterThan(seconds, 0.5)
        XCTAssertLessThan(seconds, 1.8)
    }

    // MARK: - Test: Border layer increases dimensions

    func testProcessVideoWithBorder() async throws {
        let inputURL = tempDir.appendingPathComponent("input_border.mp4")
        let outputURL = tempDir.appendingPathComponent("output_border.mp4")

        try await createTestVideo(at: inputURL, duration: 1.0, fps: 30, width: 320, height: 240)

        let processor = VideoProcessor()
        let borderLayer = CompositionLayer.border(
            BorderLayerParams(thickness: .pixels(20), color: .white)
        )
        let config = ProcessingConfig(layers: [borderLayer])
        let videoExport = VideoExportConfig(codec: .h264)

        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoExport
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        // Check output dimensions: 320+40 x 240+40
        let asset = AVAsset(url: outputURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            XCTFail("No video track in output")
            return
        }
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(Int(size.width), 360)
        XCTAssertEqual(Int(size.height), 280)
    }

    // MARK: - Test: H.265 codec

    func testProcessVideoH265() async throws {
        let inputURL = tempDir.appendingPathComponent("input_h265.mp4")
        let outputURL = tempDir.appendingPathComponent("output_h265.mp4")

        try await createTestVideo(at: inputURL, duration: 1.0, fps: 30)

        let processor = VideoProcessor()
        let config = ProcessingConfig(layers: [])
        let videoExport = VideoExportConfig(codec: .h265)

        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoExport
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        // Verify it's a valid video
        let asset = AVAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0.5)
    }

    // MARK: - Test: Progress handler is called

    func testProgressHandlerCalled() async throws {
        let inputURL = tempDir.appendingPathComponent("input_progress.mp4")
        let outputURL = tempDir.appendingPathComponent("output_progress.mp4")

        try await createTestVideo(at: inputURL, duration: 1.0, fps: 30)

        let processor = VideoProcessor()
        let progressFrames = UnsafeAtomicInt(initialValue: 0)

        await processor.onProgress { progress in
            progressFrames.increment()
            XCTAssertGreaterThanOrEqual(progress.fraction, 0)
            XCTAssertLessThanOrEqual(progress.fraction, 1.1) // allow small overshoot
        }

        let config = ProcessingConfig(layers: [])
        let videoExport = VideoExportConfig(codec: .h264)

        try await processor.process(
            input: inputURL,
            output: outputURL,
            config: config,
            videoExport: videoExport
        )

        XCTAssertGreaterThan(progressFrames.load(), 0)
    }

    // MARK: - Helper: Create test video

    private func createTestVideo(
        at url: URL,
        duration: Double = 1.0,
        fps: Int = 30,
        width: Int = 320,
        height: Int = 240
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(fps))
        let ciContext = CIContext()

        for frame in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            var pixelBuffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer pool"])
            }
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else {
                throw NSError(domain: "Test", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
            }

            // Fill with a solid color (blue)
            let color = CIColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
            let colorImage = CIImage(color: color)
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            ciContext.render(colorImage, to: buffer)

            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            adaptor.append(buffer, withPresentationTime: time)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw NSError(domain: "Test", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Test video creation failed: \(writer.error?.localizedDescription ?? "unknown")"
            ])
        }
    }
}

// MARK: - Simple Atomic Counter for Sendable Progress Tracking

/// A simple atomic integer for thread-safe counting in tests.
private final class UnsafeAtomicInt: @unchecked Sendable {
    private var _value: Int
    private let lock = NSLock()

    init(initialValue: Int = 0) {
        _value = initialValue
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
