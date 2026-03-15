import SwiftUI
@preconcurrency import AVFoundation

@MainActor
@Observable
final class VideoPlayerViewModel {
    var asset: AVAsset?
    var duration: TimeInterval = 0
    var playheadPosition: TimeInterval = 0
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 0
    var thumbnails: [CGImage] = []
    var isLoading = false

    private var imageGenerator: AVAssetImageGenerator?
    private var loadTask: Task<Void, Never>?

    /// Whether the user has actually trimmed away from full duration.
    var isTrimmed: Bool {
        trimStart > 0.01 || (duration > 0 && abs(trimEnd - duration) > 0.01)
    }

    /// The trim range as a (start, end) pair, only if the user has actually trimmed.
    var trimRange: (start: TimeInterval, end: TimeInterval)? {
        guard isTrimmed else { return nil }
        return (start: trimStart, end: trimEnd)
    }

    /// The trimmed duration.
    var trimmedDuration: TimeInterval {
        max(0, trimEnd - trimStart)
    }

    func load(url: URL) async {
        loadTask?.cancel()
        thumbnails = []
        isLoading = true

        let avAsset = AVURLAsset(url: url)
        self.asset = avAsset

        do {
            let durationCM = try await avAsset.load(.duration)
            let seconds = CMTimeGetSeconds(durationCM)
            guard seconds.isFinite, seconds > 0 else {
                isLoading = false
                return
            }
            self.duration = seconds
            self.trimStart = 0
            self.trimEnd = seconds
            self.playheadPosition = 0

            let generator = AVAssetImageGenerator(asset: avAsset)
            generator.maximumSize = CGSize(width: 80, height: 60)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            self.imageGenerator = generator

            await generateThumbnails()
        } catch {
            // Asset loading failed — leave duration at 0
        }

        isLoading = false
    }

    func frameAtPlayhead() async -> CGImage? {
        guard let generator = imageGenerator else { return nil }
        let time = CMTime(seconds: playheadPosition, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: time).image
    }

    func seekTo(_ position: TimeInterval) {
        playheadPosition = min(max(position, trimStart), trimEnd)
    }

    private func generateThumbnails() async {
        guard let generator = imageGenerator, duration > 0 else { return }

        // ~2 thumbnails per second, capped at 60
        let count = min(60, max(1, Int(duration * 2)))
        let interval = duration / Double(count)

        var times: [CMTime] = []
        for i in 0..<count {
            times.append(CMTime(seconds: Double(i) * interval, preferredTimescale: 600))
        }

        var generated: [CGImage] = []
        for time in times {
            guard !Task.isCancelled else { return }
            if let cgImage = try? await generator.image(at: time).image {
                generated.append(cgImage)
            }
        }

        guard !Task.isCancelled else { return }
        self.thumbnails = generated
    }
}
