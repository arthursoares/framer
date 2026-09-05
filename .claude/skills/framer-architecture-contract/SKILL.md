---
name: framer-architecture-contract
description: Load when you need the mental model of the framer codebase before changing anything structural — adding/reordering composition layers, touching FrameProcessor/BorderRenderer/ShaderRenderer/LayerCompositor, adding or modifying GPU effects or Metal shaders, changing Codable models or preset schemas, refactoring AppState/PreviewViewModel, or deciding whether the CPU fallback path can be removed. Also load when asking "why is it built this way", "what invariant am I about to break", "is X a known weak point", or "is this an open architectural question".
---

# framer Architecture Contract

The load-bearing design decisions of this repo, the invariants that must hold, the
known-weak points, and the open questions a maintainer has not yet decided. Read this
BEFORE structural changes. Facts below verified against the working tree at commit
`48d85a5` on 2026-07-09 unless noted.

**Jargon, defined once:**
- **Layer** — one element of the composition stack (a border, a dither pass, a caption...).
- **GPU effect / bucket** — a `.gpuEffect` layer routed to one of 4 "bucket" renderers
  (textCell / printSampling / edgeField / glitch), each hosting several visual variants.
- **Metal** — Apple's GPU API. **MSL** — Metal Shading Language (`.metal` files).
- **Parity** — the CPU and GPU implementations of the same effect producing equivalent
  pixels within test tolerances.
- **WYSIWYG** — the downscaled preview must look like the full-resolution export.

## When NOT to use this skill

| You actually want... | Go to sibling |
|---|---|
| Metal mechanics: shader loading, uniforms, texture upload, add-a-GPU-effect steps | framer-metal-pipeline-reference |
| Color/dither/pixel-sort/blend math and theory | framer-image-processing-reference |
| Parameter catalog, YAML/JSON schemas, CLI flags, add-a-parameter checklist | framer-config-and-flags |
| Full incident stories behind the weak points listed here | framer-failure-archaeology |
| Which docs are stale and why | framer-docs-and-writing |
| Test estate, snapshot-hash discipline | framer-validation-and-qa |
| Fixing the broken xcodebuild test tier | framer-campaign-restore-validation |
| House rules on merges, commits, PRs | framer-change-control |

## The one mental model

Everything in this repo is a view over one data structure:

```
CompositionLayer (12-case enum)          Sources/FramerCore/Models/CompositionLayer.swift:1656
        │  carried as
ProcessingConfig.layers: [CompositionLayer]?   Sources/FramerCore/Models/ProcessingConfig.swift:204
        │  consumed by
FrameProcessor (public actor)            Sources/FramerCore/Processing/FrameProcessor.swift:7
        │  which folds each layer, in array order, over the current CGImage:
        │    .gpuEffect  → GPUEffectsPlatform.dispatchRenderPreview → bucket renderer
        │    everything else → BorderRenderer.applyLayers            Sources/FramerCore/Processing/BorderRenderer.swift:51
        ▼
final CGImage → MetadataWriter (export) or SwiftUI preview
```

The 12 cases (CompositionLayer.swift:1657-1668): `border`, `padding`, `canvas`,
`resize`, `overlay`, `orientation`, `caption`, `dither`, `aspectRatio`, `lut`,
`shader`, `gpuEffect` — each carrying its own params struct.

The macOS app (`Sources/FramerApp`, built as module **`Framer`** — see Weak Points),
the iOS app (`Sources/FramerMobile`), the CLI (`Sources/FramerCLI`), JSON presets, and
YAML configs are all just editors/serializers of that one array. If you understand the
array and the fold, you understand the pipeline.

WHY: one canonical representation means the CLI, both apps, and every preset format
render identically for free. Any feature that bypasses `ProcessingConfig.layers` breaks
that guarantee — don't.

## Invariants (must hold; each has a WHY)

### I1 — Layer order IS render semantics
`FrameProcessor.applyConfiguredLayers` (FrameProcessor.swift:154-205) iterates
`layers` in array order; each layer's output is the next layer's input. Disabled layers
are skipped (`guard layer.isEnabled` in BorderRenderer.swift:64). Reordering the array
reorders the render. There is no dependency graph, no z-index, no "smart" ordering.
- WHY: presets serialize the array verbatim, so serialized order == visual result.
- Consequence: never sort, dedupe, or "normalize" a layers array in passing. UI
  drag-reorder is a semantic edit, not cosmetic.
