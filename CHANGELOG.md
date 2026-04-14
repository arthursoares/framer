# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — GPU effects migration (PR #7)

Work on `claude/gpu-effects-migration-MbMMo` refining the GPU-effects bucket system against Grainrad WGSL references.

### Added

- **ASCII font picker**: full `NSFontManager.availableFontFamilies` / `UIFont.familyNames` list bound to `ASCIIShaderParams.fontName`. "System Default" keeps the baked pixel-art atlas; any other font routes through `ASCIIAtlasGenerator` with Core Text rasterisation.
- **ASCII High Detail toggle** (`ASCIIShaderParams.highDetail`): 16×16 atlas cell (up from 8×8) for sharper glyph edges. Orthogonal to the font/characters axes — the toggle only changes resolution when you've already customised chars or font. Shader + CPU `sampleLUT` derive cell size from the atlas height, so both paths coexist without a shader branch.
- **Blockify `.shaded` style**: per-cell radial falloff (matches Grainrad reference), picker option alongside Solid / Outlined. Reuses Border Width slider as the falloff strength.
- **Dots `sizeMultiplier` slider** (0.1 – 2.0): the shader uniform existed but was hard-coded to 1.0 on the encoder side. Now wired through.
- **Mobile parity for Voronoi + Contour**: added `Wall Strength` / `Cell Fill` to Voronoi, `Line Strength` / `Field Intensity` to Contour.

### Fixed

- **Voronoi rewrite (`voronoiVariant` in EdgeField.metal)**: full port of the Grainrad `colorMode=1` path. Samples source at each seed's pixel position, so the classic polygonal mosaic renders with image colour instead of the earlier grayscale wall/interior falloff. Default edge colour flipped to black for voronoi specifically.
- **Contour neighbour-sampling**: rewrote detection to sample 4 neighbours at `thickness`-pixel offsets and compare quantised levels. Invert now applies symmetrically to centre + neighbours.
- **Threshold shader color modes**: `u.color.mode` was ignored — Source / Mono / FG-BG now behave distinctly. Palette option removed from the bucket-level color picker (no palette uniform is encoded into the bucket structs yet — Dither's path is separate).
- **matrixRain "Threshold" dead slider**: UI bound to `params.threshold` but the encoder wrote `params.trailLength` to the shader's `threshold` uniform. Removed the slider; Trail remains.
- **Shader style picker inside detail panel**: a legacy dropdown that silently rewrote layer params without changing the kind label. Removed from desktop + mobile.
- **Stale-index crash in layer bindings**: `binding(for index: Int)` captured the index by value and crashed when a layer was deleted while its detail view was still in the view tree. Rewritten to look up by `layer.id` with a captured fallback.
- **`CGBitmapContextCreate` failures on alpha-last CGImages**: `MetalTextureSupport.normalizedForTextureUpload` now uses a strict exact-match fast-path check (all of `bitsPerComponent`, `bitsPerPixel`, `bitmapInfo.rawValue`, colour-space model) before redrawing; previews no longer fall back to the incorrect colour path for HEIC / some sRGB PNGs.

### Changed

- Atlas-cell addressing in TextCell.metal + ShaderASCIIRenderer now derives cell size from the bound atlas's height, not a hard-coded `8`. Lets 8×8 baked PNGs and 16×16 runtime atlases share the same code path.

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
