# Tech Stack

> **Updated:** 2026-02-24

## Core Technologies

| Layer | Technology | Version |
|-------|------------|---------|
| Language | Swift | 5.10 |
| Platforms | macOS | 14+ |
| Package Manager | Swift Package Manager | - |
| Project Generator | XcodeGen | - |
| Testing | XCTest | built-in |

## Build & Development

| Tool | Purpose |
|------|---------|
| `swift build` | Build all targets |
| `swift test` | Run test suite |
| `swift run framer` | Run CLI |
| `xcodegen generate` | Regenerate Xcode project |

## Targets

| Target | Type | Description |
|--------|------|-------------|
| FramerCore | Library | Image processing, presets, models |
| FramerCLI | Executable | Command-line interface |
| FramerApp | App (via XcodeGen) | SwiftUI macOS application |
| FramerCoreTests | Test | Unit tests (102 tests) |

## Dependencies

### CLI

| Package | Version | Purpose |
|---------|---------|---------|
| `apple/swift-argument-parser` | 1.3.0+ | CLI argument parsing |

### Configuration

| Package | Version | Purpose |
|---------|---------|---------|
| `jpsim/Yams` | 5.1.0+ | YAML preset/config parsing |

## Apple Frameworks Used

| Framework | Purpose |
|-----------|---------|
| CoreGraphics | 2D drawing, image composition |
| CoreImage | Image filters, color extraction |
| CoreText | Font rendering, text layout |
| ImageIO | EXIF reading, image I/O |
| AppKit | NSImage, NSFont (macOS) |
| SwiftUI | macOS app UI |
| Photos | Photo library access (app) |

## Assets

| Asset | Location | Storage |
|-------|----------|---------|
| Texture overlays (168 files) | `assets/textures/` | Git LFS |

## Platform Support

| Platform | Architecture | Status |
|----------|--------------|--------|
| macOS | ARM64 (Apple Silicon) | Supported |
| macOS | x86_64 (Intel) | Supported |
