import Foundation
import AVFoundation
import CoreImage

/// Orchestrates video processing: AVAssetReader → CIFilterPipeline → AVAssetWriter
/// with audio passthrough.
public actor VideoProcessor {

    public struct Progress: Sendable {
        public let currentFrame: Int
        public let totalFrames: Int
        public var fraction: Double { Double(currentFrame) / Double(max(totalFrames, 1)) }
    }

    private let ciContext: CIContext
    private var progressHandler: (@Sendable (Progress) -> Void)?

    public init() {
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    public func onProgress(_ handler: @escaping @Sendable (Progress) -> Void) {
        self.progressHandler = handler
    }

    public func process(
        input: URL,
        output: URL,
        config: ProcessingConfig,
        videoExport: VideoExportConfig
    ) async throws {
        let asset = AVAsset(url: input)

        // Load video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw FramerError.invalidImage(input)
        }

        // Load properties
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let fps = nominalFrameRate > 0 ? nominalFrameRate : 30.0

        // Compute time range from trim
        let timeRange: CMTimeRange
        if let trim = videoExport.trim {
            let startTime = CMTime(seconds: trim.start, preferredTimescale: 600)
            let endTime = CMTime(seconds: trim.end, preferredTimescale: 600)
            let clampedEnd = min(endTime, duration)
            timeRange = CMTimeRange(start: startTime, end: clampedEnd)
        } else {
            timeRange = CMTimeRange(start: .zero, duration: duration)
        }

        // Compute output size
        let layers = config.layers ?? CompositionLayer.defaultLayers()
        let inputSize = CGSize(width: naturalSize.width, height: naturalSize.height)
        let outputSize = OutputSizeCalculator.outputSize(for: inputSize, layers: layers)
        let outputWidth = Int(outputSize.width)
        let outputHeight = Int(outputSize.height)

        // Estimate total frames for progress
        let totalSeconds = CMTimeGetSeconds(timeRange.duration)
        let totalFrames = max(1, Int(totalSeconds * Double(fps)))

        // Set up reader
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        videoReaderOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoReaderOutput) else {
            throw FramerError.encodingFailed(output)
        }
        reader.add(videoReaderOutput)

        // Audio track (optional, passthrough)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioTrack = audioTracks.first
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            let aOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            aOutput.alwaysCopiesSampleData = false
            if reader.canAdd(aOutput) {
                reader.add(aOutput)
                audioReaderOutput = aOutput
            }
        }

        // Set up writer
        let videoCodec: AVVideoCodecType = videoExport.codec == .h265 ? .hevc : .h264
        let writerVideoSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight
        ]

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerVideoSettings)
        videoWriterInput.expectsMediaDataInRealTime = false

        let sourcePixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: sourcePixelAttributes
        )

        guard writer.canAdd(videoWriterInput) else {
            throw FramerError.encodingFailed(output)
        }
        writer.add(videoWriterInput)

        // Audio writer input (passthrough)
        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            aInput.expectsMediaDataInRealTime = false
            if writer.canAdd(aInput) {
                writer.add(aInput)
                audioWriterInput = aInput
            }
        }

        // Start reading/writing
        guard reader.startReading() else {
            throw FramerError.encodingFailed(output)
        }
        guard writer.startWriting() else {
            cleanupPartialFile(at: output)
            throw FramerError.encodingFailed(output)
        }
        writer.startSession(atSourceTime: timeRange.start)

        // Process video frames
        let exif = ExifData()
        var frameIndex = 0

        while let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Apply filter pipeline
            let processedImage = CIFilterPipeline.apply(
                layers: layers,
                to: sourceImage,
                sourceImage: sourceImage,
                exif: exif
            )

            // Wait for writer input to be ready
            while !videoWriterInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            // Get output pixel buffer from pool
            guard let pool = pixelBufferAdaptor.pixelBufferPool else {
                cleanupPartialFile(at: output)
                throw FramerError.encodingFailed(output)
            }

            var outputPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)
            guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
                cleanupPartialFile(at: output)
                throw FramerError.encodingFailed(output)
            }

            // Render processed image into output buffer
            ciContext.render(processedImage, to: outputBuffer)

            // Append to writer
            guard pixelBufferAdaptor.append(outputBuffer, withPresentationTime: presentationTime) else {
                cleanupPartialFile(at: output)
                throw FramerError.encodingFailed(output)
            }

            frameIndex += 1
            progressHandler?(Progress(currentFrame: frameIndex, totalFrames: totalFrames))
        }

        // Check reader status
        if reader.status == .failed {
            cleanupPartialFile(at: output)
            throw FramerError.encodingFailed(output)
        }

        // Copy audio buffers
        if let audioReaderOutput, let audioWriterInput {
            while let audioBuffer = audioReaderOutput.copyNextSampleBuffer() {
                while !audioWriterInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                audioWriterInput.append(audioBuffer)
            }
            audioWriterInput.markAsFinished()
        }

        // Finish writing
        videoWriterInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            cleanupPartialFile(at: output)
            throw FramerError.encodingFailed(output)
        }
    }

    // MARK: - Private

    private func cleanupPartialFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
