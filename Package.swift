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
    ]
)
