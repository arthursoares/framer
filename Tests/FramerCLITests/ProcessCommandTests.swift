import XCTest
@testable import FramerCLI
@testable import FramerCore

final class ProcessCommandTests: XCTestCase {
    func test_applyCLIOverrides_preservesEmptyExplicitStack() throws {
        var config = ProcessingConfig.default
        config.layers = []

        try command().applyCLIOverrides(to: &config)

        XCTAssertEqual(config.layers, [])
    }

    func test_applyCLIOverrides_preservesExplicitLayerStackWithoutCaptionFlags() throws {
        let firstID = UUID()
        let secondID = UUID()
        let originalLayers: [CompositionLayer] = [
            .caption(CaptionLayerParams(
                id: firstID,
                enabled: false,
                mode: .custom("first"),
                fontName: "Avenir",
                fontSize: .fixed(27),
                fontStyle: [.italic],
                fontColorMode: .dominant(saturationShift: 0.2, lightnessShift: -0.1),
                alignment: .left,
                position: .top,
                offsetX: 9,
                offsetY: -4
            )),
            .border(BorderLayerParams(thickness: .pixels(7), color: try CodableColor(hex: "#123456"))),
            .caption(CaptionLayerParams(
                id: secondID,
                mode: .template("{{camera}}"),
                fontName: "Menlo",
                fontSize: .auto,
                fontStyle: [.bold],
                fontColorMode: .dominantInverted(saturationShift: -0.3, lightnessShift: 0.4),
                alignment: .right,
                position: .bottom,
                offsetX: -2,
                offsetY: 11
            ))
        ]
        var config = ProcessingConfig.default
        config.layers = originalLayers
        let command = try command()

        try command.applyCLIOverrides(to: &config)

        XCTAssertEqual(config.layers, originalLayers)
    }

    func test_applyCLIOverrides_fontOnlyChangesSuppliedFieldsOnExistingCaptions() throws {
        let firstID = UUID()
        let secondID = UUID()
        let padding = CompositionLayer.padding(PaddingLayerParams(thickness: 12))
        var config = ProcessingConfig.default
        config.layers = [
            .caption(CaptionLayerParams(
                id: firstID,
                enabled: false,
                mode: .custom("first"),
                fontName: "Avenir",
                fontSize: .fixed(18),
                fontStyle: [.italic],
                fontColorMode: .dominant(),
                alignment: .left,
                position: .top,
                offsetX: 3,
                offsetY: 4
            )),
            padding,
            .caption(CaptionLayerParams(
                id: secondID,
                mode: .template("{{lens}}"),
                fontName: "Menlo",
                fontSize: .auto,
                fontStyle: [],
                fontColor: try CodableColor(hex: "#ABCDEF"),
                alignment: .right,
                offsetX: -5,
                offsetY: 6
            ))
        ]
        let command = try command("--font-name", "Courier", "--font-size", "31", "--font-bold")

        try command.applyCLIOverrides(to: &config)

        let layers = try XCTUnwrap(config.layers)
        XCTAssertEqual(layers.map(\.id), [firstID, padding.id, secondID])
        XCTAssertEqual(layers[1], padding)
        guard case .caption(let first) = layers[0], case .caption(let second) = layers[2] else {
            return XCTFail("Expected captions to remain in place")
        }
        XCTAssertEqual(first.mode, .custom("first"))
        XCTAssertFalse(first.enabled)
        XCTAssertEqual(first.fontName, "Courier")
        XCTAssertEqual(first.fontSize, .fixed(31))
        XCTAssertEqual(first.fontStyle, [.bold, .italic])
        XCTAssertEqual(first.fontColorMode, .dominant())
        XCTAssertEqual(first.alignment, .left)
        XCTAssertEqual(first.position, .top)
        XCTAssertEqual(first.offsetX, 3)
        XCTAssertEqual(first.offsetY, 4)
        XCTAssertEqual(second.mode, .template("{{lens}}"))
        XCTAssertEqual(second.fontName, "Courier")
        XCTAssertEqual(second.fontSize, .fixed(31))
        XCTAssertEqual(second.fontStyle, [.bold])
        XCTAssertEqual(second.fontColor.hex, "#ABCDEF")
        XCTAssertEqual(second.alignment, .right)
        XCTAssertEqual(second.offsetX, -5)
        XCTAssertEqual(second.offsetY, 6)
    }

