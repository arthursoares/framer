import ArgumentParser
import Foundation
import FramerCore

struct ProcessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Process one or more images"
    )

    @Option(name: .shortAndLong, help: "Input image or directory") var input: String
    @Option(name: .shortAndLong, help: "Output directory") var output: String?
    @Option(name: [.long, .customShort("f")], help: "Output file path (single file only)") var outputFile: String?
    @Option(help: "Border style: solid, instagram, print, or print10x15") var borderStyle: String?
    @Option(name: [.long, .customShort("t")], help: "Border thickness (e.g. 20 or 5%%)") var borderThickness: String?
    @Option(help: "Border color (hex, e.g. #FFFFFF)") var borderColor: String?
    @Option(help: "Padding in pixels") var padding: Int?
    @Option(help: "Caption text") var caption: String?
    @Option(help: "Caption template with {{field}} placeholders") var captionTemplate: String?
    @Flag(help: "Disable caption") var noCaption = false
    @Option(help: "Font name") var fontName: String?
    @Option(help: "Font size in pixels") var fontSize: Int?
    @Flag(help: "Use bold font style") var fontBold = false
    @Flag(help: "Use italic font style") var fontItalic = false
    @Option(help: "Font color (hex)") var fontColor: String?
    @Option(name: [.long, .customShort("q")], help: "JPEG quality (60-100)") var quality: Int?
    @Option(help: "Output format: jpeg or png") var outputFormat: String?
    @Option(help: "Config YAML file path") var config: String?
    @Option(help: "Preset name") var preset: String?
    @Option(name: [.long, .customShort("w")], help: "Number of workers") var workers: Int?
    @Option(help: "Post-process command ({file} = output path)") var postProcess: String?
    @Option(help: "Background color (hex, e.g. #FFFFFF)") var backgroundColor: String?
    @Option(help: "Outer padding in pixels (print style)") var outerPadding: Int?
    @Option(help: "Legacy alias for outer padding in print style") var captionPadding: Int?
    @Flag(help: "Do not preserve EXIF metadata") var noMetadata = false
    @Option(help: "Print width in mm (default 148)") var printWidth: Double?
    @Option(help: "Print height in mm (default 100)") var printHeight: Double?
    @Option(help: "Print DPI (default 300)") var printDpi: Int?
    @Option(help: "Crop to aspect ratio (e.g. 4:5, 1:1, 16:9)") var aspectRatio: String?

    mutating func run() async throws {
        // Initialize default presets if needed
        PresetStore().initializeDefaults()

        // Build config: CLI flags → config file → preset → .framer.yaml → defaults
        let configURL = config.map { URL(fileURLWithPath: $0) }
        var cfg = YAMLConfig.loadDefault(configPath: configURL, preset: preset)
        try applyCLIOverrides(to: &cfg)

        let inputURL = URL(fileURLWithPath: input)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: input, isDirectory: &isDir)

        guard output != nil || outputFile != nil else {
            throw ValidationError("Either --output or --output-file is required")
        }

        if isDir.boolValue {
            guard let outputDir = output else {
                throw ValidationError("--output is required for directory processing")
            }
            let workerCount = try Self.validatedWorkers(workers)
            try await batchProcess(directory: inputURL, outputDir: outputDir, config: cfg, workers: workerCount)
        } else {
            let outURL: URL
            if let f = outputFile {
                outURL = URL(fileURLWithPath: f)
            } else {
                let outDir = URL(fileURLWithPath: output!)
                try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                outURL = Self.outputName(for: inputURL, in: outDir, style: cfg.borderStyle, format: cfg.outputFormat)
            }
            let processor = FrameProcessor()
            try await processor.process(input: inputURL, output: outURL, config: cfg)
            Self.runPostProcess(cfg.postProcess, file: outURL)
            print("Done: \(outURL.path)")
        }
    }

    func applyCLIOverrides(to config: inout ProcessingConfig) throws {
        if let borderStyle {
            switch borderStyle {
            case "solid": config.borderStyle = .solid
            case "instagram": config.borderStyle = .instagram
            case "print10x15": config.borderStyle = .print(.print10x15)
            case "print":
                config.borderStyle = .print(PrintFormat(
                    widthMM: printWidth ?? 148,
                    heightMM: printHeight ?? 100,
                    dpi: printDpi ?? 300
                ))
            default: break
            }
        }

        // Apply print dimensions even without --border-style if already in print mode.
        if case .print(var format) = config.borderStyle {
            if let printWidth { format.widthMM = printWidth }
            if let printHeight { format.heightMM = printHeight }
            if let printDpi { format.dpi = printDpi }
            config.borderStyle = .print(format)
        }
        if let borderThickness { config.borderThickness = BorderSize(string: borderThickness) }
        if let borderColor, let color = try? CodableColor(hex: borderColor) { config.borderColor = color }
        if let padding { config.padding = padding }
        try Self.applyOutputFormatOverride(outputFormat, quality: quality, config: &config)
        if let postProcess { config.postProcess = postProcess }
        if let backgroundColor, let color = try? CodableColor(hex: backgroundColor) {
            config.backgroundColor = color
        }
        Self.applyPaddingOverrides(
            outerPadding: outerPadding,
            captionPadding: captionPadding,
            config: &config
        )
        if noMetadata { config.noMetadata = true }

        // A nil stack is the legacy CLI configuration. Materializing its
        // default layers retains the caption that the command has always added.
        if config.layers == nil {
            config.layers = CompositionLayer.defaultLayers()
        }

        // Insert aspect ratio crop at the beginning of the layer stack.
        if let aspectRatio {
            let parts = aspectRatio.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, parts[0] > 0, parts[1] > 0 {
                config.layers?.insert(
                    .aspectRatio(AspectRatioLayerParams(ratioWidth: parts[0], ratioHeight: parts[1])),
                    at: 0
                )
            }
        }

        if noCaption {
            config.layers?.removeAll { layer in
                if case .caption = layer { return true }
                return false
            }
            return
        }

        let replacementMode: CaptionMode?
        if let captionTemplate {
            replacementMode = .template(captionTemplate)
        } else if let caption {
            replacementMode = .custom(caption)
        } else {
            replacementMode = nil
        }

        let hasFontOverride = fontName != nil
            || fontSize != nil
            || fontBold
            || fontItalic
            || fontColor != nil

        if let replacementMode {
            config.layers?.removeAll { layer in
                if case .caption = layer { return true }
                return false
            }
            var params = CaptionLayerParams(mode: replacementMode)
            applyFontOverrides(to: &params)
            config.layers?.append(.caption(params))
        } else if hasFontOverride {
            var foundCaption = false
            config.layers = config.layers?.map { layer in
                guard case .caption(var params) = layer else { return layer }
                foundCaption = true
                applyFontOverrides(to: &params)
                return .caption(params)
            }
            if !foundCaption {
                var params = CaptionLayerParams()
                applyFontOverrides(to: &params)
                config.layers?.append(.caption(params))
            }
        }
    }

    private func applyFontOverrides(to params: inout CaptionLayerParams) {
        if let fontName { params.fontName = fontName }
        if let fontSize { params.fontSize = .fixed(fontSize) }
        if fontBold { params.fontStyle.insert(.bold) }
        if fontItalic { params.fontStyle.insert(.italic) }
        if let fontColor {
            params.fontColor = (try? CodableColor(hex: fontColor)) ?? .black
        }
    }

    func batchProcess(directory: URL, outputDir: String, config: ProcessingConfig, workers: Int) async throws {
        guard workers > 0 else {
            throw ValidationError("--workers must be at least 1")
        }

        let fm = FileManager.default
        let outDir = URL(fileURLWithPath: outputDir)
        let images = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["jpg","jpeg","png","tiff","tif","heic"].contains($0.pathExtension.lowercased()) }

        guard !images.isEmpty else {
            print("No images found in \(directory.path)")
            return
        }

        let jobs = try Self.validatedBatchJobs(
            images: images,
            outputDirectory: outDir,
            config: config,
            caseSensitiveFileSystem: Self.isCaseSensitiveFileSystem(at: outDir, fileManager: fm)
        )
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let total = jobs.count
        print("Processing \(total) image\(total == 1 ? "" : "s") with \(workers) worker\(workers == 1 ? "" : "s")...")

        let counter = Counter()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = jobs.makeIterator()

            // Seed initial workers
            for _ in 0..<min(workers, total) {
                if let job = pending.next() {
                    group.addTask {
                        try await Self.processBatchJob(job, config: config, counter: counter, total: total)
                    }
                }
            }

            // As each finishes, schedule next
            for try await _ in group {
                if let job = pending.next() {
                    group.addTask {
                        try await Self.processBatchJob(job, config: config, counter: counter, total: total)
                    }
                }
            }
        }

        print("Done: \(total) images processed to \(outDir.path)")
    }

    struct BatchJob: Sendable {
        let input: URL
        let output: URL
    }

    static func validatedBatchJobs(
        images: [URL],
        outputDirectory: URL,
        config: ProcessingConfig,
        caseSensitiveFileSystem: Bool
    ) throws -> [BatchJob] {
        var inputsByDestination: [String: URL] = [:]
        var jobs: [BatchJob] = []
        jobs.reserveCapacity(images.count)

        for input in images {
            let output = outputName(
                for: input,
                in: outputDirectory,
                style: config.borderStyle,
                format: config.outputFormat
            ).standardizedFileURL
            let path = caseSensitiveFileSystem
                ? output.path
                : output.path.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))

            if let conflictingInput = inputsByDestination[path] {
                throw ValidationError(
                    "Batch inputs '\(conflictingInput.lastPathComponent)' and '\(input.lastPathComponent)' "
                    + "resolve to the same output '\(output.lastPathComponent)'"
                )
            }
            inputsByDestination[path] = input
            jobs.append(BatchJob(input: input, output: output))
        }

        return jobs
    }

    static func isCaseSensitiveFileSystem(
        at url: URL,
        fileManager: FileManager,
        readVolumeCapability: (URL) throws -> Bool? = {
            try $0.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
                .volumeSupportsCaseSensitiveNames
        }
    ) -> Bool {
        var existingURL = url.standardizedFileURL
        while !fileManager.fileExists(atPath: existingURL.path) {
            let parent = existingURL.deletingLastPathComponent()
            guard parent.path != existingURL.path else { return false }
            existingURL = parent
        }
        // Unknown volume capabilities must not permit potentially colliding writes.
        return (try? readVolumeCapability(existingURL)) ?? false
    }

    private static func processBatchJob(
        _ job: BatchJob,
        config: ProcessingConfig,
        counter: Counter,
        total: Int
    ) async throws {
        let processor = FrameProcessor()
        try await processor.process(input: job.input, output: job.output, config: config)
        runPostProcess(config.postProcess, file: job.output)
        let completed = await counter.increment()
        print("[\(completed)/\(total)] \(job.input.lastPathComponent)")
    }

    static func validatedWorkers(_ workers: Int?) throws -> Int {
        let defaultWorkers = max(1, ProcessInfo.processInfo.processorCount)
        let resolved = workers ?? defaultWorkers
        guard resolved > 0 else {
            throw ValidationError("--workers must be at least 1")
        }
        return resolved
    }

    static func applyOutputFormatOverride(
        _ outputFormat: String?,
        quality: Int?,
        config: inout ProcessingConfig
    ) throws {
        if let quality {
            config.outputFormat = .jpeg(quality: quality)
        }

        guard let outputFormat else { return }
        switch outputFormat.lowercased() {
        case "png":
            config.outputFormat = .png
        case "jpeg", "jpg":
            let resolvedQuality: Int
            if let quality {
                resolvedQuality = quality
            } else if case .jpeg(let existingQuality) = config.outputFormat {
                resolvedQuality = existingQuality
            } else {
                resolvedQuality = 100
            }
            config.outputFormat = .jpeg(quality: resolvedQuality)
        default:
            throw ValidationError("--output-format must be 'jpeg' or 'png'")
        }
    }

    static func outputName(for input: URL, in dir: URL, style: BorderStyle, format: OutputFormat) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let ext: String
        switch format {
        case .png: ext = "png"
        case .jpeg: ext = "jpg"
        }
        let suffix: String
        switch style {
        case .solid: suffix = "_solid"
        case .instagram: suffix = "_instagram"
        case .print: suffix = "_print"
        }
        return dir.appendingPathComponent("\(stem)\(suffix).\(ext)")
    }

    static func applyPaddingOverrides(
        outerPadding: Int?,
        captionPadding: Int?,
        config: inout ProcessingConfig
    ) {
        if let outerPadding {
            config.outerPadding = outerPadding
        } else if let captionPadding {
            config.outerPadding = captionPadding
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    static func runPostProcess(_ command: String?, file: URL) {
        guard let cmd = command, !cmd.isEmpty else { return }
        let quoted = shellQuote(file.path)
        let resolved = cmd.replacingOccurrences(of: "{file}", with: quoted)
        let proc = Process()
        proc.launchPath = "/bin/sh"
        proc.arguments = ["-c", resolved]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                print("Warning: post-process exited with status \(proc.terminationStatus)")
            }
        } catch {
            print("Warning: post-process failed: \(error.localizedDescription)")
        }
    }
}

// Thread-safe counter for batch progress
private actor Counter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
