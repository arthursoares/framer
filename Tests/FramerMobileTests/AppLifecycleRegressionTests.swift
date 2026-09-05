import XCTest
import CoreGraphics
import FramerCore
@testable import FramerMobile

@MainActor
final class AppLifecycleRegressionTests: XCTestCase {
    func test_editorFallbackLayersKeepStableIdentityWithoutChangingConfig() throws {
        let state = AppState()
        let initialConfig = state.currentConfig
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let initialEncoding = try encoder.encode(initialConfig)

        let initialIDs = state.editorLayers.map(\.id)
        XCTAssertFalse(initialIDs.isEmpty)
        XCTAssertEqual(state.editorLayers.map(\.id), initialIDs)
        XCTAssertEqual(state.currentConfig, initialConfig)
        XCTAssertEqual(try encoder.encode(state.currentConfig), initialEncoding)
        XCTAssertNil(state.currentConfig.layers)

        var customizedLegacyConfig = ProcessingConfig.default
        customizedLegacyConfig.padding = 37
        let customizedEncoding = try encoder.encode(customizedLegacyConfig)
        state.currentConfig = customizedLegacyConfig
        state.activePresetName = "Legacy"
        state.appliedPresetConfig = customizedLegacyConfig

        XCTAssertEqual(state.editorLayers.map(\.id), initialIDs)
        XCTAssertEqual(state.currentConfig, customizedLegacyConfig)
        XCTAssertEqual(state.appliedPresetConfig, customizedLegacyConfig)
        XCTAssertEqual(try encoder.encode(state.currentConfig), customizedEncoding)
        XCTAssertNil(state.currentConfig.layers)
        XCTAssertFalse(state.isPresetModified)

        state.editorLayers[0].isEnabled.toggle()
        XCTAssertNotNil(state.currentConfig.layers)
        XCTAssertTrue(state.isPresetModified)
    }

    func test_presetRenderKeyTracksPhotoRotationAndPresetConfiguration() {
        let photoID = UUID()
        let presetID = UUID()
        let original = Preset(id: presetID, name: "Preset", config: .default)
        var changedConfig = ProcessingConfig.default
        changedConfig.outputFormat = .png
        let changed = Preset(id: presetID, name: "Preset", config: changedConfig)

        let baseline = MobilePresetPreviewRenderKey(
            photoID: photoID,
            photoRotation: 0,
            presets: [original]
        )

        XCTAssertNotEqual(
            baseline,
            MobilePresetPreviewRenderKey(photoID: UUID(), photoRotation: 0, presets: [original])
        )
        XCTAssertNotEqual(
            baseline,
            MobilePresetPreviewRenderKey(photoID: photoID, photoRotation: 90, presets: [original])
        )
        XCTAssertNotEqual(
            baseline,
            MobilePresetPreviewRenderKey(photoID: photoID, photoRotation: 0, presets: [changed])
        )
    }

    func test_stalePresetBatchCannotWriteAfterReplacement() async throws {
        let renderer = ControlledPresetRenderer()
        let cache = PresetPreviewCache(
            debounce: nil,
            renderer: { url, rotation, preset, maxDimension in
                try await renderer.render(
                    url: url,
                    rotation: rotation,
                    preset: preset,
                    maxDimension: maxDimension
                )
            }
        )
        let photo = PhotoItem(url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        let presetID = UUID()
        let oldPreset = Preset(id: presetID, name: "Preset", config: .default)
        var replacementConfig = ProcessingConfig.default
        replacementConfig.outputFormat = .png
        let newPreset = Preset(id: presetID, name: "Preset", config: replacementConfig)

        let oldTask = cache.regenerate(for: photo, presets: [oldPreset])
        await renderer.waitUntilStarted(requestCount: 1)
        let newTask = cache.regenerate(for: photo, presets: [newPreset])
        await renderer.waitUntilStarted(requestCount: 2)

        await renderer.finish(request: 1, image: Self.image(width: 2, height: 2))
        await newTask.value
        await renderer.finish(request: 0, image: Self.image(width: 1, height: 1))
        await oldTask.value

        XCTAssertEqual(cache.previews[presetID]?.cgImage?.width, 2)
    }

    func test_replacingPresetBatchCancelsInFlightRenderer() async {
        let replacementImage = Self.image(width: 2, height: 2)
        let renderer = CancellationAwarePresetRenderer(replacementImage: replacementImage)
        let cache = PresetPreviewCache(
            debounce: nil,
            renderer: { url, rotation, preset, maxDimension in
                try await renderer.render(
                    url: url,
                    rotation: rotation,
                    preset: preset,
                    maxDimension: maxDimension
                )
            }
        )
        let photo = PhotoItem(url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        let oldPreset = Preset(name: "Old", config: .default)
        let newPreset = Preset(name: "New", config: .default)

        let oldTask = cache.regenerate(for: photo, presets: [oldPreset])
        await renderer.waitUntilOldRenderStarted()
        let newTask = cache.regenerate(for: photo, presets: [newPreset])
        await renderer.releaseOldRender()
        await oldTask.value
        await newTask.value

        let oldRenderWasCancelled = await renderer.oldRenderWasCancelled
        XCTAssertTrue(oldRenderWasCancelled)
        XCTAssertEqual(cache.previews[newPreset.id]?.cgImage?.width, 2)
    }

    func test_stalePhotoImportCleansFilesWithoutClearingNewImportState() async throws {
        let firstGate = ControlledImportOperation()
        let secondGate = ControlledImportOperation()
        let coordinator = PhotoImportCoordinator()
        let staleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: staleURL)
        var completions: [[PhotoItem]] = []
        var clearCount = 0

        let firstTask = coordinator.start(
            operation: { await firstGate.result() },
            onComplete: { completions.append($0) },
            clearSelection: { clearCount += 1 }
        )
        await firstGate.waitUntilStarted()

        let secondTask = coordinator.start(
            operation: { await secondGate.result() },
            onComplete: { completions.append($0) },
            clearSelection: { clearCount += 1 }
        )
        await secondGate.waitUntilStarted()
        await firstGate.finish(PhotoImportResult(items: [], temporaryURLs: [staleURL]))
        await firstTask.value

        XCTAssertTrue(coordinator.isLoading)
        XCTAssertEqual(clearCount, 0)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))

