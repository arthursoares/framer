// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "framer",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FramerCore", targets: ["FramerCore"]),
        .executable(name: "framer", targets: ["FramerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "FramerCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            // SwiftPM compiles individual .metal files into a metallib when
            // declared per-file as `.process` resources. The directory form
            // (.process("Effects/Metal")) treats them as opaque files to copy
            // — a known SPM gotcha. ShaderCommon.h ships as the include
            // header. _EffectTemplate.metal is excluded (scaffold with TODOs).
            exclude: [
                "Effects/Metal/_EffectTemplate.metal",
            ],
            resources: [
                .process("Effects/Metal/ShaderCommon.h"),
                .process("Effects/Metal/FullscreenVertex.metal"),
                .process("Effects/Metal/TextCell.metal"),
                .process("Effects/Metal/ColorGrade.metal"),
                .process("Effects/Metal/DistantPast.metal"),
                .process("Effects/Metal/CRT.metal"),
                .process("Effects/Metal/Halftone.metal"),
                .process("Effects/Metal/Kuwahara.metal"),
                .process("Effects/Metal/PixelSort.metal"),
                .process("Effects/Metal/Dither.metal"),
                .process("Effects/Metal/PrintSampling.metal"),
                .process("Effects/Metal/EdgeField.metal"),
                .process("Effects/Metal/Glitch.metal"),
                // ASCII LUT atlases — duplicated here from assets/textures/ so
                // the CLI / test runner / any FramerCore consumer can reach
                // them via Bundle.module without depending on the macOS app
                // bundle's folder reference (which only exists at app scope).
                .copy("Resources/textures"),
            ]
        ),
        .executableTarget(
            name: "FramerCLI",
            dependencies: [
                "FramerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "FramerCoreTests",
            dependencies: ["FramerCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "FramerCLITests",
            dependencies: ["FramerCLI", "FramerCore"]
        ),
        .testTarget(
            name: "FramerCLIE2ETests",
            dependencies: ["FramerCore"],
            resources: [.copy("../E2EFixtures")]
        ),
    ]
)
