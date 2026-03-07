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
    @Option(help: "Caption padding in pixels (print style)") var captionPadding: Int?
    @Flag(help: "Do not preserve EXIF metadata") var noMetadata = false
    @Option(help: "Print width in mm (default 148)") var printWidth: Double?
    @Option(help: "Print height in mm (default 100)") var printHeight: Double?
    @Option(help: "Print DPI (default 300)") var printDpi: Int?

    mutating func run() async throws {
        // Initialize default presets if needed
        PresetStore().initializeDefaults()

        // Build config: CLI flags → config file → preset → .framer.yaml → defaults
        let configURL = config.map { URL(fileURLWithPath: $0) }
        var cfg = YAMLConfig.loadDefault(configPath: configURL, preset: preset)

        // Apply CLI overrides
        if let s = borderStyle {
            switch s {
            case "solid": cfg.borderStyle = .solid
            case "instagram": cfg.borderStyle = .instagram
            case "print10x15": cfg.borderStyle = .print(.print10x15)
            case "print":
                let format = PrintFormat(
                    widthMM: printWidth ?? 148,
                    heightMM: printHeight ?? 100,
                    dpi: printDpi ?? 300
                )
                cfg.borderStyle = .print(format)
            default: break
            }
        }
        // Apply print dimensions even without --border-style if already in print mode
        if case .print(var format) = cfg.borderStyle {
            if let w = printWidth { format.widthMM = w }
            if let h = printHeight { format.heightMM = h }
            if let d = printDpi { format.dpi = d }
            cfg.borderStyle = .print(format)
        }
        if let t = borderThickness { cfg.borderThickness = BorderSize(string: t) }
        if let c = borderColor, let color = try? CodableColor(hex: c) { cfg.borderColor = color }
        if let p = padding { cfg.padding = p }
        if let q = quality { cfg.outputFormat = .jpeg(quality: q) }
        if outputFormat == "png" { cfg.outputFormat = .png }
        if let pp = postProcess { cfg.postProcess = pp }
        if let bg = backgroundColor, let color = try? CodableColor(hex: bg) { cfg.backgroundColor = color }
        if let op = outerPadding { cfg.outerPadding = op }
        if noMetadata { cfg.noMetadata = true }

        // Build caption layer from CLI flags
        var captionMode: CaptionMode = .template(" - {{mon}} '{{year2}} -")
        if noCaption { captionMode = .none }
        else if let t = captionTemplate { captionMode = .template(t) }
        else if let c = caption { captionMode = .custom(c) }

        var captionFontStyle: FontStyle = []
        if fontBold { captionFontStyle.insert(.bold) }
        if fontItalic { captionFontStyle.insert(.italic) }

        let captionParams = CaptionLayerParams(
            mode: captionMode,
            fontName: fontName ?? "Courier New",
            fontSize: fontSize.map { .fixed($0) } ?? .auto,
            fontStyle: captionFontStyle,
            fontColor: (fontColor.flatMap { try? CodableColor(hex: $0) }) ?? (try! CodableColor(hex: "#000000"))
        )

        // Ensure layers exist and add caption
        if cfg.layers == nil {
            cfg.layers = CompositionLayer.defaultLayers()
        }
        // Remove any existing caption layers, then append
        cfg.layers?.removeAll { if case .caption = $0 { return true }; return false }
        if case .none = captionMode {} else {
            cfg.layers?.append(.caption(captionParams))
        }

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
            let workerCount = workers ?? ProcessInfo.processInfo.processorCount
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

    private func batchProcess(directory: URL, outputDir: String, config: ProcessingConfig, workers: Int) async throws {
        let fm = FileManager.default
        let outDir = URL(fileURLWithPath: outputDir)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let images = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["jpg","jpeg","png","tiff","tif","heic"].contains($0.pathExtension.lowercased()) }

        guard !images.isEmpty else {
            print("No images found in \(directory.path)")
            return
        }

        let total = images.count
        print("Processing \(total) image\(total == 1 ? "" : "s") with \(workers) worker\(workers == 1 ? "" : "s")...")

        let counter = Counter()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = images.makeIterator()

            // Seed initial workers
            for _ in 0..<min(workers, total) {
                if let url = pending.next() {
                    group.addTask {
                        let outURL = Self.outputName(for: url, in: outDir, style: config.borderStyle, format: config.outputFormat)
                        let processor = FrameProcessor()
                        try await processor.process(input: url, output: outURL, config: config)
                        Self.runPostProcess(config.postProcess, file: outURL)
                        let d = await counter.increment()
                        print("[\(d)/\(total)] \(url.lastPathComponent)")
                    }
                }
            }

            // As each finishes, schedule next
            for try await _ in group {
                if let url = pending.next() {
                    group.addTask {
                        let outURL = Self.outputName(for: url, in: outDir, style: config.borderStyle, format: config.outputFormat)
                        let processor = FrameProcessor()
                        try await processor.process(input: url, output: outURL, config: config)
                        Self.runPostProcess(config.postProcess, file: outURL)
                        let d = await counter.increment()
                        print("[\(d)/\(total)] \(url.lastPathComponent)")
                    }
                }
            }
        }

        print("Done: \(total) images processed to \(outDir.path)")
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

    static func runPostProcess(_ command: String?, file: URL) {
        guard let cmd = command, !cmd.isEmpty else { return }
        let quoted = file.path.contains(" ") ? "\"\(file.path)\"" : file.path
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
