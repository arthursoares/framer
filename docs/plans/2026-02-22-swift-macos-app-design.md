# Framer — Swift Rewrite Design

**Date:** 2026-02-22
**Status:** Approved
**Scope:** Full rewrite of Go CLI as Swift; new macOS desktop app with live preview

---

## Overview

Replace the existing Go CLI with a Swift implementation and add a native macOS desktop app. Both targets share a common `FramerCore` Swift library for image processing. The project stays in the same git repository.

---

## Architecture: SPM Multi-Target Monorepo

```
framer/
├── Package.swift
├── Sources/
│   ├── FramerCore/          ← pure Swift library, no UI
│   │   ├── Models/          ← ProcessingConfig, ExifData, Preset, etc.
│   │   ├── Processing/      ← FrameProcessor, BorderRenderer, CaptionRenderer
│   │   ├── EXIF/            ← EXIFReader (ImageIO framework)
│   │   └── Presets/         ← PresetStore (YAML, iCloud sync)
│   ├── FramerCLI/           ← thin CLI using swift-argument-parser
│   │   └── main.swift
│   └── FramerApp/           ← SwiftUI macOS app
│       ├── App/
│       ├── Library/
│       ├── Editor/
│       ├── Presets/
│       └── Queue/
├── Tests/
│   └── FramerCoreTests/
└── FramerApp.xcodeproj
```

---

## Section 1: Technology Choices

| Concern | Technology |
|---|---|
| Image processing | Core Image + vImage (hardware-accelerated, sandbox-safe) |
| EXIF reading | ImageIO framework (built-in, no third-party) |
| Fonts | System fonts via `CTFontCreateWithName` / `NSFont` — no bundled fonts |
| Config/Presets | `Codable` structs + `swift-yaml`, stored in `~/Library/Application Support/Framer/` |
| iCloud sync | iCloud Drive container for presets |
| CLI argument parsing | `swift-argument-parser` (Apple official) |
| Live preview | `@Observable` + `Task` + debounced background actor rendering |
| Minimum deployment | macOS 14 Sonoma |
| Distribution | App Store (sandboxed) + direct download (notarized) — both builds from same codebase |

---

## Section 2: FramerCore Library

Shared image processing engine used by both CLI and app.

### Core Model

```swift
struct ProcessingConfig: Codable {
    var borderStyle: BorderStyle       // .solid, .instagram
    var borderThickness: BorderSize    // .pixels(Int) or .percent(Double)
    var borderColor: Color
    var padding: Int
    var captionMode: CaptionMode       // .template(String), .custom(String), .none
    var fontName: String               // system font name
    var fontSize: FontSize             // .auto or .fixed(Int)
    var fontColor: Color
    var outputFormat: OutputFormat     // .jpeg(quality:), .png
    var instagramMaxSize: Int
    var postProcess: String?
}
```

### Processing Pipeline

Runs on a background actor for thread safety and UI responsiveness:

1. Load image via ImageIO → `CGImage`
2. Read EXIF via ImageIO → `ExifData`
3. Compute layout (border size, padding, canvas size)
4. Render border/background → new `CGImage`
5. Render caption text via CoreText
6. Encode to JPEG or PNG

### Two Execution Paths

- **Live preview path:** Same pipeline, output capped at 1200px max dimension, returns `NSImage` — no disk I/O, used by the macOS app
- **Full export path:** Full-resolution pipeline, writes to disk, optionally invokes post-process command

### Caption Templates

Same `{{field}}` placeholder system as the Go CLI:
- Date/time: `{{year}}`, `{{year2}}`, `{{month}}`, `{{mon}}`, `{{day}}`
- Camera: `{{camera}}`, `{{lens}}`
- Exposure: `{{iso}}`, `{{aperture}}`, `{{shutter}}`, `{{focal}}`

---

## Section 3: FramerCLI

Thin Swift executable replacing the Go CLI. Full feature parity, same flags.

### Commands

```
framer process -i photo.jpg -o output/      ← main command
framer process -i photos/ -o output/        ← batch
framer presets list                          ← list presets
framer presets apply <name> -i photo.jpg    ← apply preset
framer fonts                                 ← list system fonts (monospaced by default)
```

### Behaviors

- Reads `.framer.yaml` and `~/.config/framer/` with same priority order as current Go CLI
- Presets shared with macOS app via `~/Library/Application Support/Framer/presets/`
- Batch processing via `async/await` + `TaskGroup`, respecting `--workers` flag
- `--post-process` hook identical to current behavior
- Progress bar for batch operations

---

## Section 4: FramerApp (macOS SwiftUI App)

### Layout: Three-Panel

```
┌─────────────────────────────────────────────────────────────┐
│  Toolbar: [Open Folder] [Preset ▾] [Export Queue] [Settings]│
├──────────────┬──────────────────────────┬───────────────────┤
│   Library    │      Live Preview        │   Settings Panel  │
│   (sidebar)  │                          │                   │
│  📁 Folders  │   [photo with frame]     │  Border Style     │
│  photo1.jpg  │                          │  Thickness slider │
│  photo2.jpg  │   EXIF info line         │  Border Color     │
│  photo3.jpg  │   Caption preview        │  Padding slider   │
│              │                          │  Caption template │
│  [+ Add]     │                          │  Font / Size      │
│              │                          │  [Export Selected]│
│              │                          │  [Export All]     │
└──────────────┴──────────────────────────┴───────────────────┘
```

### Features

- **Library sidebar:** drag-and-drop folders/files, Finder-style browsing, multi-select
- **Live preview:** debounced background rendering (~200ms), downscaled preview image
- **EXIF inspector:** click EXIF line → popover with full metadata
- **Caption preview:** updates live as template changes
- **Preset manager:** toolbar dropdown with named presets + thumbnail previews; "Save Current as Preset..." creates new ones; full management panel (⌘2)
- **Export queue:** background processing sheet, runs while you keep editing (⌘3)
- **iCloud sync:** presets in iCloud Drive container, synced across Macs

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘1` | Library view |
| `⌘2` | Preset manager |
| `⌘3` | Export queue |
| `⌘,` | Preferences |
| `⌘E` | Export selected |
| `⌘⇧E` | Export all |

### Preferences

- Default output directory
- Default output format (JPEG quality / PNG)
- Install CLI Tools (symlinks app-bundled `framer` binary to `/usr/local/bin/`)
- iCloud sync toggle for presets

---

## Distribution

Both App Store and direct download builds from the same codebase:

- **App Store build:** Full sandbox, iCloud container enabled, no post-process shell execution (sandbox restriction — this feature disabled in App Store build via compile flag)
- **Direct download build:** Hardened runtime + notarization, post-process shell execution enabled

The CLI is distributed independently via Homebrew (same as today) and also bundled inside the `.app` for the "Install CLI Tools" flow.

---

## What Gets Dropped from the Go Version

- Embedded font files (replaced by system fonts)
- `--list-fonts` flag (replaced by `framer fonts` subcommand)
- Go dependency on `goexif`, `go-exiftool`, `imaging`, `freetype` (all replaced by Apple frameworks)
