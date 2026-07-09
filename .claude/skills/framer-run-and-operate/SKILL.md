---
name: framer-run-and-operate
description: >
  Load this skill to RUN framer: CLI invocations (process/presets/fonts/benchmark
  subcommands, single-image and batch runs, preset and caption-template usage,
  --workers, --no-metadata), running the macOS app from Xcode, and the map of where
  every artifact lives on disk (presets, user LUTs, overlays, YAML config chain,
  export outputs). Triggers: "how do I run framer", "framer CLI flags", "where are
  presets stored", "caption template tokens", "benchmark lut", "output file naming",
  "EXIF/IPTC on exports", "app export queue". NOT for build failures (see
  framer-build-and-env) or performance measurement methodology (see
  framer-diagnostics-and-proof).
---

# Running and operating framer

framer is a Swift photo-framing tool with two operational surfaces: a CLI
(`framer` executable, built by SwiftPM from `Sources/FramerCLI/`) and a macOS
SwiftUI app (`Framer` scheme in the XcodeGen-generated `Framer.xcodeproj`).
Both drive the same `FramerCore` pipeline. This skill tells you how to invoke
them and where every file lands. All facts verified 2026-07-09 at commit 48d85a5.

## When NOT to use this skill

| You are trying to... | Go to |
|---|---|
| Fix a build/toolchain/signing failure, set up from scratch, Git LFS | framer-build-and-env |
| Measure performance or prove a visual claim with numbers | framer-diagnostics-and-proof |
| Understand every config parameter / preset schema field | framer-config-and-flags |
| Understand the render pipeline / layer semantics | framer-architecture-contract |
| Know which docs are stale and why | framer-docs-and-writing |
| Run or repair the test suites | framer-validation-and-qa / framer-campaign-restore-validation |

## The one correct way to invoke the CLI

```bash
swift run framer --help
```

**Trap:** there is a 14 MB executable named `framer` sitting at the repo root.
It is the obsolete pre-rewrite Go v1.x binary (dated Jan 2026, gitignored,
answers with Go `flag`-package usage). Never run `./framer`. Always
`swift run framer ...`, or build once and use the SwiftPM product directly:

```bash
swift build            # debug binary at .build/debug/framer
swift build -c release # release binary at .build/release/framer
```

Top-level surface (verified from `swift run framer --help` and
`Sources/FramerCLI/Framer.swift`):

| Subcommand | Purpose |
|---|---|
| `process` (default) | Process one or more images |
| `presets` | Manage presets (only subcommand: `list`) |
| `fonts` | List available system fonts (monospaced by default; `--all` for everything) |
| `benchmark` | Focused processing benchmarks (only subcommand: `lut`) |

Because `process` is the **default subcommand**, `swift run framer -i photo.jpg -o out/`
is equivalent to `swift run framer process -i photo.jpg -o out/`.

## `process` — flag anatomy

Source: `Sources/FramerCLI/Commands/ProcessCommand.swift`. Required: `--input`
plus **either** `--output` (directory) **or** `--output-file` (single file);
missing both is a `ValidationError`.

Input/output:

| Flag | Meaning |
|---|---|
| `-i, --input <path>` | Input image **or directory** (directory triggers batch mode) |
| `-o, --output <dir>` | Output directory (created if missing) |
| `-f, --output-file <path>` | Exact output file path (single-image only) |
| `--output-format <jpeg\|png>` | Output encoder (default jpeg) |
| `-q, --quality <60-100>` | JPEG quality (setting it forces jpeg output) |

Framing/styling:

