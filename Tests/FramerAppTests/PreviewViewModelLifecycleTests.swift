import XCTest
import CoreGraphics
import FramerCore
@testable import Framer

@MainActor
final class PreviewViewModelLifecycleTests: XCTestCase {
    func test_nilSelectionInvalidatesInFlightRender() async throws {
        let renderer = ControlledMacPreviewRenderer()
        let viewModel = PreviewViewModel(
            renderer: { url, config, rotation in
                try await renderer.render(url: url, config: config, rotation: rotation)
            },
            exifLoader: { _ in nil }
        )
        let item = PhotoItem(url: URL(fileURLWithPath: "/tmp/first.jpg"))

        let renderTask = try XCTUnwrap(viewModel.updatePreview(for: item, config: .default))
        await renderer.waitUntilStarted(requestCount: 1)
        XCTAssertNil(viewModel.updatePreview(for: nil, config: .default))
        await renderer.finish(request: 0, result: .success(Self.image(width: 4, height: 4)))
        await renderTask.value

        XCTAssertNil(viewModel.previewImage)
        XCTAssertNil(viewModel.outputSize)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_staleCompletionCannotClearOrOverwriteNewerRender() async throws {
        let renderer = ControlledMacPreviewRenderer()
        let viewModel = PreviewViewModel(
            renderer: { url, config, rotation in
                try await renderer.render(url: url, config: config, rotation: rotation)
            },
            exifLoader: { _ in nil }
        )
        let sharedURL = URL(fileURLWithPath: "/tmp/shared.jpg")
        let first = PhotoItem(url: sharedURL)
        var second = PhotoItem(url: sharedURL)
        second.rotation = 90

        let firstTask = try XCTUnwrap(viewModel.updatePreview(for: first, config: .default))
        await renderer.waitUntilStarted(requestCount: 1)
        let secondTask = try XCTUnwrap(viewModel.updatePreview(for: second, config: .default))
        await renderer.waitUntilStarted(requestCount: 2)

        await renderer.finish(request: 0, result: .failure(MacPreviewTestError.stale))
        await firstTask.value
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.error)

        await renderer.finish(request: 1, result: .success(Self.image(width: 3, height: 2)))
        await secondTask.value
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.outputSize, CGSize(width: 3, height: 2))
    }

    private static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

private enum MacPreviewTestError: Error {
    case stale
}

private actor ControlledMacPreviewRenderer {
    private var continuations: [Int: CheckedContinuation<CGImage, Error>] = [:]
    private var startedCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func render(url: URL, config: ProcessingConfig, rotation: Int) async throws -> CGImage {
        _ = config
        _ = rotation
        return try await withCheckedThrowingContinuation { continuation in
            continuations[startedCount] = continuation
            startedCount += 1
            resumeStartWaiters()
        }
    }

    func waitUntilStarted(requestCount: Int) async {
        guard startedCount < requestCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((requestCount, continuation))
        }
    }

    func finish(request: Int, result: Result<CGImage, Error>) {
        continuations.removeValue(forKey: request)?.resume(with: result)
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { startedCount >= $0.count }
        startWaiters.removeAll { startedCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}
