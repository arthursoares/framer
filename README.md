# Framer

A Swift macOS app and CLI tool for adding professional borders, captions, texture overlays, dithering, LUTs, and GPU effects to photos. Designed for photographers to post-process images exported from Adobe Lightroom with vintage-style borders and EXIF metadata captions.

> **Note**: This project was created using [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) as an experiment in AI-assisted development.

## Inspiration

The border format is inspired by an old box of photos from my grandfather, featuring white borders with machine-printed dates.

## Features

### New in v2.2.0
- Clear photo-import, loading, comparison, and error-recovery flows on macOS and iOS
- Safer preset persistence, partial-import feedback, and collision-free CLI batches
- Brighter labels, larger mobile controls, and accessible selection/export actions

See the [v2.2.0 changelog](CHANGELOG.md#220---2026-09-05) for details and CLI compatibility notes.

### macOS App (SwiftUI)
- **Photo Library Integration**: Browse and select photos from your library
- **Live Preview**: Real-time, WYSIWYG preview — scale-sensitive effects render with the same pattern density the export will have
- **Preset Management**: Create, edit, and apply processing presets with thumbnails
- **Batch Export**: Process multiple images with a concurrent export queue

### CLI Tool
- **Batch Processing**: Process single images or entire directories
- **Concurrent Workers**: Multi-core processing with configurable worker count
- **Shell Scripting**: Integrate into automated workflows

### Layer-Based Composition (12 layer types)

Every render is a fold over one ordered layer stack — the CLI, the app, and every preset format produce identical pixels from the same stack.

- **Border / Padding / Canvas / Resize / Aspect Ratio**: framing and geometry — solid, dominant-color, and gradient fills; Instagram (4:5) and print (10x15cm) formats
- **Orientation**: force landscape or portrait via 90-degree rotation
- **Caption**: EXIF-based captions with template tokens and font styling
- **Overlay**: 168 bundled texture overlays (dirt, film dust, light leaks, wet plate, frames) with blend modes
- **Dither**: 16 algorithms — Bayer (ordered), Floyd–Steinberg, Atkinson, Sierra / Sierra Two-Row / Sierra Lite, Jarvis–Judice–Ninke, Burkes, Stucki, Riemersma (Hilbert curve), Blue Noise, Interleaved Gradient Noise, White Noise, Artistic Drip, Halftone, CMYK Halftone — with B&W, two-tone, dominant-two-tone, per-channel color, and vintage-palette color modes
- **LUT**: `.cube` color lookup tables with Metal-compute rendering and a user LUT library
- **Shader**: 12 stylized looks — ASCII, Pixel Sort, Crimewave, Narc, Shiba, Distant Past, CRT, Halftone, Kuwahara, and the B&W film stack (B&W Film, Film Grain, Rough Border — see below)
- **GPU Effects**: 12 Metal effects across four families — dots, blockify, matrix rain, threshold, crosshatch, edge detection, contour, wave lines, voronoi, noise field, pixel sort, VHS

Effects render on the GPU. Metal is a hard requirement for the dither/shader/GPU-effect layers as of v2.0.0 (present on every supported Mac); output is regression-locked by golden-reference tests rather than eyeballing.

### B&W Film Stack (v2.1.0)

Three shader looks that together reproduce the classic Silver Efex Pro darkroom stack — B&W conversion → film grain → rough border — built by *measuring* Silver Efex Pro 3 rather than imitating it by eye: its GUI was driven programmatically to export calibration ramps, and the extracted transfer curves were fit directly into the shaders (measurement kit and datasets in [`tools/sep-measurement/`](tools/sep-measurement/)).

- **B&W Film**: six-channel spectral sensitivity conversion (R/Ye/G/Cy/B/Mg), a tonality engine fit to measured transfer curves, 30 film response profiles (25 with measured characteristic curves), split toning with a 24-preset darkroom table, vignette, burn edges, and two-scale structure
- **Film Grain**: grains-per-pixel density, soft↔hard kernel, highlight/shadow protection, and 30 real-name film stocks (Kodak, Ilford, Fuji, Agfa, Rollei, Adox, Fomapan, Bergger) with grain values measured from Silver Efex Pro 3's own defaults
- **Rough Border**: 14 seeded procedural border types — exactly reproducible, proportional at any resolution, with per-image variation that keeps preview identical to export

### Caption Templates
- **EXIF Date Extraction**: Automatically displays date as "MON 'YY" format
- **Custom Templates**: Use `{{field}}` placeholders for dynamic captions
  - `{{camera}}`, `{{lens}}`, `{{iso}}`, `{{aperture}}`, `{{shutter}}`, `{{focal}}`
  - `{{year}}`, `{{year2}}`, `{{month}}`, `{{mon}}`, `{{day}}`, `{{date}}`
  - `{{width}}`, `{{height}}` (canvas dimensions)
- **Font Styling**: Bold and italic font style options, any installed font family

### Presets
- **JSON presets** (app-managed): saved by the macOS app to `~/Library/Application Support/Framer/presets/` — not currently resolvable by name via CLI `--preset`. Saving a YAML preset in the app retires the YAML file with that preset's identity after the JSON replacement succeeds, so that edited built-in preset stops resolving via the CLI. Unreadable preset files are preserved for recovery.
- **YAML presets/configs**: v1-compatible schema; CLI discovery chain is `--config path` → `--preset name` (probes `~/Library/Application Support/Framer/presets/<name>.yaml`) → `./.framer.yaml` → `~/.config/framer/default.yaml`. If `--preset` finds no YAML file of that name it silently falls through to the next source
- **Built-in presets** (seeded as YAML on first CLI run): `film`, `instagram`, `minimal`, `print 10x15`, `dark gradient`, `Shader ASCII`, `Shader Crimewave`

## Architecture

Swift Package (SPM) + XcodeGen project with four targets:

| Target | Built by | Description |
|--------|----------|-------------|
| **FramerCore** | SPM | Image-processing library — layers, effects, Metal pipeline, presets |
| **FramerCLI** | SPM | `framer` command-line interface (Swift Argument Parser) |
| **Framer** | XcodeGen/Xcode | SwiftUI macOS app (module name `Framer`, sources in `Sources/FramerApp/`) |
| **FramerMobile** | XcodeGen/Xcode | SwiftUI iOS app (in progress) |

Dependencies:
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- [Yams](https://github.com/jpsim/Yams) — YAML preset/config parsing

## Installation

### From a GitHub Release

Download `framer-v2.2.0-macos-arm64.tar.gz` and `SHA256SUMS` from the
[latest release](https://github.com/arthursoares/framer/releases/latest).
Verify and extract the unsigned CLI package:

```bash
shasum -a 256 -c SHA256SUMS
tar -xzf framer-v2.2.0-macos-arm64.tar.gz
./framer --version
```

If macOS quarantines the downloaded executable, run
`xattr -d com.apple.quarantine ./framer` and retry.

Keep `framer_FramerCore.bundle` beside the executable, including when moving it
to another installation directory. It contains the shaders and ASCII atlases.
Texture overlays still require the source assets described below.

### From Source

Requires Swift 5.10+, macOS 14+, and [Git LFS](https://git-lfs.com) (texture overlays are LFS objects — without `git lfs pull` they are 132-byte pointer files and render as garbage).

```bash
git clone https://github.com/arthursoares/framer.git
cd framer
git lfs install && git lfs pull

# Build + test the CLI and core library
swift build
swift test

# Run
swift run framer -i photo.jpg -o output/
```

### macOS App

```bash
# Generate Xcode project (requires xcodegen)
xcodegen generate

# Open and build in Xcode
open Framer.xcodeproj
```

## CLI Usage

Explicit layer stacks retain their captions unless a caption or font flag is
supplied. Use `--caption-template` to replace captions, font-only flags to update
existing caption typography, or `--no-caption` to remove captions. Batch inputs
that would overwrite the same output filename are rejected before processing.

```bash
# Process a single image
framer -i photo.jpg -o output/

# Process a folder
framer -i photos/ -o output/

# Use a preset
framer -i photo.jpg -o output/ --preset film

# Custom caption template
framer -i photo.jpg -o output/ --caption-template "{{camera}} {{aperture}} {{shutter}}"

# Bold italic caption
framer -i photo.jpg -o output/ --font-bold --font-italic

# Instagram format
framer -i photo.jpg -o output/ --border-style instagram

# Full layer stacks (dither, shaders, LUTs, GPU effects) via YAML config
framer -i photo.jpg -f out.png --output-format png --config my-look.yaml

# Process with 8 workers
framer -i photos/ -o output/ --workers 8
```

## Development

```bash
# Build
swift build

# Test
swift test

# Regenerate Xcode project (required after adding files under Sources/FramerApp/ or Tests/FramerAppTests/)
xcodegen generate
```

Process, architecture, and testing conventions live in the skill library under [.claude/skills/](.claude/skills/) (see [CLAUDE.md](CLAUDE.md)). Releases follow [.claude/skills/release/SKILL.md](.claude/skills/release/SKILL.md); the change record is [CHANGELOG.md](CHANGELOG.md).

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

The LUT layer's automatic path uses Metal when available and falls back to its CPU reference otherwise (the one deliberate exception to the GPU-only effects contract — it doubles as the benchmark baseline).

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
