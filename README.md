# Framer

A Swift macOS app and CLI tool for adding professional borders, captions, and texture overlays to photos. Designed for photographers to post-process images exported from Adobe Lightroom with vintage-style borders and EXIF metadata captions.

> **Note**: This project was created using [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) as an experiment in AI-assisted development.

## Inspiration

The border format is inspired by an old box of photos from my grandfather, featuring white borders with machine-printed dates.

## Features

### macOS App (SwiftUI)
- **Photo Library Integration**: Browse and select photos from your library
- **Live Preview**: Real-time preview of border, caption, and overlay settings
- **Preset Management**: Create, edit, and apply processing presets
- **Batch Export**: Process multiple images with drag-and-drop

### CLI Tool
- **Batch Processing**: Process single images or entire directories
- **Concurrent Workers**: Multi-core processing with configurable worker count
- **Shell Scripting**: Integrate into automated workflows

### Border Styles
- **Solid**: Clean, colored border with customizable padding
- **Instagram**: Fixed 4:5 ratio frame optimized for Instagram posts

### Layer-Based Composition
- **Canvas Layer**: Set physical canvas size with width/height
- **Border Layer**: Configurable thickness, color, and padding
- **Orientation Layer**: Force landscape or portrait via 90-degree rotation
- **Caption Layer**: EXIF-based captions with template tokens
- **Overlay Layer**: Texture overlays (dirt, film dust, light leaks, wet plate) with blend modes
- **Dither Layer**: 9 dithering algorithms with 3 color modes, pre-processing controls

### Dithering
- **Algorithms**: Bayer (ordered), Floyd-Steinberg, Atkinson, Blue Noise, Artistic Drip (Parker), Halftone (clustered dot), Stucki, White Noise, Riemersma (Hilbert curve)
- **Color Modes**: Black & white, two-tone (custom fg/bg colors), full color (per-channel quantization)
- **Controls**: Threshold (brightness), pixel scale (1–8× chunky retro), Bayer level (1–4), pre-sharpen, contrast
- **Quality**: Serpentine scanning on all error diffusion, sRGB↔linear gamma conversion

### Caption Templates
- **EXIF Date Extraction**: Automatically displays date as "MON 'YY" format
- **Custom Templates**: Use `{{field}}` placeholders for dynamic captions
  - `{{camera}}`, `{{lens}}`, `{{iso}}`, `{{aperture}}`, `{{shutter}}`, `{{focal}}`
  - `{{year}}`, `{{year2}}`, `{{month}}`, `{{mon}}`, `{{day}}`, `{{date}}`
  - `{{width}}`, `{{height}}` (canvas dimensions)
- **Font Styling**: Bold and italic font style options

### Presets
- **Built-in Presets**: Vintage, Instagram, Minimal
- **Custom Presets**: Save and load YAML-based presets from `~/.config/framer/presets/`

## Architecture

Swift Package with three targets:

| Target | Description |
|--------|-------------|
| **FramerCore** | Image processing library — borders, captions, overlays, presets |
| **FramerCLI** | Command-line interface using Swift Argument Parser |
| **FramerApp** | SwiftUI macOS application |

Dependencies:
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- [Yams](https://github.com/jpsim/Yams) — YAML preset/config parsing

## Installation

### From Source

Requires Swift 5.10+ and macOS 14+.

```bash
# Clone repository
git clone https://github.com/arthursoares/framer.git
cd framer

# Build CLI
swift build

# Run CLI
swift run framer -i photo.jpg -o output/

# Run tests
swift test
```

### macOS App

```bash
# Generate Xcode project (requires xcodegen)
xcodegen generate

# Open and build in Xcode
open Framer.xcodeproj
```

## CLI Usage

```bash
# Process a single image
framer -i photo.jpg -o output/

# Process a folder
framer -i photos/ -o output/

# Use a preset
framer -i photo.jpg -o output/ --preset vintage

# Custom caption template
framer -i photo.jpg -o output/ --caption-template "{{camera}} {{aperture}} {{shutter}}"

# Bold italic caption
framer -i photo.jpg -o output/ --font-bold --font-italic

# Instagram format
framer -i photo.jpg -o output/ -s instagram

# Process with 8 workers
framer -i photos/ -o output/ --workers 8
```

## Development

```bash
# Build
swift build

# Test
swift test

# Regenerate Xcode project
xcodegen generate
```

## LUT Benchmark

The CLI includes a focused LUT benchmark command for comparing the CPU reference path against the real automatic render path used by the app and CLI.

```bash
swift run framer benchmark lut \
  --input docs/sample.jpg \
  --lut assets/luts/ANDP-KodakPortra800-32bit.CUBE \
  --preview-base 1200 \
  --iterations 10 \
  --warmup 2
```

Measured on `2026-04-01` with `docs/sample.jpg` (`3000x1987`) and `assets/luts/ANDP-KodakPortra800-32bit.CUBE`:

- Preview mode (`--preview-base 1200`)
  - CPU: `233.04 ms`
  - Auto(Metal): `32.44 ms`
  - Speedup: `7.18x`
- Full export mode (no `--preview-base`)
  - CPU: `1964.00 ms`
  - Auto(Metal): `78.16 ms`
  - Speedup: `25.13x`

The automatic path uses Metal when available and falls back to CPU otherwise.

Next LUT performance step:
- Preview still blocks on GPU readback and `CGImage` reconstruction after the Metal pass.
- The next high-impact optimization is to present preview output closer to a Metal texture so the preview path no longer has to read pixels back to CPU on every LUT change.
- That work is intentionally deferred because it touches preview/UI architecture, not just LUT internals.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
- Inspired by vintage photo printing techniques
- Texture overlays from analog film scanning artifacts
