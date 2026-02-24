# Project Structure

> **Updated:** 2026-02-24

## Directory Layout

```
framer/
├── Package.swift                  # SPM package definition
├── project.yml                    # XcodeGen project configuration
├── Framer.xcodeproj/              # Generated Xcode project
│   └── project.pbxproj
├── Sources/
│   ├── FramerCore/                # Core image processing library
│   │   ├── Models/
│   │   │   ├── ProcessingConfig.swift   # Config, BorderStyle, FontStyle, etc.
│   │   │   ├── ExifData.swift           # EXIF metadata model + template resolution
│   │   │   ├── Preset.swift             # Preset model
│   │   │   └── CompositionLayer.swift   # Layer system (canvas, border, caption, overlay, etc.)
│   │   ├── Processing/
│   │   │   ├── FrameProcessor.swift     # Main processing pipeline
│   │   │   ├── BorderRenderer.swift     # Border/padding rendering
│   │   │   ├── CaptionRenderer.swift    # Text caption rendering via CoreText
│   │   │   ├── ColorExtractor.swift     # Dominant color extraction
│   │   │   ├── MetadataWriter.swift     # EXIF preservation + IPTC keywords
│   │   │   ├── EXIFReader.swift         # EXIF extraction via ImageIO
│   │   │   └── TextureFrameProvider.swift # Texture overlay blending
│   │   └── Presets/
│   │       ├── PresetStore.swift        # Preset CRUD + defaults
│   │       └── YAMLConfig.swift         # YAML config schema
│   ├── FramerCLI/
│   │   ├── Framer.swift                 # CLI entry point (ArgumentParser)
│   │   └── Commands/
│   │       ├── ProcessCommand.swift     # Main process command
│   │       ├── PresetsCommand.swift     # Preset management
│   │       └── FontsCommand.swift       # Font listing
│   └── FramerApp/
│       ├── App/
│       │   └── AppState.swift           # @MainActor app state
│       ├── Editor/
│       │   ├── PreviewViewModel.swift   # Preview generation
│       │   └── SettingsPanel.swift      # Processing settings UI
│       └── Library/
│           └── PhotoThumbnailView.swift # Photo library thumbnails
├── Tests/
│   └── FramerCoreTests/
│       ├── Resources/                   # Test fixtures (sample images)
│       ├── BorderRendererTests.swift
│       ├── CaptionRendererTests.swift
│       ├── ColorExtractorTests.swift
│       ├── CompositionLayerTests.swift
│       ├── EXIFReaderTests.swift
│       ├── FrameProcessorTests.swift
│       ├── MetadataWriterTests.swift
│       ├── PlaceholderTests.swift
│       ├── PresetStoreTests.swift
│       └── ProcessingConfigTests.swift
├── assets/
│   └── textures/                  # 168 overlay textures (Git LFS)
├── docs/
│   ├── overlay-blending.md        # Overlay blending documentation
│   └── plans/                     # Design/planning documents
├── .gitattributes                 # LFS tracking rules
├── .gitignore
├── CLAUDE.md                      # AI assistant entry point
├── CHANGELOG.md                   # Version history
├── README.md                      # Project documentation
└── LICENSE                        # MIT License
```

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `Sources/FramerCore/` | Image processing library (models, processing, presets) |
| `Sources/FramerCLI/` | Command-line interface |
| `Sources/FramerApp/` | SwiftUI macOS application |
| `Tests/FramerCoreTests/` | Unit tests (102 tests) |
| `assets/textures/` | Overlay texture images (Git LFS) |
| `docs/` | Design docs and plans |

## File Types

| Extension | Purpose | Location |
|-----------|---------|----------|
| `*.swift` | Swift source files | `Sources/`, `Tests/` |
| `*.yml` | XcodeGen project config | Root |
| `*.jpg`, `*.tif` | Texture overlays | `assets/textures/` |
| `*.yaml` | Preset configurations | User `~/.config/framer/presets/` |
| `*.md` | Documentation | Root, `docs/` |

## Important Files

| File | Purpose |
|------|---------|
| `Package.swift` | SPM package definition (targets, dependencies) |
| `project.yml` | XcodeGen config (app target, resources) |
| `Sources/FramerCore/Processing/FrameProcessor.swift` | Main processing pipeline |
| `Sources/FramerCore/Models/CompositionLayer.swift` | Layer-based composition system |
| `Sources/FramerCore/Models/ProcessingConfig.swift` | All configuration types |

## Code Organization

The project uses a **multi-target Swift Package** architecture:

- **FramerCore**: Pure processing library with no UI dependencies. Contains all image processing logic, configuration models, and preset management.

- **FramerCLI**: Thin CLI wrapper using Swift Argument Parser. Translates CLI flags to `ProcessingConfig` and delegates to `FrameProcessor`.

- **FramerApp**: SwiftUI macOS app providing a visual editor. Uses `FrameProcessor` for preview and export.

- **FramerCoreTests**: Comprehensive test suite covering all core functionality (102 tests across 10 test classes).
