---
name: framer-config-and-flags
description: Catalog of every configuration axis in framer — the 12 CompositionLayer cases and their params structs, GPUEffectKind's 15 variants with visibility and capability flags, JSON/YAML preset schemas, the CLI config discovery chain and full flag surface, where defaults live, and back-compat rules for schema changes. Load when adding/renaming a parameter, touching Codable init(from:)/encode, editing YAMLConfig.swift or PresetStore.swift, adding a CLI flag, wondering which sliders an effect variant actually reads, or debugging "preset won't load"/"slider does nothing"/"where is this default set". Keywords - ProcessingConfig, YAMLLayerSchema, userFacingCases, usesCommonAdjustments, decodeIfPresent, preset, .framer.yaml, defaultParams.
---

# framer-config-and-flags

Every knob in this project — layer params, GPU capability flags, preset files, CLI flags, defaults — cataloged with file:line ground truth. All facts verified 2026-07-09 at commit `48d85a5` unless noted. This content drifts fast; run the one-liners in "Provenance and maintenance" before trusting any table.

**Jargon, once:**
- **Layer** — one element of `ProcessingConfig.layers: [CompositionLayer]?`; the render pipeline folds layers over the image in array order.
- **Bucket** — one of 4 GPU-effect parameter families (`textCell`, `printSampling`, `edgeField`, `glitch`); each bucket serves several visual **variants** (`GPUEffectKind`).
- **Capability flag** — a computed Bool on `GPUEffectKind` telling the UI which control blocks that variant's shader actually reads.
- **Preset** — a saved `ProcessingConfig` with a name, stored as JSON or YAML.

## When NOT to use this skill

| You actually want | Go to sibling |
|---|---|
| Shader loading, uniforms, texture upload, adding a whole GPU effect | framer-metal-pipeline-reference |
| Dithering/pixel-sort/blend math and color-space theory | framer-image-processing-reference |
| Running the CLI/app, output file locations, LUT/overlay directories | framer-run-and-operate |
| Build/toolchain setup, xcodegen, LFS | framer-build-and-env |
| Sidebar control grammar, design tokens | framer-ui-design-system |
| Test conventions, snapshot discipline, what counts as evidence | framer-validation-and-qa |
| Commit/branch/PR rules, what needs review | framer-change-control |
| Full story behind an incident named here | framer-failure-archaeology |
| Which docs are stale (full ledger) | framer-docs-and-writing |

## The configuration model in one sentence

Everything — macOS app, iOS app, CLI, JSON presets, YAML presets — is a view over one struct: `ProcessingConfig` (`Sources/FramerCore/Models/ProcessingConfig.swift:195-234`) whose payload is `layers: [CompositionLayer]?`; layer order is render order.

`ProcessingConfig` top-level fields (mostly legacy Go-CLI-era knobs; the layer array is the modern surface): `borderStyle`, `borderThickness`, `borderColor`, `padding`, `outputFormat`, `instagramMaxSize`, `postProcess`, `backgroundColor`, `outerPadding`, `noMetadata`, `backgroundMode`, `layers`. Defaults live in the memberwise init (`ProcessingConfig.swift:207-218`); `ProcessingConfig.default = ProcessingConfig()` at line 234.

## Layer parameter catalog — the 12 CompositionLayer cases

Enum at `Sources/FramerCore/Models/CompositionLayer.swift:1657-1668`. Params structs (all `Identifiable, Codable, Equatable, Sendable`):

| Case | Params struct | Location | YAML `type:` string |
|---|---|---|---|
| `.border` | `BorderLayerParams` | CompositionLayer.swift:94 | `border` |
| `.padding` | `PaddingLayerParams` | CompositionLayer.swift:127 | `padding` |
| `.canvas` | `CanvasLayerParams` | CompositionLayer.swift:160 | `canvas` |
| `.resize` | `ResizeLayerParams` | CompositionLayer.swift:197 | `resize` |
| `.overlay` | `OverlayLayerParams` | CompositionLayer.swift:293 | `overlay` |
| `.orientation` | `OrientationLayerParams` | CompositionLayer.swift:341 | `orientation` |
| `.caption` | `CaptionLayerParams` | CompositionLayer.swift:419 | `caption` |
| `.dither` | `DitherLayerParams` | CompositionLayer.swift:722 | `dither` |
| `.aspectRatio` | `AspectRatioLayerParams` | CompositionLayer.swift:814 | `aspect_ratio` |
| `.lut` | `LUTLayerParams` | CompositionLayer.swift:893 | `lut` |
| `.shader` | `ShaderLayerParams` | CompositionLayer.swift:1564 | `shader` |
| `.gpuEffect` | `GPUEffectLayerParams` | Effects/Models/GPUEffectParameters.swift:499 | `gpu_effect` |

