# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-24

Complete rewrite from Go CLI to Swift macOS app + CLI.

### Added

#### Swift Rewrite
- **FramerCore library**: Standalone image processing library using CoreGraphics/CoreImage
- **FramerCLI**: Command-line interface using Swift Argument Parser
- **FramerApp**: SwiftUI macOS application with photo library integration and live preview
- **102 unit tests** across 10 test classes

#### Layer-Based Composition System
- **Canvas Layer**: Set physical canvas dimensions (width/height)
- **Border Layer**: Configurable thickness, color, padding, and fill modes (solid, dominant, gradient)
- **Orientation Layer**: Force landscape or portrait via 90-degree rotation
- **Caption Layer**: EXIF-based captions with template tokens and positioning
- **Overlay Layer**: Texture overlays with blend modes and opacity control
- **Resize Layer**: Output dimension constraints

#### Texture Overlay System
- **168 bundled textures**: Dirt, film dust, light leaks, wet plate, and frame textures
- **Blend modes**: Screen, multiply, overlay, softLight per texture kind
- **Git LFS**: Large texture files tracked via Git LFS

#### Font Styling
- **Bold/Italic support**: FontStyle OptionSet with `--font-bold`/`--font-italic` CLI flags
- **System fonts**: Uses macOS system fonts via CoreText

#### Border Styles
- **Solid**: Clean colored border with customizable padding
- **Instagram**: Fixed 4:5 ratio frame
- **Print**: Physical print format (10x15cm default) with custom dimensions and DPI

#### Processing Features
- **EXIF preservation**: Metadata carried through to output via MetadataWriter
- **IPTC keywords**: "framer" keyword added to processed images
- **Color extraction**: Dominant color and gradient generation for dynamic backgrounds
- **Concurrent processing**: Batch processing with configurable worker count

#### Preset System
- **YAML presets**: Save/load from `~/.config/framer/presets/`
- **Built-in presets**: Vintage, Instagram, Minimal, Print 10x15
- **JSON preset support**: In-app preset management

### Removed
- Go source code and all Go dependencies
- Legacy iOS companion app (Framer-iOS/)
- Embedded font binaries (fonts.go, fonts_data/)
- Go CI/CD workflows
- Cross-platform support (now macOS-only)

### Changed
- Architecture: single-file Go to multi-target Swift Package
- Image processing: Go imaging library to CoreGraphics/CoreImage
- Font rendering: FreeType to CoreText
- EXIF reading: goexif to ImageIO
- Configuration: flag package to Swift Argument Parser
- Project build: `go build` to `swift build` / `xcodegen generate`

---

## [1.0.0] - 2025

Original Go CLI implementation.

### Core Features
- Two border styles: Solid and Instagram (4:5 ratio)
- EXIF date extraction for automatic captions
- Caption templates with `{{field}}` placeholders
- YAML configuration and preset system
- Batch processing with concurrent workers and progress bar
- Multiple embedded TrueType fonts
- PNG and JPEG output formats
- Post-processing hook for external tools (JPEGmini Pro, jpegoptim)
- Cross-platform builds (macOS, Linux, Windows)
- Homebrew installation support

---

**Note**: All development was done using [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) as an experiment in AI-assisted development.
