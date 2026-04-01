import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import FramerCore

struct BenchmarkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Run focused processing benchmarks",
        subcommands: [LUT.self]
    )

    struct LUT: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "lut",
            abstract: "Benchmark LUT rendering on CPU and Metal"
        )

        @Option(name: .shortAndLong, help: "Input image path") var input: String
        @Option(help: "Input .cube LUT path") var lut: String
        @Option(help: "LUT intensity (0...1)") var intensity: Double = 1.0
        @Option(help: "Preview base dimension. Omit to benchmark full export-sized rendering.") var previewBase: Int?
        @Option(help: "Measured iterations per backend") var iterations: Int = 10
        @Option(help: "Warmup iterations per backend") var warmup: Int = 2

        func run() throws {
            guard iterations > 0 else {
                throw ValidationError("--iterations must be greater than 0")
            }
            guard warmup >= 0 else {
                throw ValidationError("--warmup cannot be negative")
            }
            guard (0.0...1.0).contains(intensity) else {
                throw ValidationError("--intensity must be between 0 and 1")
            }
            if let previewBase, previewBase <= 0 {
                throw ValidationError("--preview-base must be greater than 0")
            }

            let imageURL = URL(fileURLWithPath: input)
            let lutURL = URL(fileURLWithPath: lut)
            let image = try loadImage(from: imageURL)
            let lut3D = try CubeFileParser.parse(from: lutURL)

            print("Benchmarking LUT render")
            print("  image: \(imageURL.path)")
            print("  lut: \(lutURL.path)")
            print("  mode: \(previewBase.map { "preview(base=\($0))" } ?? "export/full")")
            print("  size: \(image.width)x\(image.height)")
            print("  iterations: \(iterations)")
            print("  warmup: \(warmup)")
            print("  metal available: \(LUTMetalRenderer.isAvailable ? "yes" : "no")")

            let cpuStats = try measure(name: "CPU") {
                _ = try LUTRenderer.applyCPUReference(
                    to: image,
                    lut: lut3D,
                    intensity: intensity,
                    previewBaseDimension: previewBase
                )
            }
            print(statsLine(name: "CPU", stats: cpuStats))

            let activeBackendLabel = LUTMetalRenderer.isAvailable ? "Auto(Metal)" : "Auto(CPU fallback)"
            let autoStats = try measure(name: activeBackendLabel) {
                _ = try LUTRenderer.apply(
                    to: image,
                    lut: lut3D,
                    intensity: intensity,
                    previewBaseDimension: previewBase
                )
            }
            print(statsLine(name: activeBackendLabel, stats: autoStats))

            if LUTMetalRenderer.isAvailable {
                let speedup = cpuStats.meanMS / autoStats.meanMS
                print(String(format: "  speedup: %.2fx", speedup))
            }
        }

        private func loadImage(from url: URL) throws -> CGImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw FramerError.invalidImage(url)
            }
            return image
        }

        private func measure(name: String, block: () throws -> Void) throws -> BenchmarkStats {
            for _ in 0..<warmup {
                try block()
            }

            var samplesMS: [Double] = []
            samplesMS.reserveCapacity(iterations)

            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                try block()
                let end = DispatchTime.now().uptimeNanoseconds
                let elapsedMS = Double(end - start) / 1_000_000.0
                samplesMS.append(elapsedMS)
            }

            return BenchmarkStats(samplesMS: samplesMS)
        }

        private func statsLine(name: String, stats: BenchmarkStats) -> String {
            String(
                format: "  %@: mean %.2f ms | median %.2f ms | min %.2f ms | max %.2f ms",
                name,
                stats.meanMS,
                stats.medianMS,
                stats.minMS,
                stats.maxMS
            )
        }
    }
}

private struct BenchmarkStats {
    let meanMS: Double
    let medianMS: Double
    let minMS: Double
    let maxMS: Double

    init(samplesMS: [Double]) {
        let sorted = samplesMS.sorted()
        meanMS = sorted.reduce(0, +) / Double(sorted.count)
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            medianMS = (sorted[upper - 1] + sorted[upper]) / 2.0
        } else {
            medianMS = sorted[sorted.count / 2]
        }
        minMS = sorted.first ?? 0
        maxMS = sorted.last ?? 0
    }
}
