import XCTest
import CoreGraphics
import FramerCore
@testable import Framer

@MainActor
final class PreviewViewModelLifecycleTests: XCTestCase {
    func test_requestStateClearsDifferentPhotoButRetainsSamePhotoPreview() async throws {
        let renderer = ControlledMacPreviewRenderer()
        let viewModel = PreviewViewModel(
            renderer: { url, config, rotation in
                try await renderer.render(url: url, config: config, rotation: rotation)
            },
            exifLoader: { _ in ExifData(camera: "Test Camera") }
        )
        let first = PhotoItem(url: URL(fileURLWithPath: "/tmp/first.jpg"))
        let second = PhotoItem(url: URL(fileURLWithPath: "/tmp/second.jpg"))

        let firstTask = try XCTUnwrap(viewModel.updatePreview(for: first, config: .default))
        XCTAssertTrue(viewModel.isLoading)
        await renderer.waitUntilStarted(requestCount: 1)
        await renderer.finish(request: 0, result: .success(Self.image(width: 4, height: 3)))
        await firstTask.value
        XCTAssertEqual(viewModel.exifData?.camera, "Test Camera")

        let samePhotoTask = try XCTUnwrap(viewModel.updatePreview(for: first, config: .default))
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNotNil(viewModel.previewImage)
        XCTAssertEqual(viewModel.outputSize, CGSize(width: 4, height: 3))

        let differentPhotoTask = try XCTUnwrap(viewModel.updatePreview(for: second, config: .default))
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.previewImage)
        XCTAssertNil(viewModel.outputSize)
        XCTAssertNil(viewModel.exifData)

        XCTAssertNil(viewModel.updatePreview(for: nil, config: .default))
        await samePhotoTask.value
        await differentPhotoTask.value
    }

    func test_renderFailureCanBeRetriedWithoutShowingStaleError() async throws {
        let renderer = ControlledMacPreviewRenderer()
        let viewModel = PreviewViewModel(
            renderer: { url, config, rotation in
                try await renderer.render(url: url, config: config, rotation: rotation)
            },
            exifLoader: { _ in nil }
        )
        let item = PhotoItem(url: URL(fileURLWithPath: "/tmp/retry.jpg"))

        let failedTask = try XCTUnwrap(viewModel.updatePreview(for: item, config: .default))
        await renderer.waitUntilStarted(requestCount: 1)
        await renderer.finish(request: 0, result: .failure(MacPreviewTestError.stale))
        await failedTask.value
        XCTAssertNotNil(viewModel.error)

        let retryTask = try XCTUnwrap(viewModel.updatePreview(for: item, config: .default))
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        await renderer.waitUntilStarted(requestCount: 2)
        await renderer.finish(request: 1, result: .success(Self.image(width: 5, height: 2)))
        await retryTask.value

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.outputSize, CGSize(width: 5, height: 2))
    }

    func test_originalLoaderUsesRotationAndRejectsStaleABACompletion() async throws {
        let loader = ControlledMacOriginalLoader()
        let viewModel = PreviewViewModel(
            renderer: { _, _, _ in Self.image(width: 1, height: 1) },
            exifLoader: { _ in nil },
            originalLoader: { url, rotation in
                try await loader.load(url: url, rotation: rotation)
            }
        )
        var item = PhotoItem(url: URL(fileURLWithPath: "/tmp/original.jpg"))

        let firstTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        XCTAssertTrue(viewModel.isOriginalLoading)
        await loader.waitUntilStarted(requestCount: 1)

        item.rotation = 90
        let secondTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        await loader.waitUntilStarted(requestCount: 2)

        item.rotation = 0
        let thirdTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        await loader.waitUntilStarted(requestCount: 3)
        let rotations = await loader.rotations
        XCTAssertEqual(rotations, [0, 90, 0])

        await loader.finish(request: 0, result: .success(Self.image(width: 7, height: 1)))
        await firstTask.value
        XCTAssertNil(viewModel.originalImage)
        XCTAssertTrue(viewModel.isOriginalLoading)

        await loader.finish(request: 1, result: .failure(MacPreviewTestError.stale))
        await secondTask.value
        XCTAssertNil(viewModel.originalError)

        await loader.finish(request: 2, result: .success(Self.image(width: 3, height: 2)))
        await thirdTask.value
        XCTAssertNotNil(viewModel.originalImage)
        XCTAssertFalse(viewModel.isOriginalLoading)
        XCTAssertNil(viewModel.originalError)
    }

    func test_originalFailureCanBeRetried() async throws {
        let loader = ControlledMacOriginalLoader()
        let viewModel = PreviewViewModel(
            renderer: { _, _, _ in Self.image(width: 1, height: 1) },
            exifLoader: { _ in nil },
            originalLoader: { url, rotation in
                try await loader.load(url: url, rotation: rotation)
            }
        )
        let item = PhotoItem(url: URL(fileURLWithPath: "/tmp/original-retry.jpg"))

        let failedTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        await loader.waitUntilStarted(requestCount: 1)
        await loader.finish(request: 0, result: .failure(MacPreviewTestError.stale))
        await failedTask.value
        XCTAssertNotNil(viewModel.originalError)
        XCTAssertFalse(viewModel.isOriginalLoading)

        let retryTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        XCTAssertNil(viewModel.originalError)
        XCTAssertTrue(viewModel.isOriginalLoading)
        await loader.waitUntilStarted(requestCount: 2)
        await loader.finish(request: 1, result: .success(Self.image(width: 2, height: 3)))
        await retryTask.value

        XCTAssertNotNil(viewModel.originalImage)
        XCTAssertNil(viewModel.originalError)
        XCTAssertFalse(viewModel.isOriginalLoading)
    }

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

    private nonisolated static func image(width: Int, height: Int) -> CGImage {
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

private actor ControlledMacOriginalLoader {
    private var continuations: [Int: CheckedContinuation<CGImage, Error>] = [:]
    private var startedCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var rotations: [Int] = []

    func load(url: URL, rotation: Int) async throws -> CGImage {
        _ = url
        rotations.append(rotation)
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