        let imported = PhotoItem(url: URL(fileURLWithPath: "/tmp/new.jpg"))
        await secondGate.finish(PhotoImportResult(items: [imported], temporaryURLs: []))
        await secondTask.value

        XCTAssertFalse(coordinator.isLoading)
        XCTAssertEqual(clearCount, 1)
        XCTAssertEqual(completions.flatMap { $0 }.map(\.id), [imported.id])
    }

    func test_staleMobilePreviewCannotClearOrOverwriteNewerRender() async throws {
        let renderer = ControlledPreviewRenderer()
        let viewModel = PreviewViewModel(renderer: { url, config, rotation in
            try await renderer.render(url: url, config: config, rotation: rotation)
        })
        let sharedURL = URL(fileURLWithPath: "/tmp/shared.jpg")
        let first = PhotoItem(url: sharedURL)
        var second = PhotoItem(url: sharedURL)
        second.rotation = 90

        let firstTask = try XCTUnwrap(viewModel.updatePreview(for: first, config: .default))
        await renderer.waitUntilStarted(requestCount: 1)
        let secondTask = try XCTUnwrap(viewModel.updatePreview(for: second, config: .default))
        await renderer.waitUntilStarted(requestCount: 2)

        await renderer.finish(request: 0, result: .failure(TestError.stale))
        await firstTask.value
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.error)

        await renderer.finish(request: 1, result: .success(Self.image(width: 3, height: 2)))
        await secondTask.value
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.outputSize, CGSize(width: 3, height: 2))
    }

    func test_nilSelectionInvalidatesMobilePreviewRender() async throws {
        let renderer = ControlledPreviewRenderer()
        let viewModel = PreviewViewModel(renderer: { url, config, rotation in
            try await renderer.render(url: url, config: config, rotation: rotation)
        })
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

private enum TestError: Error {
    case stale
}

private actor ControlledPreviewRenderer {
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

private actor ControlledPresetRenderer {
    private var continuations: [Int: CheckedContinuation<CGImage, Error>] = [:]
    private var startedCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func render(
        url: URL,
        rotation: Int,
        preset: Preset,
        maxDimension: Int
    ) async throws -> CGImage {
        _ = url
        _ = rotation
        _ = maxDimension
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

    func finish(request: Int, image: CGImage) {
        continuations.removeValue(forKey: request)?.resume(returning: image)
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { startedCount >= $0.count }
        startWaiters.removeAll { startedCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}

private actor CancellationAwarePresetRenderer {
    let replacementImage: CGImage
    private(set) var oldRenderWasCancelled = false
    private var oldRenderStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(replacementImage: CGImage) {
        self.replacementImage = replacementImage
    }

    func render(
        url: URL,
        rotation: Int,
        preset: Preset,
        maxDimension: Int
    ) async throws -> CGImage {
        _ = url
        _ = rotation
        _ = maxDimension
        guard preset.name == "Old" else { return replacementImage }

        oldRenderStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
        oldRenderWasCancelled = Task.isCancelled
        return replacementImage
    }

    func waitUntilOldRenderStarted() async {
        guard !oldRenderStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseOldRender() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ControlledImportOperation {
    private var continuation: CheckedContinuation<PhotoImportResult, Never>?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func result() async -> PhotoImportResult {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(_ result: PhotoImportResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