- Related contract: `LayerCompositor.compose(base:over:mode:opacity:)`
  (Sources/FramerCore/Processing/LayerCompositor.swift:35-56) is how visual layers
  land back on the stack — it throws `dimensionMismatch` unless base and over have
  identical pixel dimensions, never modifies the alpha channel, and short-circuits to
  return `over` unchanged for `.normal` mode at opacity >= 1.0. New effect layers must
  return an image of the same dimensions as their input or composition throws.

### I2 — WYSIWYG preview vs export
Scale-sensitive layers (dither, LUT, shader) sample patterns at a density derived from
image size. To make the 1200–3000 px preview match the full-res export, both paths pass
a `previewBaseDimension` down (preview: FrameProcessor.swift:40-57; export:
FrameProcessor.swift:88-99 computes the same `previewMaxDimension` the preview used).

Special case: if the stack contains any `.gpuEffect`, the preview runs at FULL
resolution and only downscales at the end (FrameProcessor.swift:32-36 and 62-64),
because bucket shaders are resolution-dependent. Scale-sensitive CPU layers in the same
stack then receive `previewMax` as their base (the `layerPreviewBase` plumbing,
FrameProcessor.swift:47) so their pattern density still matches export.

- WHY: the incident class this prevents is "preview looked great, export came out with
  different grain" — see framer-failure-archaeology.
- RULE: any NEW scale-sensitive layer must accept and honor `previewBaseDimension`,
  and if it mutates canvas size it must be simulated in
  `FrameProcessor.previewMaxDimension` (FrameProcessor.swift:192 onward).

### I3 — Effects are GPU-only; regression anchors to frozen goldens (CPU path RETIRED 2026-07-09)
Decided and executed 2026-07-09 per docs/adr/2026-07-09-retire-cpu-effect-path.md
(maintainer direction: "we will always have Metal available"; PR #12's bucket
retirement was the first step). The redundant CPU twins (~2,900 lines) are gone;
**a Metal failure now throws `MetalEffectError` to the caller — failing loudly is
the contract; there is no silent visually-different fallback.**

The dispatch contract:
- `ShaderRenderer.apply` (Sources/FramerCore/Processing/ShaderRenderer.swift) calls
  the Metal renderers directly; `gpuOrCPU` and the CPU style implementations
  (incl. ShaderASCIIRenderer, ShaderPixelSortRenderer) were deleted.
- `DitherRenderer.apply` dispatches **by algorithm**: `.riemersma` → the kept CPU
  implementation (inherently serial Hilbert-curve error history, no GPU port — a
  CAPABILITY, not a fallback); every other algorithm → `DitherGPURenderer`, errors
  propagating. The degraded mono cmykHalftone CPU fallback was deleted.
