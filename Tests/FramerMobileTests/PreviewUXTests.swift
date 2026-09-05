import XCTest
import CoreGraphics
import FramerCore
@testable import FramerMobile

@MainActor
final class PreviewUXTests: XCTestCase {
    func test_comparisonPressRestoresPreviousModeWhenReleasedDuringPan() {
        var state = PreviewArea.ComparisonPressState()

        XCTAssertEqual(
            state.update(isPressing: true, isDragging: false, currentMode: false),
            true
        )
        XCTAssertEqual(
            state.update(isPressing: false, isDragging: true, currentMode: true),
            false
        )

        XCTAssertEqual(
            state.update(isPressing: true, isDragging: false, currentMode: true),
            true
        )
        XCTAssertEqual(
            state.update(isPressing: false, isDragging: false, currentMode: true),
            true
        )
    }

    func test_comparisonPressDoesNotOverrideExplicitSelectionOrStartDuringPan() {
        var state = PreviewArea.ComparisonPressState()

        XCTAssertNil(state.update(isPressing: true, isDragging: true, currentMode: false))
        XCTAssertEqual(state.select(false), false)
        XCTAssertNil(state.update(isPressing: false, isDragging: false, currentMode: false))

        XCTAssertEqual(
            state.update(isPressing: true, isDragging: false, currentMode: false),
            true
        )
        XCTAssertEqual(state.select(false), false)
        XCTAssertNil(state.update(isPressing: false, isDragging: false, currentMode: false))
    }

    func test_requestStateClearsDifferentPhotoButRetainsSamePhotoPreview() async throws {
        let renderer = ControlledMobileUXRenderer()
        let viewModel = PreviewViewModel(renderer: { url, config, rotation in
            try await renderer.render(url: url, config: config, rotation: rotation)
        })
        let first = PhotoItem(url: URL(fileURLWithPath: "/tmp/mobile-first.jpg"))
        let second = PhotoItem(url: URL(fileURLWithPath: "/tmp/mobile-second.jpg"))

        let firstTask = try XCTUnwrap(viewModel.updatePreview(for: first, config: .default))
        XCTAssertTrue(viewModel.isLoading)
        await renderer.waitUntilStarted(requestCount: 1)
        await renderer.finish(request: 0, result: .success(Self.image(width: 4, height: 3)))
        await firstTask.value

        let samePhotoTask = try XCTUnwrap(viewModel.updatePreview(for: first, config: .default))
        XCTAssertNotNil(viewModel.previewImage)
        XCTAssertTrue(viewModel.isLoading)

        let differentPhotoTask = try XCTUnwrap(viewModel.updatePreview(for: second, config: .default))
        XCTAssertNil(viewModel.previewImage)
        XCTAssertNil(viewModel.outputSize)
        XCTAssertTrue(viewModel.isLoading)

        XCTAssertNil(viewModel.updatePreview(for: nil, config: .default))
        await samePhotoTask.value
        await differentPhotoTask.value
    }

    func test_originalLoaderUsesRotationAndRejectsStaleABACompletion() async throws {
        let loader = ControlledMobileOriginalLoader()
        let viewModel = PreviewViewModel(
            renderer: { _, _, _ in Self.image(width: 1, height: 1) },
            originalLoader: { url, rotation in
                try await loader.load(url: url, rotation: rotation)
            }
        )
        var item = PhotoItem(url: URL(fileURLWithPath: "/tmp/mobile-original.jpg"))

        let firstTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
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

        await loader.finish(request: 1, result: .failure(MobileUXTestError.failed))
        await secondTask.value
        XCTAssertNil(viewModel.originalError)

        await loader.finish(request: 2, result: .success(Self.image(width: 3, height: 2)))
        await thirdTask.value
        XCTAssertEqual(viewModel.originalImage?.size, CGSize(width: 3, height: 2))
        XCTAssertFalse(viewModel.isOriginalLoading)
        XCTAssertNil(viewModel.originalError)
    }

    func test_previewAndOriginalFailuresCanBeRetried() async throws {
        let renderer = ControlledMobileUXRenderer()
        let loader = ControlledMobileOriginalLoader()
        let viewModel = PreviewViewModel(
            renderer: { url, config, rotation in
                try await renderer.render(url: url, config: config, rotation: rotation)
            },
            originalLoader: { url, rotation in
                try await loader.load(url: url, rotation: rotation)
            }
        )
        let item = PhotoItem(url: URL(fileURLWithPath: "/tmp/mobile-retry.jpg"))

        let failedPreviewTask = try XCTUnwrap(viewModel.updatePreview(for: item, config: .default))
        await renderer.waitUntilStarted(requestCount: 1)
        await renderer.finish(request: 0, result: .failure(MobileUXTestError.failed))
        await failedPreviewTask.value
        XCTAssertNotNil(viewModel.error)

        let retryPreviewTask = try XCTUnwrap(viewModel.updatePreview(for: item, config: .default))
        XCTAssertNil(viewModel.error)
        await renderer.waitUntilStarted(requestCount: 2)
        await renderer.finish(request: 1, result: .success(Self.image(width: 5, height: 4)))
        await retryPreviewTask.value
        XCTAssertEqual(viewModel.outputSize, CGSize(width: 5, height: 4))

        let failedOriginalTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        await loader.waitUntilStarted(requestCount: 1)
        await loader.finish(request: 0, result: .failure(MobileUXTestError.failed))
        await failedOriginalTask.value
        XCTAssertNotNil(viewModel.originalError)

        let retryOriginalTask = try XCTUnwrap(viewModel.loadOriginalIfNeeded(for: item))
        XCTAssertNil(viewModel.originalError)
        XCTAssertTrue(viewModel.isOriginalLoading)
        await loader.waitUntilStarted(requestCount: 2)
        await loader.finish(request: 1, result: .success(Self.image(width: 2, height: 3)))
        await retryOriginalTask.value
        XCTAssertEqual(viewModel.originalImage?.size, CGSize(width: 2, height: 3))
        XCTAssertFalse(viewModel.isOriginalLoading)
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

private enum MobileUXTestError: Error {
    case failed
}

private actor ControlledMobileUXRenderer {
    private var continuations: [Int: CheckedContinuation<CGImage, Error>] = [:]
    private var startedCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func render(url: URL, config: ProcessingConfig, rotation: Int) async throws -> CGImage {
        _ = url
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

private actor ControlledMobileOriginalLoader {
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