| Flag | Meaning |
|---|---|
| `--border-style <s>` | `solid`, `instagram`, `print`, or `print10x15` — **no `-s` short form** (docs claiming one are stale, see below) |
| `-t, --border-thickness <v>` | e.g. `20` (px) or `5%` |
| `--border-color <hex>` / `--background-color <hex>` | Colors, e.g. `#FFFFFF` |
| `--padding <px>` / `--outer-padding <px>` | `--caption-padding` is a legacy alias for outer padding |
| `--print-width <mm>` `--print-height <mm>` `--print-dpi <n>` | Print geometry (defaults 148 / 100 / 300) |
| `--aspect-ratio <W:H>` | Inserts a crop layer at position 0 of the layer stack (e.g. `4:5`) |

Caption:

| Flag | Meaning |
|---|---|
| `--caption <text>` | Literal caption |
| `--caption-template <tpl>` | Template with `{{field}}` tokens (see next section) |
| `--no-caption` | No caption layer |
| `--font-name` `--font-size` `--font-bold` `--font-italic` `--font-color` | Caption typography (defaults: Courier New, auto size, black) |

Config/behavior:

| Flag | Meaning |
|---|---|
| `--config <path>` | Explicit YAML config file |
| `--preset <name>` | Named preset from the preset store |
| `-w, --workers <n>` | Batch concurrency (default: `ProcessInfo.processorCount`) |
| `--post-process <cmd>` | Run after each export via `/bin/sh -c`; `{file}` is replaced with the shell-quoted output path; non-zero exit prints a warning but does not fail the run |
| `--no-metadata` | Do not preserve EXIF metadata (see "Output conventions") |

Behaviors worth knowing (all in `ProcessCommand.swift`):

- **Caption default:** with no caption flags at all, the CLI appends a caption
  layer with template `" - {{mon}} '{{year2}} -"` (e.g. `- JUL '26 -`).
- **Caption override is destructive:** the CLI strips any caption layers that
  came from the preset/config and appends its own. To keep a preset's caption
  exactly, you cannot — re-specify it via `--caption-template`.
- **Batch mode:** if `--input` is a directory, `--output` is required. Files
  with extensions jpg/jpeg/png/tiff/tif/heic are processed by a
  `withThrowingTaskGroup` worker pool; progress prints as `[n/total] name.jpg`.

Worked examples (single-image run verified end-to-end 2026-07-09; produced an
8.4 MB `sample_solid.jpg` with correct EXIF + IPTC):

```bash
# Single image, default solid style
swift run framer -i docs/sample.jpg -o /tmp/framer-out

# Batch a directory with 8 workers using a preset
swift run framer -i ~/Photos/roll1 -o ~/Photos/roll1-framed --preset film -w 8

# Exact output path, PNG, EXIF-driven caption
swift run framer -i photo.jpg -f out.png --output-format png \
  --caption-template "{{camera}}  {{focal}}  {{aperture}}  {{shutter}}  {{iso}}"
```

## Caption template tokens

Verified against the resolver `Sources/FramerCore/Models/ExifData.swift`
(`resolve(template:)`). Missing EXIF values render as empty string; the date
falls back to "now" if the photo has no EXIF date.

| Token | Renders as | Example |
|---|---|---|
| `{{year}}` | 4-digit year | `2019` |
| `{{year2}}` | 2-digit year | `19` |
| `{{month}}` | Full month name | `October` |
| `{{mon}}` | 3-letter upper month | `OCT` |
| `{{day}}` | Zero-padded day | `11` |
| `{{date}}` | `yyyy-MM-dd` | `2019-10-11` |
| `{{camera}}` | Camera model string | `GR II` |
| `{{lens}}` | Lens string | |
| `{{iso}}` | `ISO ` prefix added | `ISO 200` |
| `{{aperture}}` | `f/` prefix added | `f/2.8` |
| `{{shutter}}` | As stored | `1/250` |
| `{{focal}}` | `mm` suffix added | `28mm` |

## Config resolution chain

First hit wins: explicit `--config` beats `--preset`, which beats local
`./.framer.yaml`, which beats `~/.config/framer/default.yaml`, which beats the
built-in `ProcessingConfig.default`; CLI flags then override individual fields
on top of whatever loaded. The full ordered chain (with paths and source-line
citations) and the field-by-field YAML schema are owned by
**framer-config-and-flags**.