- Bucket renderers (since PR #12): Glitch/EdgeField are GPU-only and throw;
  TextCell/PrintSampling route to kept CPU loops only for legacy hidden variants
  (`.ascii`, `.halftone`, `.dithering` bucket forms) with no GPU entry — selected by
  variant, not by catch.
- Exception, deliberately untouched: the LUT stack keeps nil-return fallback to
  `applyCPU` (Sources/FramerCore/Processing/LUTRenderer.swift:41-57) — it is the
  oracle for the LUT tests and the `benchmark lut` CPU baseline
  (BENCHMARK-BASELINE in the ADR's classification).

Verification contract (replaces CPU-vs-GPU parity):
- Tests/FramerCoreTests/EffectGPUGoldenTests.swift — 13 tests compare GPU renders
  against frozen PNGs in Tests/FramerCoreTests/Resources/GoldenReferences/ with the
  per-effect tolerances inherited from the retired parity suite. Regeneration is
  env-gated (command in the file header) and follows the snapshot-hash discipline:
  never blind-refresh; land in the same commit as the cause; explain the pixel shift.
- Tests/FramerCoreTests/EffectGPUBehaviorTests.swift (renamed from
  EffectGPUParityTests) — GPU invariants (binary-BW, palette membership,
  quantization grid), flag wiring, and the Riemersma explicit-dispatch routing test.
- Metal-less hosts skip the effect render suites entirely (skip arithmetic owned by
  framer-validation-and-qa) and cannot render `.shader`/`.dither`/`.gpuEffect`
  layers — an accepted cost recorded in the ADR.

Historical context: while both paths existed, CPU/GPU divergence was the top
recurring bug class (canonical incident: pixel-sort divergence, commit `f21a6fe` —
full story in framer-failure-archaeology). The lockstep rule ("shared constants and
formulas change in both paths in the same commit") died with the CPU path; its
successor is the golden-refresh rule above.

### I4 — BOTH shader-loading paths must keep working
`MetalEffectLibrary.init` (Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift:53-120):
1. **Xcode builds** (Framer.app, FramerMobile): SwiftPM's `.process` rule compiles a
   `default.metallib` into `Bundle.module`; tried first via `makeDefaultLibrary`.
2. **`swift build` / `swift test` / FramerCLI**: SwiftPM 5.10 copies `.metal` files
   verbatim (no metallib). Fallback: concatenate `ShaderCommon.h` + every `.metal`
   text resource (stripping each file's `#include "ShaderCommon.h"` line) and
   `makeLibrary(source:)` at runtime.

RULE for new `.metal` files (mechanics in framer-metal-pipeline-reference):
- add a per-file `.process(...)` entry in Package.swift (the directory form
  `.process("Effects/Metal")` silently copies instead of compiling — documented gotcha
  in Package.swift comments), AND
- keep the file concatenation-safe: no symbols duplicated across `.metal` files, no
  reliance on include order beyond ShaderCommon.h. `_EffectTemplate.metal` must stay
  in Package.swift `exclude:` or the combined runtime compile breaks.

### I5 — Uniform mirroring discipline
Swift uniform structs mirror MSL structs field-for-field with explicit `_pad` fields.
The rule is written at the top of Sources/FramerCore/Effects/GPU/SharedUniforms.swift:
*"When you change the C header, change the Swift mirror in the same patch."* Numeric
constants are also duplicated: `GlitchGPURenderer.maxSpanWalk = 1024`
(Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift:23) must equal
`PIXEL_SORT_MAX_WALK` in Sources/FramerCore/Effects/Metal/PixelSort.metal:31.
Layout drift symptom (garbled colors / "argument has a length" validation error) and
the `uniformBytes()` stride rule: framer-metal-pipeline-reference.

### I6 — Serialization back-compat: legacy decode branches are permanent
The house convention for every params struct: hand-written `init(from:)` using
`decodeIfPresent ?? default`, and `encode` skips default values. Old presets must load
forever. Canonical example: `KuwaharaShaderParams` (CompositionLayer.swift:1411-1449)
still decodes the legacy `sharpness` field (0..8, inverted semantics) and maps it via
`softness = 1 - sharpness/8`; it never encodes `sharpness` back. Never delete such a
branch — there is no migration step anywhere; the decode branch IS the migration.
Note also `ProcessingConfig.init(from:)` decodes `layers` with `try?`
(ProcessingConfig.swift:260) — a corrupt layers array degrades to nil (legacy config
path) rather than throwing. Field-by-field schema detail: framer-config-and-flags.

## Two separate Metal stacks (deliberate isolation, unification unplanned)

| | Effects stack | LUT stack |
|---|---|---|
| Kind | fragment shaders, fullscreen triangle | compute kernel |
| Source | 12 active `.metal` files in Sources/FramerCore/Effects/Metal/ (+ excluded `_EffectTemplate.metal`, `ShaderCommon.h`) | shader embedded as a Swift string (LUTMetalRenderer.swift:13), runtime-compiled (line 92) |
| Orchestration | MetalEffectLibrary + MetalRenderPass | LUTMetalRenderer's private `MetalContext` with its own device/queue/caches (LUTMetalRenderer.swift:264-273) |
| Fallback style | throw `MetalEffectError` → CPU | return nil → CPU |

They share no code. This isolation is the current design, not an accident — the LUT
stack has its own preview-input caching semantics — but nobody has ruled on unifying
them (see Open Questions). Don't "helpfully" merge them in passing.

## Persistence: three formats, one back-compat rule

1. **JSON presets** — `Codable` `Preset` files at
   `~/Library/Application Support/Framer/presets/<UUID>.json`
   (Sources/FramerCore/Presets/PresetStore.swift:7-11).
2. **YAML presets/configs** — flat snake_case schema kept compatible with the
   predecessor Go CLI ("compatible with the Go CLI schema",
   Sources/FramerCore/Presets/YAMLConfig.swift:6). YAML presets of the same
   deterministic (name-derived) UUID are overridden by JSON presets
   (PresetStore.swift:44-58).
3. **CLI config discovery chain** (YAMLConfig.swift:281-305):
   `--config path` → `--preset <name>` (Application Support presets dir) →
   `./.framer.yaml` → `~/.config/framer/default.yaml` (macOS only) → built-in default.

The back-compat rule I6 applies to all three. Schema catalog: framer-config-and-flags.

## App state model (macOS)

- `AppState` — one `@MainActor @Observable` class
  (Sources/FramerApp/App/AppState.swift:4-6, 272 lines): library, selection, config,
  presets, export queue. Export concurrency is capped by
  `recommendedExportConcurrency` = `min(itemCount, min(6, max(1, cpuCount - 1)))`
  (AppState.swift:238-246) — leave a core for the UI, never more than 6.
- `PreviewViewModel` — `@MainActor @Observable`; 150 ms debounce + a generation
  counter so stale renders are dropped
  (Sources/FramerApp/Editor/PreviewViewModel.swift:47-67).
- `PresetThumbnailCache` — extracted from AppState as a dedicated `@Observable` type
  specifically to narrow observation scope: when it was a `var` on AppState, every
  thumbnail write during a background render invalidated EVERY view tracking any
  AppState property (rationale documented in
  Sources/FramerApp/Presets/PresetThumbnailCache.swift:4-14). This is the house
  pattern for hot-write state: give it its own `@Observable` object.

**Module naming trap:** the macOS app target/module is **`Framer`** (project.yml
`targets: Framer:` with `sources: Sources/FramerApp`), NOT `FramerApp`. Xcode-only
tests do `@testable import Framer` (Tests/FramerAppTests/*.swift). Writing
`import FramerApp` fails.

## Known weak points — stated plainly

| Weak point | Evidence (verified 2026-07-09) | Risk |
|---|---|---|
| Layer editors are split by layer (updated 2026-09-05) | macOS `LayerListSection.swift` is a coordinator with controls under `Editor/LayerControls/`; iOS `LayerDetailView.swift` coordinates controls under `Layers/Controls/` | Add controls to their owning files. The large GPU/shader structs remain intact; sidebar grammar and snapshot rules still apply. |
| PresetStore skips unreadable presets but preserves their files (updated 2026-09-05) | PresetStore.list() has no deletion path; PresetStoreTests verifies original bytes survive malformed/unsupported records and read failures | A Codable regression still hides valid presets. Keep legacy decoding and never restore automatic deletion. |
| LUTMetalRenderer caches grow unboundedly | input/output textures keyed by (width,height), LUT textures keyed by full-data hash; no eviction anywhere in MetalContext (LUTMetalRenderer.swift:269-330; grep for `removeAll`/`evict` finds none) | Acceptable only because sizes are few in practice; a LUT-browsing feature would leak GPU memory |
| AppState never got its planned Library/Editor split | Plan: docs/plans/2026-03-08-performance-optimizations.md "Fix 4: Split AppState into Library vs Editor"; reality: single `AppState` class, no `LibraryState`/`EditorState` symbols exist | Slider drags still invalidate library views and vice versa; the PresetThumbnailCache extraction was a partial mitigation, the full split is still open |
| `LUTProvider.bundledLUTs()` executable-relative lookup appears dead | LUTProvider.swift:296-299 looks for `<executable dir>/assets/luts`; repo has `assets/luts/` (4 files) but neither project.yml nor Package.swift bundles it, and SPM puts binaries in `.build/debug/` with no assets sibling | Bundled LUTs are invisible in every standard run context; user-imported LUTs (Application Support) are the working path. Likely a Go-CLI-era leftover — confirm intent before "fixing" |
| Two `Package.resolved` files must stay aligned (updated 2026-09-05) | Root and Xcode workspace both pin ArgumentParser 1.7.1 and Yams 5.4.0 at identical revisions | Compare pin arrays after resolving dependencies; resolver-specific origin hashes may differ |
| App tests remain Xcode-only (updated 2026-09-05) | `Framer` runs 65 macOS tests and `FramerMobile` runs 7 iOS tests via project.yml; both passed locally with signing disabled | `swift test` alone does not validate app changes. Run the applicable Xcode target. |
| Docs of record are partially stale (e.g. docs/gpu-effects-parameter-matrix.md predates later shader wiring; README.md predates several layers; CLAUDE.md was rewritten 2026-07-09 to route to this library) | staleness ledger: framer-docs-and-writing | Do not treat prose docs as ground truth for shader capabilities; `GPUEffectKind` capability flags (Sources/FramerCore/Effects/Models/GPUEffectKind.swift:81-124) + the `.metal` sources are ground truth |

## Open architectural questions (undecided — do not resolve unilaterally)

| Question | Current state | Where the decision work lives |
|---|---|---|
| ~~Retire the CPU effect path?~~ | **RESOLVED 2026-07-09: retired.** ADR at docs/adr/2026-07-09-retire-cpu-effect-path.md; new contract recorded in I3. Kept by design: Riemersma (capability), legacy hidden bucket variants (capability), LUT `applyCPU` (benchmark baseline + oracle) | Done — framer-research-frontier problem 5 closed by the ADR |
| Video support someday? | Nothing in code; pipeline is single-CGImage in/out. Any move here would stress the actor model and the synchronous Metal render pass | framer-research-frontier |
| Unify the two Metal stacks? | Isolation is deliberate today; unification unplanned. Would need to reconcile throw-vs-nil fallback styles and LUT preview caching | framer-metal-pipeline-reference owns the mechanics either way |
| Snapshot baselines are single-machine | FramerAppTests SHA-256 baselines were recorded on one Mac; cross-machine font/AA rendering drift is untested. Never blind-refresh hashes (maintainer ruling — refresh mechanics owned by framer-validation-and-qa) | framer-campaign-restore-validation's P3 gate drives the decision; the resulting rule gets recorded in framer-validation-and-qa |
| Go-CLI YAML compat still a live requirement? | Compat is maintained (YAMLConfig.swift:6) but nobody has confirmed users with old `.framer.yaml` files still exist | framer-config-and-flags |

## Provenance and maintenance

Everything above was verified 2026-07-09 against the working tree at commit `48d85a5`
(`swift test` run same day: "Executed 268 tests, with 0 failures"; re-run after the
2026-07-09 PR #11/#12 merges at `f2c9521`: "Executed 273 tests, with 0 failures").
Re-verify before
trusting, especially after refactors:

```bash
# I-model: 12-case enum + layers array + actor + fold
grep -n "public enum CompositionLayer" Sources/FramerCore/Models/CompositionLayer.swift
sed -n '1657,1668p' Sources/FramerCore/Models/CompositionLayer.swift   # the 12 cases
grep -n "public var layers" Sources/FramerCore/Models/ProcessingConfig.swift
grep -n "public actor FrameProcessor" Sources/FramerCore/Processing/FrameProcessor.swift
grep -n "public static func applyLayers" Sources/FramerCore/Processing/BorderRenderer.swift

# I2: WYSIWYG plumbing
grep -n "layerPreviewBase\|containsGPUEffect" Sources/FramerCore/Processing/FrameProcessor.swift

# I3: GPU-only dispatch + golden anchoring
grep -c "gpuOrCPU" Sources/FramerCore/Processing/ShaderRenderer.swift        # expect 0
grep -n "enum MetalEffectError" Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift
grep -n "riemersma" Sources/FramerCore/Processing/DitherRenderer.swift | head -3   # algorithm dispatch
ls Tests/FramerCoreTests/Resources/GoldenReferences | wc -l                 # expect 16
swift test --filter EffectGPUGoldenTests                                    # expect 13 passed (Metal host)
swift test --filter EffectGPUBehaviorTests                                  # expect 14 passed (Metal host)
ls Sources/FramerCore/Processing/ShaderASCIIRenderer.swift 2>&1             # expect: no such file

# I4/I5: dual loading + mirrored constants
grep -n "makeDefaultLibrary\|makeLibrary(source" Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift
grep -rn "maxSpanWalk" Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift Sources/FramerCore/Effects/Metal/PixelSort.metal

# I6: legacy decode branch example
grep -n "sharpness" Sources/FramerCore/Models/CompositionLayer.swift | head

# Persistence
grep -n "Framer/presets" Sources/FramerCore/Presets/PresetStore.swift
grep -n "loadDefault" Sources/FramerCore/Presets/YAMLConfig.swift

# App state + module name
grep -n "@Observable" Sources/FramerApp/App/AppState.swift Sources/FramerApp/Presets/PresetThumbnailCache.swift
grep -n "recommendedExportConcurrency" Sources/FramerApp/App/AppState.swift
grep -n "@testable import Framer" Tests/FramerAppTests/LayerPanelRowLayoutTests.swift

# Weak points
wc -l Sources/FramerApp/Editor/LayerListSection.swift Sources/FramerMobile/Layers/LayerDetailView.swift
git log --oneline --grep=fix -- Sources/FramerApp/Editor/LayerListSection.swift | wc -l   # 42
grep -n "removeItem" Sources/FramerCore/Presets/PresetStore.swift
grep -n "assets/luts" Sources/FramerCore/Processing/LUTProvider.swift
python3 -c 'import json; a=json.load(open("Package.resolved")); b=json.load(open("Framer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")); assert a["pins"] == b["pins"], "Dependency pins differ"'
grep -n "FramerAppTests" Package.swift || echo "still Xcode-only"
grep -n "userFacingCases" Sources/FramerCore/Effects/Models/GPUEffectKind.swift
```

If any command's output disagrees with this skill, the code wins — update the skill.
