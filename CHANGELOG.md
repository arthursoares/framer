# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-07-20

The Silver Efex replication release: three new effect layers that together
reproduce the Silver Efex Pro darkroom stack (B&W conversion → film grain →
rough border), built by measuring Silver Efex Pro 3 itself rather than
tuning by eye — its GUI was driven programmatically to export calibration
ramps, and the extracted transfer curves were fit into the shaders
(measurement kit and datasets in `tools/sep-measurement/`).

### Added

#### Rough Border (new shader layer)
- 14 procedural border types (clean line, double rebate, torn, brushed,
  jagged, dashed, soft fade, spatter, wavy, turbulent, grunge band, …) —
  seeded and exactly reproducible; proportional at any resolution or aspect
  ratio (all geometry in min-dimension units)
- Seed field with one-tap shuffle, plus "Vary per Image": each image in a
  batch derives its own border from a stable hash of its filename, so
  preview always matches export and re-runs reproduce
- Border color picker (defaults to black); Size displayed 2–100

#### Film Grain (new shader layer)
- Silver Efex grain model: grains-per-pixel density (higher = finer),
  soft↔hard kernel, and highlight/shadow protection so grain lives in the
  midtones
- 30 film stocks under their real names (Kodak, Ilford, Fuji, Agfa, Rollei,
  Adox, Fomapan, Bergger) with per-stock grain values **measured from Silver
  Efex Pro 3's own defaults**; manufacturer-grouped picker
- Same seed / shuffle / vary-per-image system as Rough Border; grain size
  is preview→export compensated

#### B&W Film (new shader layer)
- Six-channel spectral sensitivity conversion (R/Ye/G/Cy/B/Mg) — the film
  way of rendering color into gray; achromatic pixels are untouched
- Tonality engine **fit to measured Silver Efex transfer curves**:
  brightness is an exact gamma law (`2^(-slider/50)`), contrast a pinned
  log-odds sigmoid, zone dials use measured weight functions, and every
  control pins pure black and pure white like the original
