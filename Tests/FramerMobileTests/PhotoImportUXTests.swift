import XCTest
@testable import FramerMobile

@MainActor
final class PhotoImportUXTests: XCTestCase {
    func test_partialPhotoImportReportsSuccessfulAndSkippedCounts() async {
        let coordinator = PhotoImportCoordinator()
        let imported = PhotoItem(url: URL(fileURLWithPath: "/tmp/imported.jpg"))
        var feedback: String?

        let task = coordinator.start(
            operation: {
                PhotoImportResult(items: [imported], temporaryURLs: [], failureCount: 2)
            },
            onComplete: { _ in },
            clearSelection: {},
            onFeedback: { feedback = PhotoImportCoordinator.feedbackMessage(for: $0) }
        )
        await task.value

        XCTAssertEqual(feedback, "Added 1 photo. 2 photos couldn’t be loaded.")
    }

    func test_stalePhotoImportCannotPublishFailureFeedback() async {
        let first = ControlledPhotoImport()
        let second = ControlledPhotoImport()
        let coordinator = PhotoImportCoordinator()
        var feedbackMessages: [String] = []

        let firstTask = coordinator.start(
            operation: { await first.result() },
            onComplete: { _ in },
            clearSelection: {},
            onFeedback: { result in
                if let message = PhotoImportCoordinator.feedbackMessage(for: result) {
                    feedbackMessages.append(message)
                }
            }
        )
        await first.waitUntilStarted()

        let secondTask = coordinator.start(
            operation: { await second.result() },
            onComplete: { _ in },
            clearSelection: {},
            onFeedback: { result in
                if let message = PhotoImportCoordinator.feedbackMessage(for: result) {
                    feedbackMessages.append(message)
                }
            }
        )
        await second.waitUntilStarted()
        await first.finish(PhotoImportResult(items: [], temporaryURLs: [], failureCount: 3))
        await firstTask.value
        await second.finish(PhotoImportResult(items: [], temporaryURLs: [], failureCount: 1))
        await secondTask.value

        XCTAssertEqual(feedbackMessages, ["No photos were added. 1 photo couldn’t be loaded."])
    }

    func test_partialBatchSharePublishesFeedbackAfterTemporaryFileCleanup() throws {
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: temporaryFile)
        let feedback = BatchShareCompletion.partialFailureAlert(
            exportedCount: 1,
            totalCount: 2,
            failedCount: 1
        )
        var published: EditorOperationAlert?

        BatchShareCompletion.finish(
            temporaryFiles: [temporaryFile],
            feedback: feedback
        ) { alert in
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryFile.path))
            published = alert
        }

        XCTAssertEqual(published?.title, "Some Photos Weren’t Prepared")
        XCTAssertEqual(published?.message, "Prepared 1 of 2 photos. 1 couldn’t be processed.")
    }
}

private actor ControlledPhotoImport {
    private var continuation: CheckedContinuation<PhotoImportResult, Never>?
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func result() async -> PhotoImportResult {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ result: PhotoImportResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
