import XCTest
@testable import FramerCLI
@testable import FramerCore

final class ProcessCommandTests: XCTestCase {
    func test_validatedWorkers_rejectsZero() {
        XCTAssertThrowsError(try ProcessCommand.validatedWorkers(0))
    }

    func test_validatedWorkers_rejectsNegative() {
        XCTAssertThrowsError(try ProcessCommand.validatedWorkers(-2))
    }

    func test_validatedWorkers_acceptsPositive() throws {
        XCTAssertEqual(try ProcessCommand.validatedWorkers(3), 3)
    }

    func test_applyOutputFormatOverride_jpegForcesJPEGEvenWhenConfigIsPNG() throws {
        var cfg = ProcessingConfig.default
        cfg.outputFormat = .png

        try ProcessCommand.applyOutputFormatOverride("jpeg", quality: nil, config: &cfg)

        switch cfg.outputFormat {
        case .jpeg:
            XCTAssertTrue(true)
        case .png:
            XCTFail("Expected jpeg output format")
        }
    }

    func test_applyOutputFormatOverride_invalidValueThrows() {
        var cfg = ProcessingConfig.default

        XCTAssertThrowsError(try ProcessCommand.applyOutputFormatOverride("gif", quality: nil, config: &cfg))
    }

    func test_applyPaddingOverrides_usesCaptionPaddingWhenOuterNotProvided() {
        var cfg = ProcessingConfig.default
        cfg.outerPadding = 0

        ProcessCommand.applyPaddingOverrides(outerPadding: nil, captionPadding: 24, config: &cfg)

        XCTAssertEqual(cfg.outerPadding, 24)
    }

    func test_applyPaddingOverrides_outerPaddingWinsOverCaptionPadding() {
        var cfg = ProcessingConfig.default
        cfg.outerPadding = 0

        ProcessCommand.applyPaddingOverrides(outerPadding: 30, captionPadding: 24, config: &cfg)

        XCTAssertEqual(cfg.outerPadding, 30)
    }

    func test_shellQuote_escapesSingleQuotesAndDollarSigns() {
        let raw = "/tmp/a'b $HOME.jpg"

        let quoted = ProcessCommand.shellQuote(raw)

        XCTAssertEqual(quoted, "'/tmp/a'\"'\"'b $HOME.jpg'")
    }
}