    func test_applyCLIOverrides_captionTextReplacesConfiguredCaptionsOnceAtEnd() throws {
        var config = ProcessingConfig.default
        let border = CompositionLayer.border(BorderLayerParams(thickness: .pixels(8)))
        let padding = CompositionLayer.padding(PaddingLayerParams(thickness: 19))
        config.layers = [
            .caption(CaptionLayerParams(mode: .custom("old one"), alignment: .left)),
            border,
            .caption(CaptionLayerParams(mode: .template("old two"), position: .top)),
            padding
        ]
        let command = try command(
            "--caption", "replacement",
            "--caption-template", "{{replacement}}",
            "--font-italic"
        )

        try command.applyCLIOverrides(to: &config)

        let layers = try XCTUnwrap(config.layers)
        XCTAssertEqual(Array(layers.dropLast()), [border, padding])
        guard case .caption(let caption) = layers.last else {
            return XCTFail("Expected one replacement caption at the end")
        }
        XCTAssertEqual(caption.mode, .template("{{replacement}}"))
        XCTAssertEqual(caption.fontName, "Courier New")
        XCTAssertEqual(caption.fontStyle, [.italic])
        XCTAssertEqual(caption.alignment, .center)
        XCTAssertEqual(caption.position, .bottom)
    }

    func test_applyCLIOverrides_customCaptionUsesCustomMode() throws {
        var config = ProcessingConfig.default
        config.layers = []
        let command = try command("--caption", "A literal caption")

        try command.applyCLIOverrides(to: &config)

        let layers = try XCTUnwrap(config.layers)
        guard case .caption(let caption) = layers.first else {
            return XCTFail("Expected a custom caption")
        }
        XCTAssertEqual(caption.mode, .custom("A literal caption"))
    }

    func test_applyCLIOverrides_noCaptionRemovesAllCaptions() throws {
        let border = CompositionLayer.border(BorderLayerParams())
        var config = ProcessingConfig.default
        config.layers = [
            .caption(CaptionLayerParams(mode: .custom("keep?"))),
            border,
            .caption(CaptionLayerParams(mode: .custom("also?")))
        ]
        let command = try command("--no-caption", "--font-name", "Ignored")

        try command.applyCLIOverrides(to: &config)

        XCTAssertEqual(config.layers, [border])
    }