The `.shader` layer carries `ShaderStyleParams` — 9 sub-styles, each with its own params struct in CompositionLayer.swift: `ascii`, `crimewave`, `narc`, `shiba`, `pixelSort`, `distantPast`, `crt`, `halftone`, `kuwahara` (enum at CompositionLayer.swift:1457; "Shader Ceiling" in the preset list is a tuned `.pixelSort` config — PresetStore.swift:287-299 — not a tenth style).

The `.gpuEffect` layer carries `GPUEffectParameters` — a 4-case bucket enum (`Effects/Models/GPUEffectParameters.swift:432-435`): `textCell` / `printSampling` / `edgeField` / `glitch`, each holding shared `common` + `geometry` + `color` blocks plus a bucket payload struct (`TextCellParameters`, `PrintSamplingParameters`, `EdgeFieldParameters`, `GlitchParameters` — all in GPUEffectParameters.swift).

## GPUEffectKind — 15 variants, visibility, capability flags

`Sources/FramerCore/Effects/Models/GPUEffectKind.swift`. 15 raw-String cases: `ascii, dithering, halftone, matrixRain, dots, contour, pixelSort, blockify, threshold, edgeDetection, crosshatch, waveLines, noiseField, voronoi, vhs`.

### Visibility: userFacingCases (lines 42-49)

Hidden from the layer-add picker: **`.ascii`, `.halftone`, `.dithering`** — because better-tuned canonical implementations live in the `.shader` layer (ASCII, Halftone) and `.dither` layer (all 17 algorithms + vintage palettes; the bucket variant only had 3 algorithms — the "Dithering doesn't have the presets" user report). `.pixelSort` IS user-facing (re-exposed in "sidebar harmony pass 4", per the doc comment at lines 35-38).

**RULE: never delete the hidden enum cases.** They exist for YAML back-compat, preset roundtrip, and Codable stability (doc comment, lines 40-41). Hidden = removed from the picker only; old presets referencing them must keep decoding forever.

### Capability flags (lines 81-124) — THE ground truth for which params a variant reads