- 30 film response profiles; the 25 films Silver Efex Pro 3 carries install
  their **measured characteristic curves** (Tri-X's S-curve, Delta 3200's
  deep toe, PAN F's paper-white shoulder, …)
- Full finishing block: split toning with the 24-preset darkroom table
  (sepia, selenium, copper, cyan, split toners, ambrotype, …), aspect-true
  vignette with shape dial, per-edge burn edges
- Two-scale structure (local contrast) with zone dials and fine structure,
  soft-limited so edges don't halo
- Levels & curves: gamma, black/white points, and the film's installed
  curve surfaced in the UI with a one-tap reset

#### Sidebar UX (from a three-lens adversarial design review)
- B&W Film and Film Grain panels organized into captioned collapsible
  sections with persisted expansion state
- Honest preset provenance: hand-editing a profile-owned dial flips the
  film / toning / stock picker to "Custom" instead of claiming a profile
  the dials no longer match; double-click reset returns dials to the
  selected profile's values
- Out-of-range preset values widen sliders instead of being silently
  clamped; accessibility labels on hidden-label pickers and icon buttons

#### Tooling
- `tools/sep-measurement/`: the GUI-automation measurement kit (CGEvent
  driver, focus-guarded export scripts, curve extraction) and the measured
  datasets — 13 tonality curves and 25 per-film characteristic curves

### Fixed
- Tone-curve bake had halved boundary tangents, bending the default curve
  into a subtle S (up to 13/255 at the quarter-tones) — caught by ramp
  parity against Silver Efex, now locked by identity tests
- Enum fields decoded from presets now fall back tolerantly on unknown raw
  values instead of throwing (a throwing decode makes PresetStore delete
  the preset file)

## [2.0.0] - 2026-07-09

Complete rewrite from Go CLI to Swift, and everything built on top of it since.
This entry was first drafted on 2026-02-24 for the rewrite itself but v2.0.0 was
never tagged; this release finally ships it, covering all work since v1.2.0
(356 commits, PRs #2–#15).

### Added

#### Swift Rewrite (2026-02)
- **FramerCore library**: standalone image-processing library on CoreGraphics/CoreImage
- **FramerCLI** (`framer`): command-line interface using Swift Argument Parser, with
  `process`, `presets`, `fonts`, and `benchmark` subcommands and `--version`
- **Framer** (macOS app): SwiftUI application with photo library, live preview,
  filmstrip, export queue, and the "Darkroom Editorial" visual design (PR #2)
- **FramerMobile** (iOS app): in progress, shares FramerCore

#### Layer-Based Composition System (12 layer types)
- **Border / Padding / Canvas / Resize / Aspect Ratio**: framing and geometry, with
  solid, dominant-color, and gradient fills; Instagram and print (10x15) formats
- **Orientation**: force landscape/portrait via 90° rotation
- **Caption**: EXIF-based captions with `{{field}}` template tokens, positioning,
  color modes, and font styling (bold/italic, any installed family)
- **Overlay**: 168 bundled textures (dirt, film dust, light leaks, wet plate, frames)
  with per-kind blend modes, tracked via Git LFS
- **Dither**: 17 algorithms (Bayer, Floyd–Steinberg, Atkinson, Sierra family,
  Jarvis–Judice–Ninke, Burkes, Stucki, Riemersma, blue noise, IGN, white noise,
  artistic drip, halftone, CMYK halftone, …) with B&W, two-tone,
  dominant-two-tone, per-channel color, and vintage-palette color modes
- **LUT**: `.cube` LUT parsing with Metal-compute rendering and CPU reference,
  user-imported LUT library, staged `benchmark lut` CLI (PR #4)
- **Shader**: 9 stylized looks (ASCII, pixel sort, crimewave, narc, shiba,
  distant past, CRT, halftone, Kuwahara) (PR #5)
- **GPU Effects bucket**: 12 user-facing Metal effects across four families —
  textCell (dots, blockify, matrixRain), printSampling (threshold, crosshatch),
  edgeField (edgeDetection, contour, waveLines, voronoi, noiseField), glitch
  (pixelSort, vhs) — ported against Grainrad WGSL references (PRs #7, #10, #12)

#### Editor & App UX
- Sidebar "harmony" system: shared layout contract, reusable control primitives,
  SHA-256 snapshot tests locking every inspector surface (PR #8)
- Config-level undo, parameter reset buttons, user-defined dither palettes,
  preset thumbnails, photo deletion from the filmstrip, app icons (PRs #9, #12)
- Presets: JSON presets in `~/Library/Application Support/Framer/presets/`,
  YAML preset/config compatibility with the v1 Go CLI schema, config discovery
  chain (`--config` → `--preset` → `./.framer.yaml` → `~/.config/framer/default.yaml`)

#### Verification
- **Golden-reference effect tests**: GPU renders locked against committed
  reference PNGs with per-effect tolerances (`EffectGPUGoldenTests`), plus GPU
  invariant/behavior tests — the successor to CPU/GPU parity testing
- WYSIWYG contract: scale-sensitive layers honor `previewBaseDimension` so the
  preview provably matches the export
- 273 SPM tests + 63 app-tier test methods; AI-agent skill library documenting
  process and architecture (PRs #13, #14)

### Fixed
- CoreGraphics QoS priority inversion on preview/export render tasks (PR #11)
- GPU-effects parameter consistency: single source of truth for defaults, sRGB
  color round-tripping, dead-slider and encoder-wiring fixes (PRs #3, #10, #12)
- HEIC/PNG color correctness on Metal texture upload; stale-index crash on
  layer deletion; preset picker and palette-selection stickiness (PRs #3, #12)

### Changed
- **BREAKING — Metal is now a hard requirement for effect rendering.** The CPU
  effect path was retired (PR #15, ADR:
  `docs/adr/2026-07-09-retire-cpu-effect-path.md`): a Metal failure throws
  instead of silently rendering a visually different CPU fallback. Kept by
  design: Riemersma dither (sole implementation), legacy hidden bucket
  variants, and the LUT CPU reference (test oracle + benchmark baseline).
  Hosts without a Metal device can no longer render `.shader`/`.dither`/
  `.gpuEffect` layers.
- Architecture: single-file Go → multi-target Swift Package + XcodeGen;
  imaging → CoreGraphics/CoreImage; FreeType → CoreText; goexif → ImageIO;
  flag → Swift Argument Parser

### Removed
- Go source code, dependencies, CI/CD workflows, and embedded font binaries
- Legacy iOS companion app (Framer-iOS/)
- Cross-platform builds (now macOS 14+ / iOS 17+ only)
- The CPU effect implementations (~2,900 lines) superseded by the GPU path

---

## [1.2.0] - 2026-01-22 *(Go era)*

- Metadata tagging improvements and default background color fix.

## [1.1.0] - 2025-10-19 *(Go era)*

- print10x15 preset for Canon Selphy printers.

## [1.0.0] - 2025 *(Go era)*

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