    func test_applyCLIOverrides_appendsDefaultCaptionForExplicitFontFlagWhenMissing() throws {
        let border = CompositionLayer.border(BorderLayerParams())
        var config = ProcessingConfig.default
        config.layers = [border]
        let command = try command("--font-color", "#112233")

        try command.applyCLIOverrides(to: &config)

        let layers = try XCTUnwrap(config.layers)
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers[0], border)
        guard case .caption(let caption) = layers[1] else {
            return XCTFail("Expected a default caption appended")
        }
        XCTAssertEqual(caption.mode, .template(" - {{mon}} '{{year2}} -"))
        XCTAssertEqual(caption.fontName, "Courier New")
        XCTAssertEqual(caption.fontSize, .auto)
        XCTAssertEqual(caption.fontColor.hex, "#112233")
    }

    func test_applyCLIOverrides_materializesLegacyDefaultCaptionWhenLayersAreNil() throws {
        var config = ProcessingConfig.default
        XCTAssertNil(config.layers)
        let command = try command()

        try command.applyCLIOverrides(to: &config)

        let layers = try XCTUnwrap(config.layers)
        XCTAssertEqual(layers.count, 3)
        guard case .border(let border) = layers[0],
              case .padding(let padding) = layers[1],
              case .caption(let caption) = layers[2] else {
            return XCTFail("Expected the legacy border, padding, and caption stack")
        }
        XCTAssertEqual(border.thickness, .pixels(20))
        XCTAssertEqual(border.color, .white)
        XCTAssertEqual(padding.thickness, 150)
        XCTAssertEqual(caption.mode, .template(" - {{mon}} '{{year2}} -"))
        XCTAssertEqual(caption.fontName, "Courier New")
        XCTAssertEqual(caption.fontSize, .auto)
    }

    func test_applyCLIOverrides_insertsAspectRatioBeforePreservedExplicitStack() throws {
        let caption = CompositionLayer.caption(CaptionLayerParams(id: UUID(), mode: .custom("kept")))
        let border = CompositionLayer.border(BorderLayerParams())
        var config = ProcessingConfig.default
        config.layers = [caption, border]
        let command = try command("--aspect-ratio", "4:5")

        try command.applyCLIOverrides(to: &config)

        let layers = try XCTUnwrap(config.layers)
        guard case .aspectRatio(let ratio) = layers[0] else {
            return XCTFail("Expected aspect ratio first")
        }
        XCTAssertEqual(ratio.ratioWidth, 4)
        XCTAssertEqual(ratio.ratioHeight, 5)
        XCTAssertEqual(Array(layers.dropFirst()), [caption, border])
    }

    func test_validatedBatchJobs_rejectsCaseInsensitiveDestinationCollision() throws {
        let inputDirectory = URL(fileURLWithPath: "/tmp/input")
        let outputDirectory = URL(fileURLWithPath: "/tmp/output")
        let inputs = [
            inputDirectory.appendingPathComponent("Photo.jpg"),
            inputDirectory.appendingPathComponent("photo.png")
        ]

        XCTAssertThrowsError(
            try ProcessCommand.validatedBatchJobs(
                images: inputs,
                outputDirectory: outputDirectory,
                config: .default,
                caseSensitiveFileSystem: false
            )
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("Photo.jpg"))
            XCTAssertTrue(message.contains("photo.png"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("same output"))
        }
    }

    func test_validatedBatchJobs_preservesDistinctNamesOnCaseSensitiveVolume() throws {
        let inputs = [URL(fileURLWithPath: "/input/Photo.jpg"), URL(fileURLWithPath: "/input/photo.png")]
        let outputDirectory = URL(fileURLWithPath: "/output")
        var config = ProcessingConfig.default
        config.outputFormat = .png

        let jobs = try ProcessCommand.validatedBatchJobs(
            images: inputs,
            outputDirectory: outputDirectory,
            config: config,
            caseSensitiveFileSystem: true
        )

        XCTAssertEqual(jobs.map(\.input), inputs)
        XCTAssertEqual(jobs.map { $0.output.lastPathComponent }, ["Photo_solid.png", "photo_solid.png"])
    }

    func test_validatedBatchJobs_rejectsCaseCollisionsWhenVolumeCapabilityIsUnknown() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer-volume-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let output = parent.appendingPathComponent("not-created-yet", isDirectory: true)
        let inputs = [URL(fileURLWithPath: "/input/Photo.jpg"), URL(fileURLWithPath: "/input/photo.png")]
        let unavailableReaders: [(URL) throws -> Bool?] = [
            { _ in nil },
            { _ in throw CocoaError(.fileReadNoPermission) },
        ]

        for readCapability in unavailableReaders {
            let caseSensitive = ProcessCommand.isCaseSensitiveFileSystem(
                at: output,
                fileManager: .default,
                readVolumeCapability: { existingURL in
                    XCTAssertEqual(existingURL.standardizedFileURL.path, parent.standardizedFileURL.path)
                    return try readCapability(existingURL)
                }
            )
            XCTAssertThrowsError(try ProcessCommand.validatedBatchJobs(
                images: inputs,
                outputDirectory: output,
                config: .default,
                caseSensitiveFileSystem: caseSensitive
            ))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func test_batchProcess_rejectsCollisionsBeforeCreatingOutputDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer-cli-collision-\(UUID().uuidString)", isDirectory: true)
        let inputDirectory = root.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: inputDirectory.appendingPathComponent("duplicate.jpg"))
        try Data().write(to: inputDirectory.appendingPathComponent("duplicate.png"))
        let command = try command()

        do {
            try await command.batchProcess(
                directory: inputDirectory,
                outputDir: outputDirectory.path,
                config: .default,
                workers: 2
            )
            XCTFail("Expected a collision validation error")
        } catch {
            let message = String(describing: error)
            XCTAssertTrue(message.contains("duplicate.jpg"))
            XCTAssertTrue(message.contains("duplicate.png"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

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

    private func command(_ arguments: String...) throws -> ProcessCommand {
        try ProcessCommand.parse(["--input", "/tmp/input.jpg"] + arguments)
    }
}