| Flag | Returns true for | Meaning |
|---|---|---|
| `usesGeometry` | `dots, blockify, matrixRain, ascii` (TextCell family) | shader reads `geometry.scale`/`spacing` as cell pitch |
| `usesColorModeAndFgBg` | `dots, blockify, matrixRain, threshold, crosshatch, edgeDetection` | shader consumes color mode + fg/bg colors |
| `usesBackgroundIntensity` | `edgeDetection, contour, waveLines, voronoi, noiseField` (EdgeField family) | shader uses backgroundIntensity as "paper level" |
| `usesPalette` (new in PR #12, merged 2026-07-09) | `dots, blockify, threshold, crosshatch, edgeDetection` | shader implements `.palette` color mode (`framerPalettePick` in ShaderCommon.h); drives whether the color-mode picker offers "Palette" + shows the palette editor (both platforms; saved user palettes live in `UserPaletteStore`) |
| `usesCommonAdjustments` | everything EXCEPT `pixelSort` | shader wraps its source sample in `applyCommonAdjustments` (brightness/contrast/saturation/hueRotation/gamma; sharpness field exists but is never consumed by any bucket shader) |

**`docs/gpu-effects-parameter-matrix.md` is a STALE snapshot — do not trust it.** Verified stale on three load-bearing points (as of 2026-07-09): line 15 says pixelSort is hidden (it is user-facing); line 18 says vhs is CPU-only (`GlitchGPURenderer.renderVHS` dispatches to `glitchFragment` in Glitch.metal — Effects/Renderers/GlitchGPURenderer.swift:67-82); line 28 says no bucket shader applies the common block (`applyCommonAdjustments` appears in EdgeField.metal, Glitch.metal, TextCell.metal, PrintSampling.metal). Ground truth = GPUEffectKind flags + the .metal sources. Full staleness ledger: framer-docs-and-writing.

### Who consults the flags (as of f2c9521)

- macOS: `Sources/FramerApp/Editor/LayerListSection.swift:278-353` gates the geometry/color/common control blocks on the flags.
- iOS: `Sources/FramerMobile/Layers/LayerDetailView.swift` now gates on all five flags too — `usesGeometry` (:203), `usesColorModeAndFgBg` (:237), `usesPalette` (:245), `usesBackgroundIntensity` (:258), `usesCommonAdjustments` (:262). This parity landed with PR #12 (**merged 2026-07-09**, `f2c9521`); before that, iOS was flag-blind and dead controls could ship there.

## Defaults — where they live (and the known drift)

| Default | Location |
|---|---|
| Whole-config defaults | `ProcessingConfig` init defaults + `.default` (ProcessingConfig.swift:207-234) |
| Default layer stack | `CompositionLayer.defaultLayers()` — border 20px white, padding 150 white, caption (CompositionLayer.swift:1873-1880) |
| Per-layer params | each params struct's memberwise-init default values (e.g. `KuwaharaShaderParams(kernelSize: 4, softness: 1.0)`, `GlitchParameters(amount: 0.5, threshold: 0.5, ...)`) |
| Fresh `.gpuEffect` layer per kind | `GPUEffectKind.makeDefaultLayer()` (GPUEffectKind.swift:151-252) |
| CLI caption default | `.template(" - {{mon}} '{{year2}} -")` (ProcessCommand.swift:82) |

**Single source of truth (since PR #12, merged 2026-07-09, `f2c9521`):** `GPUEffectKind.defaultParameters()` (GPUEffectKind.swift:172) is THE per-kind default-params function; `makeDefaultLayer()` calls it, and the duplicated private `defaultParams(for:)` copies in the macOS and iOS inspectors were deleted (verified: zero `defaultParams(for` hits in Sources/FramerApp or Sources/FramerMobile). A default change now goes in exactly one place.

**Historical drift (pre-merge state, for archaeology):** before 2026-07-09, defaults lived in THREE disagreeing places — `makeDefaultLayer()` plus duplicated `defaultParams(for:)` in LayerListSection.swift and LayerDetailView.swift — so adding a layer vs switching an existing layer's kind produced different defaults (e.g. pixelSort `0.5/0.5` vs `0.65/0.42`). Do not reintroduce inspector-local default tables.

## Preset and config file formats

### JSON presets (app)

- Stored as `<UUID>.json` in `~/Library/Application Support/Framer/presets/` (`Sources/FramerCore/Presets/PresetStore.swift:8-14`). **README.md line 52 claims `~/.config/framer/presets/` — that is WRONG for presets** (only the CLI's `default.yaml` fallback lives under `~/.config/framer/`). Do not "fix" code to match README.
- `PresetStore.list()` loads YAML presets first, then JSON; JSON overrides a YAML preset with the same ID. YAML preset identity is a deterministic MD5-derived UUID of the preset name (`PresetStore.swift:131-138`).
- **Recovery policy (updated 2026-09-05):** `list()` skips unreadable JSON and preserves the original files. `PresetStoreTests` guards malformed/unsupported records and read failures against deletion. Keep saved-preset fixture coverage for changes to `Preset`/`ProcessingConfig`/`CompositionLayer`: a decoding regression still hides valid user presets. Never restore the old delete-on-decode-failure behavior.

### YAML presets / config files (Go-CLI-compatible)

`Sources/FramerCore/Presets/YAMLConfig.swift` — flat snake_case schema kept compatible with the predecessor Go CLI (file header, line 6). Two structs:

- `YAMLSchema` (lines 8-25): 15 top-level keys (`border_style`, `border_thickness`, `border_color`, `padding`, `jpeg_quality`, `output_format`, `instagram_max_size`, `post_process`, `background_color`, `outer_padding`, `no_metadata`, `print_width_mm`, `print_height_mm`, `print_dpi`, `background_mode`) + `layers`.
- `YAMLLayerSchema` (lines 27-195): **165 optional fields** as of 48d85a5 — one flat namespace shared by all 12 layer types, discriminated by `type:`. Prefixes: bare names for classic layers (`thickness`, `color`, `caption_*`, `dither_*`, `lut_name`...), `shader_*` for the `.shader` layer, `gpu_*` for `.gpuEffect` (`gpu_effect_kind`, `gpu_common_*`, `gpu_text_*`, `gpu_edge_*`, `gpu_glitch_*`, ...). Every field is `Optional`, so YAML decode is tolerant-by-construction: unknown layers are skipped, missing fields fall back in `decodeLayer` (`case "border":` etc., lines 477-651).

### Built-in presets

`PresetStore.initializeDefaults()` (`PresetStore.swift:142-411`) seeds **19 presets as `<name>.yaml`** on first run (skipped if any YAML already exists): `film`, `instagram`, `minimal`, `print 10x15`, `dark gradient`, `Shader ASCII`, `Shader Crimewave`, `Shader Narc`, `Shader Shiba`, `Shader Pixel Sort`, `Shader Ceiling`, `Shader Distant Past`, `Shader CRT`, `Shader Halftone`, `Shader Kuwahara`, `GPU ASCII Matrix`, `GPU Halftone Print`, `GPU Wave Field`, `GPU VHS Static`.

### CLI config discovery chain

`YAMLConfig.loadDefault` (`YAMLConfig.swift:281-305`), first hit wins; explicit CLI flags then override on top (`ProcessCommand.run`, line 45 comment):

1. `--config <path>` (explicit YAML file)
2. `--preset <name>` → `~/Library/Application Support/Framer/presets/<name>.yaml`
3. `./.framer.yaml` (current directory)
4. `~/.config/framer/default.yaml` (macOS only, `#if os(macOS)`)
5. `ProcessingConfig.default`

## CLI surface (verified via `swift run framer --help`, 2026-07-09)

Entry: `Sources/FramerCLI/Framer.swift` — subcommands `process` (default), `presets`, `fonts`, `benchmark`.

| Subcommand | Source | Surface |
|---|---|---|
| `process` | Commands/ProcessCommand.swift | 29 options/flags, below |
| `presets list` | Commands/PresetsCommand.swift | no flags; prints name + UUID |
| `fonts` | Commands/FontsCommand.swift | `--all` (default: monospaced only) |
| `benchmark lut` | Commands/BenchmarkCommand.swift | `-i/--input`, `--lut`, `--intensity` (1.0), `--preview-base`, `--iterations` (10), `--warmup` (2) |

`framer process` flags (from `swift run framer process --help`):

| Group | Flags |
|---|---|
| I/O | `-i/--input` (required), `-o/--output` (dir), `-f/--output-file` (single file; one of the two outputs is required) |
| Border | `--border-style` (solid/instagram/print/print10x15), `-t/--border-thickness` (px or `%`), `--border-color`, `--padding` |
| Caption | `--caption`, `--caption-template` (`{{field}}` placeholders), `--no-caption`, `--font-name`, `--font-size`, `--font-bold`, `--font-italic`, `--font-color` |
| Output | `-q/--quality` (60-100), `--output-format` (jpeg/png), `--no-metadata`, `--post-process` (`{file}` = output path) |
| Config | `--config`, `--preset` |
| Print | `--print-width` (mm, default 148), `--print-height` (100), `--print-dpi` (300) |
| Misc | `-w/--workers` (batch parallelism, default = CPU count), `--background-color`, `--outer-padding`, `--caption-padding` (legacy alias for `--outer-padding`), `--aspect-ratio` (e.g. `4:5`; inserted as an `.aspectRatio` layer at index 0) |

Notes: CLI caption handling REPLACES any caption layers from the loaded config (`ProcessCommand.swift:112-115`); `--no-caption` maps to `CaptionMode.none`. Operation recipes and output naming (`_solid`/`_instagram`/`_print` suffixes) live in framer-run-and-operate.

## Back-compat rules for ANY schema change

House style, enforced by convention across every params struct:

1. **New JSON field → `decodeIfPresent(...) ?? default`** in a hand-written `init(from:)`. Never a bare `decode` for a new field — old presets must keep loading. Exemplar: `ProcessingConfig.init(from:)` "Fields with defaults for backward compat" (ProcessingConfig.swift:255-260).
2. **`encode` skips default values** where the struct customizes encoding (keeps YAML/JSON minimal and diff-friendly; e.g. YAML encoders only set `enabled: false`, never `true`).
3. **Never delete a legacy decode branch.** Live examples you must preserve:
   - Kuwahara legacy `sharpness` (0..8, inverted) → `softness = 1 - sharpness/8`, encode never writes `sharpness` — both JSON (`KuwaharaShaderParams`, CompositionLayer.swift:1437-1455) and YAML (`shader_sharpness`, YAMLConfig.swift:1074-1085).
   - Caption legacy `fontColor` → `fontColorMode = .fixed(color)` fallback (CompositionLayer.swift:487-493).
   - `gpu_edge_variant` YAML key decoded with fallback to the kind-derived variant (YAMLConfig.swift:828).
   - `CaptionMode.none` case kept (ProcessingConfig.swift:146-150) even though the CLI strips `.none`-mode caption layers instead of persisting them (ProcessCommand.swift:112-115); YAML `caption_mode: "none"` must keep decoding (YAMLConfig.swift:537).
   - Hidden `GPUEffectKind` cases `.ascii`/`.halftone`/`.dithering` (see above).
4. **New YAML key → new `Optional` field in `YAMLLayerSchema`**, snake_case, prefixed by owning layer family; decode with `?? default`.
5. **Fixture-test the decode paths** before shipping — a broken decode hides valid presets even though the original files are preserved for recovery.

## CHECKLIST — adding a parameter to a GPU effect

The recurring audit finding in this repo is **dead-slider drift**: a control renders but the shader never reads the value (incident: matrixRain "Threshold" slider bound to a field the encoder never sent — full story in framer-failure-archaeology; capability flags were the fix). Every step below exists to prevent one variant of that. Do them ALL in one PR:

1. **MSL uniform field + Swift mirror, same patch.** Add the field to the effect's MSL uniform struct (in its `.metal` file or `Effects/Metal/ShaderCommon.h` for shared blocks) AND to the Swift mirror struct in the same commit. Field order, types, and explicit `_pad` fields must match byte-for-byte (`Effects/GPU/SharedUniforms.swift:1-16` layout discipline). Mechanics: framer-metal-pipeline-reference.
2. **Encoder actually writes it.** The renderer's uniform construction must populate the new field; encode with `uniformBytes(_:)` (`Effects/GPU/MetalUniformEncoding.swift:24`) — never `withUnsafeBytes`. Shared common/geometry packing helpers: `Effects/GPU/GPUParameterEncoder.swift`.
3. **Model field with back-compat Codable.** Add to the params struct (GPUEffectParameters.swift for buckets, CompositionLayer.swift for `.shader` styles) following the back-compat rules above.
4. **Capability flag if variant-specific.** If only some `GPUEffectKind`s read it, gate the UI via a flag on GPUEffectKind.swift (extend an existing flag or add one) — otherwise you ship inert controls on other variants.
5. **UI row on BOTH platforms.** macOS: `Sources/FramerApp/Editor/LayerListSection.swift` (4856 lines — GPU-effect controls around lines 278-353 consult the flags). iOS: `Sources/FramerMobile/Layers/LayerDetailView.swift` (3532 lines; flag-gated since PR #12 merged 2026-07-09 — keep it that way). Sidebar row grammar: framer-ui-design-system.
6. **YAML key.** New `gpu_*`/`shader_*` optional field in `YAMLLayerSchema` + encode in `encodeLayers` + tolerant decode (`?? default`) in `decodeLayer` (YAMLConfig.swift).
7. **Golden/behavior tests.** The effect path is GPU-only (CPU twins retired 2026-07-09 — docs/adr/2026-07-09-retire-cpu-effect-path.md; do NOT write a CPU twin for the new parameter). `swift test --filter EffectGPUGoldenTests` and `--filter EffectGPUBehaviorTests` must stay green; if the parameter deliberately changes a default look, regenerate the affected goldens in the same commit with an explanation. Exception: a parameter consumed by Riemersma dither or the legacy bucket CPU loops must be wired in those kept CPU paths.
8. **Defaults live in ONE place.** `GPUEffectKind.defaultParameters()` in GPUEffectKind.swift (single source of truth since PR #12 merged 2026-07-09). Do not add per-inspector default tables — that duplication was the pre-2026-07-09 drift bug.
9. **Dead-slider self-audit before PR:** for the new control, trace value → model field → encoder → MSL field → actual read in shader code. If any hop is missing, you've recreated the incident. Measurement-based verification recipes: framer-diagnostics-and-proof.

For a parameter on a NON-GPU layer, use steps 3, 5, 6 plus a `BorderRenderer.applyLayers` / renderer change and a roundtrip test in `Tests/FramerCoreTests/CompositionLayerTests.swift` — and remember the PresetStore fixture rule.

## Provenance and maintenance

All claims verified 2026-07-09 against commit `48d85a5` by reading the cited files, running `swift run framer --help` / `swift run framer process --help` (build succeeded, output captured); flag-parity and defaults claims re-verified 2026-07-09 against `f2c9521` (PR #12 MERGED). Line numbers WILL drift — trust the greps below over the numbers above.

Re-verification one-liners (run from repo root):

| Fact | Command |
|---|---|
| 12 layer cases | `grep -n "case .*LayerParams)" Sources/FramerCore/Models/CompositionLayer.swift \| tail -12` |
| Params struct locations | `grep -rn "struct .*LayerParams: Identifiable" Sources/FramerCore/` |
| Hidden GPU kinds | `grep -n -A 6 "userFacingCases" Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| Capability flags | `grep -n "usesGeometry\|usesColorModeAndFgBg\|usesPalette\|usesBackgroundIntensity\|usesCommonAdjustments" Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| Which shaders apply common block | `grep -ln "applyCommonAdjustments" Sources/FramerCore/Effects/Metal/*.metal` |
| iOS flag parity still holds? | `grep -rn "usesCommonAdjustments\|usesGeometry" Sources/FramerMobile/` (expect hits in LayerDetailView.swift; zero hits = regression, update this skill) |
| Defaults single source of truth intact? | `grep -rn "defaultParams(for" Sources/FramerApp Sources/FramerMobile` (expect ZERO hits) and `grep -n "defaultParameters" Sources/FramerCore/Effects/Models/GPUEffectKind.swift` (expect the func); `gh pr view 12 --json state` (expect MERGED) |
| Preset directory | `grep -n "Framer/presets" Sources/FramerCore/Presets/PresetStore.swift` |
| Preset listing preserves unreadable records | `swift test --filter PresetStoreTests.test_listPresets` |
| Recovery regressions | `rg -n "preservesUnreadableFiles\|doesNotRemoveUnreadableDirectory" Tests/FramerCoreTests/PresetStoreTests.swift` |
| Built-in preset count/names | `grep -n '("' Sources/FramerCore/Presets/PresetStore.swift \| grep ProcessingConfig` |
| YAML field count (165) | `awk 'NR>=27 && /^    }/{print NR; exit}' Sources/FramerCore/Presets/YAMLConfig.swift` then `sed -n '27,<end>p' Sources/FramerCore/Presets/YAMLConfig.swift \| grep -c "var "` |
| Config discovery chain | `grep -n -A 25 "func loadDefault" Sources/FramerCore/Presets/YAMLConfig.swift` |
| CLI subcommands + flags | `swift run framer --help && swift run framer process --help` |
| Legacy decode branches intact | `grep -n "sharpness" Sources/FramerCore/Models/CompositionLayer.swift Sources/FramerCore/Presets/YAMLConfig.swift` |
| Golden/behavior tests green | `swift test --filter EffectGPUGoldenTests` ; `swift test --filter EffectGPUBehaviorTests` (self-skip without a Metal device) |
| Matrix doc still stale | `grep -n "none of the bucket shaders\|Hidden from picker" docs/gpu-effects-parameter-matrix.md` |