## `benchmark lut` — the measurement template

Full anatomy (verified from `--help` and
`Sources/FramerCLI/Commands/BenchmarkCommand.swift`):

```bash
swift run framer benchmark lut \
  --input docs/sample.jpg \
  --lut assets/luts/ANDP-KodakPortra800-32bit.CUBE \
  --preview-base 1200 \
  --iterations 10 \
  --warmup 2
```

| Option | Default | Meaning |
|---|---|---|
| `-i, --input <path>` | required | Input image |
| `--lut <path>` | required | `.cube` LUT file |
| `--intensity <0...1>` | 1.0 | LUT intensity |
| `--preview-base <n>` | omitted | Preview base dimension; **omit to benchmark full export-size rendering** |
| `--iterations <n>` | 10 | Measured iterations per backend |
| `--warmup <n>` | 2 | Warmup iterations per backend |

It prints CPU vs `Auto(Metal)` mean/median/min/max in ms, a speedup factor,
and (Metal only) per-stage timings: `upload`, `gpu`, `readback`.

**Reproducibility template** — README.md's dated measurement block (measured
2026-04-01, `docs/sample.jpg` at 3000x1987, `assets/luts/ANDP-KodakPortra800-32bit.CUBE`):

- Preview (`--preview-base 1200`): CPU `233.04 ms`, Auto(Metal) `32.44 ms`, speedup `7.18x`
- Full export (no `--preview-base`): CPU `1964.00 ms`, Auto(Metal) `78.16 ms`, speedup `25.13x`

Re-run 2026-07-09 on this machine (3 iterations, same image/LUT, preview mode):
CPU mean `161.16 ms`, Auto(Metal) mean `20.54 ms`, speedup `7.85x`, stages
upload `18.46` / gpu `3.59` / readback `25.48 ms` — same shape, faster absolute
numbers. When you claim a LUT performance change, reproduce this block and
date-stamp it exactly as README does.

README's stated "next high-impact optimization" (keep preview output resident
in a Metal texture to skip per-change CPU readback — note readback alone costs
more than the GPU pass above) is **OPEN, deliberately deferred work**, not
shipped. It is owned by framer-research-frontier.

## Running the macOS app

```bash
xcodegen generate        # only needed after adding files or editing project.yml;
                         # Framer.xcodeproj is committed and usually current
open Framer.xcodeproj    # then run the "Framer" scheme in Xcode
```

