import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import VideoToolbox

/// Orchestrates video processing: AVAssetReader → hybrid GPU/CPU pipeline → AVAssetWriter
/// with audio passthrough.
///
/// Uses a multi-pass approach per frame:
/// 1. Partition the layer stack into GPU-capable and CPU-only runs
/// 2. GPU runs use CIFilterPipeline (Core Image) — stays on GPU, no CGImage conversion
/// 3. CPU runs use BorderRenderer — converts to CGImage, processes, converts back
/// This maximizes GPU utilization while ensuring full feature parity (captions, color dithering).
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
        // AVAssetWriter fails if output file already exists — remove it first
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

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

        // Check HEVC hardware support; fall back to H.264 if unavailable
        var effectiveCodec = videoExport.codec
        if effectiveCodec == .h265 {
            if !VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) {
                effectiveCodec = .h264
                print("Warning: HEVC hardware encoding not available, falling back to H.264")
            }
        }

        // Set up writer
        let videoCodec: AVVideoCodecType = effectiveCodec == .h265 ? .hevc : .h264
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

        // Partition layers into GPU and CPU runs (computed once, reused per frame)
        let layerPartitions = CIFilterPipeline.partitionLayers(layers)
        let allGPU = layerPartitions.allSatisfy(\.isGPU)

        // Process video frames
        let exif = ExifData()
        var frameIndex = 0
        while let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            let processedCGImage: CGImage

            if allGPU {
                // Fast path: entire layer stack on GPU, single CIImage pass
                let sourceCI = CIImage(cvPixelBuffer: pixelBuffer)
                let resultCI = CIFilterPipeline.apply(layers: layers, to: sourceCI, sourceImage: sourceCI, exif: exif)
                guard let cg = ciContext.createCGImage(resultCI, from: resultCI.extent) else { continue }
                processedCGImage = cg
            } else {
                // Hybrid path: alternate between GPU and CPU runs
                var currentCI = CIImage(cvPixelBuffer: pixelBuffer)
                let sourceCI = currentCI

                for partition in layerPartitions {
                    if partition.isGPU {
                        // GPU run — process via CIFilterPipeline, stay as CIImage
                        currentCI = CIFilterPipeline.apply(
                            layers: partition.layers,
                            to: currentCI,
                            sourceImage: sourceCI,
                            exif: exif
                        )
                    } else {
                        // CPU run — convert to CGImage, process via BorderRenderer, convert back
                        guard let cgInput = ciContext.createCGImage(currentCI, from: currentCI.extent) else { continue }
                        let borderResult = try BorderRenderer.applyLayers(
                            partition.layers,
                            to: cgInput,
                            sourceImage: cgInput,
                            exif: exif
                        )
                        currentCI = CIImage(cgImage: borderResult.image)
                    }
                }

                guard let cg = ciContext.createCGImage(currentCI, from: currentCI.extent) else { continue }
                processedCGImage = cg
            }

            // Wait for writer input to be ready
            while !videoWriterInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            // Get output pixel buffer from pool
            guard let pool = pixelBufferAdaptor.pixelBufferPool else {
                cleanupPartialFile(at: output)
                throw FramerError.encodingFailed(output)
            }

            // Convert processed CGImage → CVPixelBuffer
            guard let outputBuffer = self.pixelBuffer(from: processedCGImage, pool: pool) else {
                cleanupPartialFile(at: output)
                throw FramerError.encodingFailed(output)
            }

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

    private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func pixelBuffer(from cgImage: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        guard let pixelBuffer = pb else { return nil }
        ciContext.render(CIImage(cgImage: cgImage), to: pixelBuffer)
        return pixelBuffer
    }

    private func cleanupPartialFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