Caveats (as of 2026-07-09 on the maintainer's machine): the Apple Development
signing certificate is revoked (`CSSMERR_TP_CERT_REVOKED` — not merely expired;
cert state and remediation: **framer-campaign-restore-validation** P1) and the
Xcode 26 Metal Toolchain component is
not installed, so `xcodebuild` invocations fail — the in-Xcode run experience
and the fixes are owned by **framer-build-and-env**. Do not conclude the repo
is broken from `xcodebuild` failures; `swift build && swift test` is the
healthy fast tier.

What the app needs at runtime:

- **Texture overlays**: `assets/textures/` is bundled into the app as a folder
  reference (`project.yml` targets Framer and FramerMobile). Those ~168 files
  are Git LFS objects — without `git lfs pull` they are 132-byte pointer files
  and overlays render as garbage. Setup ownership: framer-build-and-env.
- **Fonts**: `assets/fonts/` is bundled the same way; at launch the app
  registers every bundled `.ttf`/`.otf` via `CTFontManagerRegisterFontsForURL`
  (`Sources/FramerApp/App/FramerApp.swift`, `registerBundledFonts()`).

### The app's export queue

Verified in `Sources/FramerApp/App/AppState.swift`:

- Each export creates an `ExportJob` with status
  `queued | running | done | cancelled | failed(String)`.
- Concurrency per job: `min(itemCount, min(6, max(1, activeProcessorCount - 1)))`
  (`recommendedExportConcurrency`) — capped at 6 to keep the UI responsive.
  Note this differs from the CLI, whose `--workers` defaults to full
  `processorCount`.
- Output naming: `<input-stem>_<suffix>.<jpg|png>` where suffix is the
  sanitized active preset name (lowercased, non-alphanumerics → `_`), falling
  back to `framed`.
- Failed jobs are retryable (`retryJob`); running jobs are cancellable
  (`cancelJob`); a partially failed job ends as `failed("N of M failed")`.

## File-location map

Every path verified in code, 2026-07-09:

| Artifact | Location | Source of truth |
|---|---|---|
| JSON presets (app-saved) | `~/Library/Application Support/Framer/presets/<UUID>.json` | `Sources/FramerCore/Presets/PresetStore.swift` |
| YAML presets (CLI `--preset`, seeded defaults) | same directory, `<name>.yaml` | `PresetStore.swift`, `YAMLConfig.loadDefault` |
| User LUTs (imported `.cube`) | `~/Library/Application Support/Framer/luts/` | `Sources/FramerCore/Processing/LUTProvider.swift` (`userLUTDirectory`) |
| User overlays | `~/Library/Application Support/Framer/overlays/` | `Sources/FramerCore/Processing/TextureFrameProvider.swift` (`searchPaths`) |
| Saved user palettes (since PR #12, merged 2026-07-09) | `~/Library/Application Support/Framer/palettes.json` (single file) | `Sources/FramerCore/Presets/UserPaletteStore.swift` |
| Bundled overlays (app) | `Framer.app` Resources `textures/` (folder ref of `assets/textures/`) | `TextureFrameProvider.searchPaths` path 1 |
| Bundled overlays (CLI/tests) | FramerCore `Bundle.module` `textures/` — only the two ASCII atlas PNGs | `TextureFrameProvider.searchPaths` path 2 |
| YAML config chain | `--config` → preset dir → `./.framer.yaml` → `~/.config/framer/default.yaml` | `YAMLConfig.swift` 281-305 |
| CLI binaries | `.build/debug/framer`, `.build/release/framer` | SwiftPM convention |

Preset-store behaviors that affect operations:

- **Identity**: YAML presets get a deterministic UUID derived (MD5) from their
  name; a JSON preset with the same UUID **overrides** the YAML one in listings.
- **Seeding**: 19 default presets (film, instagram, minimal, print 10x15,
  dark gradient, plus Shader */GPU * effect presets) are written as YAML on
  first run — but seeding is **skipped entirely if any `.yaml` already exists**
  (`PresetStore.initializeDefaults`), so an older install may show only the
  original 5. `swift run framer presets list` prints `name (UUID)` per preset.
- **Hazard**: `PresetStore.list()` silently **deletes** any `.json` preset file
  it cannot decode. A Codable regression can destroy user presets on next
  launch — see framer-architecture-contract before touching preset Codable.
- **Bundled LUTs are apparently latent**: `LUTProvider.bundledLUTs()` looks for
  `<executable-dir>/assets/luts` (`LUTProvider.swift` ~line 296), but nothing —
  neither `project.yml` nor SwiftPM — places an `assets/luts` folder next to
  any binary, so in practice only user-imported LUTs (Application Support) are
  visible. It only "works" if you happen to run a binary from a directory
  containing `assets/luts` (e.g. repo root with a copied binary). Label:
  apparently latent — verify intent with the maintainer before "fixing".
  The repo's `.cube` files live in `assets/luts/` and are usable via explicit
  paths (as `benchmark lut` does).

## Output conventions

- **Naming (CLI)**: when using `--output <dir>`, files are named
  `<stem><suffix>.<ext>` with suffix from the border style: `_solid`,
  `_instagram`, `_print` (`ProcessCommand.outputName`). `--output-file` gives
  you the exact path. Extension is `jpg` or `png` per `--output-format`.
- **EXIF preservation**: `Sources/FramerCore/EXIF/MetadataWriter.swift` copies
  all source metadata onto the export, resets EXIF/TIFF orientation to 1
  (rotation is baked into pixels), and appends IPTC keywords
  `["framer", "framer - <style>"]`. Verified live: an export of
  `docs/sample.jpg` carries `Model: GR II`, `Orientation: normal`, and
  `Keywords: framer, framer - solid`.
- **`--no-metadata`**: exists on main (not just the E2E branch — verified in
  `ProcessCommand.swift` line 35 and `--help`). Sets
  `ProcessingConfig.noMetadata`, which makes `MetadataWriter` skip the entire
  preserve block: no source metadata copied **and no IPTC keywords added**;
  only compression settings are written.
- **Encoders**: JPEG quality maps to `kCGImageDestinationLossyCompressionQuality`
  = quality/100; PNG is lossless via ImageIO.

## Known-stale operational docs (do not follow, do not edit)

The staleness ledger is owned by framer-docs-and-writing; these are the entries
that bite operators:

- `docs/index.html` (GitHub Pages) uses the legacy Go-CLI syntax: bare `framer`
  invocations and a `-s` short flag for border style (`framer -i photo.jpg -o
  output/ -s instagram`, and its flags table lists `--border-style, -s`).
  **There is no `-s` flag** in the Swift CLI — `--border-style` is long-form
  only. `-i`/`-o` still work.
- `README.md` "Usage" also shows `framer ... -s instagram` (stale) amid
  otherwise-correct examples.
- `docs/examples/*.jpg` (10 example outputs) were committed once on 2026-01-23
  (commit 1087d41, "add GitHub Pages documentation website") and there is no
  generation script anywhere in the repo — treat them as non-regenerable
  goldens; if you regenerate them by hand, expect pixel differences.
- CLAUDE.md was rewritten 2026-07-09 to route to this skill library (its old
  `.ai-assistant/` chain pointed at directories that never existed in git).

## Provenance and maintenance

All claims verified 2026-07-09 against commit 48d85a5 by reading the cited
sources, running the CLI (`--help` for every subcommand, a real single-image
export inspected with exiftool, a live `benchmark lut` run, `presets list`),
and read-only git commands. Re-verify with:

```bash
# CLI surface and flags
swift run framer --help
swift run framer process --help
swift run framer benchmark lut --help
grep -n "defaultSubcommand" Sources/FramerCLI/Framer.swift
grep -n "noMetadata\|--workers\|postProcess" Sources/FramerCLI/Commands/ProcessCommand.swift

# Caption tokens
grep -n '{{' Sources/FramerCore/Models/ExifData.swift

# Config chain and file locations
sed -n '281,305p' Sources/FramerCore/Presets/YAMLConfig.swift
grep -n "Framer/presets" Sources/FramerCore/Presets/PresetStore.swift
grep -n "Framer/luts\|assets/luts" Sources/FramerCore/Processing/LUTProvider.swift
grep -n "Framer/overlays" Sources/FramerCore/Processing/TextureFrameProvider.swift

# Metadata behavior
grep -n "IPTCKeywords\|preserveMetadata" Sources/FramerCore/EXIF/MetadataWriter.swift

# App export queue
grep -n "recommendedExportConcurrency\|JobStatus" Sources/FramerApp/App/AppState.swift

# Benchmark numbers (README block) and stale -s syntax
grep -n "233.04\|1964.00" README.md
grep -n '\-s instagram' README.md docs/index.html

# docs/examples provenance
git log --oneline -1 -- docs/examples/
```

Facts most likely to drift: the benchmark timings (hardware/OS dependent —
always re-measure, never quote stale numbers as current), the signing/Metal
Toolchain brokenness (may get fixed; check framer-build-and-env), the latent
`assets/luts` lookup (an open question that may be resolved either way), and
the default-preset list (grows when new effect presets ship).
