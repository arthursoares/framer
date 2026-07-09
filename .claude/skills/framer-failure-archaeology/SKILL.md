---
name: framer-failure-archaeology
description: >
  Load this when you suspect a bug has been fought before, when a fix attempt feels
  familiar, when you are about to "simplify" or delete something odd-looking, or when
  you hit any of these symptoms: CPU and GPU render differently for the same preset;
  "CGBitmapContextCreate: unsupported parameter combination" logs; a preset picker's
  "Custom" option snapping back; sliders that do nothing; snapshot tests breaking after
  a "harmless" refactor; frame overlays darkening the photo; wondering why there are no
  E2E/UI tests, why feature/video-support is parked, or why bucket-system history is
  missing. This is the chronicle of every settled battle — symptom, root cause,
  evidence, status — so nobody re-fights one.
---

# Framer Failure Archaeology

The full history of every major investigation, dead end, rejected fix, revert, and
parked branch in this repo, verified against git and the working tree
(as of 2026-07-09, commit `48d85a5`). Each saga is recorded as
**SYMPTOM → ROOT CAUSE → EVIDENCE → STATUS**.

Rule of use: before fixing a bug or deleting "weird" code, scan the index below.
If your symptom matches a saga, read it — the losing moves are already documented.

**When NOT to use this skill:**

- You need a live triage procedure for a symptom happening right now → `framer-debugging-playbook`.
- You need Metal mechanics (shader loading, uniforms, texture upload) → `framer-metal-pipeline-reference`.
- You need the theory (color spaces, dithering, blend math) → `framer-image-processing-reference`.
- You want to revive E2E testing (executable campaign) → `framer-campaign-restore-validation`.
- You need parameter/flag catalogs → `framer-config-and-flags`.
- You need the stale-docs ledger → `framer-docs-and-writing`.
- You need design invariants and open architectural questions → `framer-architecture-contract`.

## Index

| # | Saga | One-line lesson | Status | Anchor |
|---|------|-----------------|--------|--------|
| 1 | E2E testing died twice | Runner blockers + divergence killed PR #6; salvage branch is the revival spec | OPEN WOUND | [§1](#1-e2e-testing-died-twice) |
| 2 | CGBitmapContext, three attempts in one day | Never inherit source `bitmapInfo`; always canonical premultipliedLast contexts | FIXED | [§2](#2-the-cgbitmapcontext-saga) |
| 3 | CPU/GPU parity incident list | Every shader port shipped 1–3 parity bugs; parity is mechanical reality, not doctrine | FIXED (recurring class) | [§3](#3-cpugpu-parity-incidents) |
| 4 | LUT Metal same-day flip-flop | GPU features ship behind a working CPU path; toggle off, don't block | FIXED | [§4](#4-lut-metal-flip-flop) |
| 5 | SPM does not compile .metal | `swift build` silently ships no metallib; runtime source compile saved it | FIXED (standing invariant) | [§5](#5-spm-does-not-compile-metal) |
| 6 | ASCII stub renderer | Full end-to-end wiring can mask a placeholder renderer | FIXED | [§6](#6-the-ascii-stub-renderer) |
| 7 | Custom-palette snap-back, twice (+1 edge case) | Derived-selection pickers snap back if the Custom seed matches a preset | FIXED (pattern still live) | [§7](#7-custom-palette-snap-back) |
| 8 | Result-builder "simplification" reverted | `_ConditionalContent` defeats `== EmptyView`; the result-builders stay | INTENTIONAL DESIGN | [§8](#8-the-result-builder-revert) |
| 9 | renderTasks UUID-keyed dictionary leak | A dict keyed by fresh `UUID()` per call cancels nothing | FIXED | [§9](#9-rendertasks-uuid-leak) |
| 10 | Stale-index crash in layer bindings | Bindings must capture `layer.id`, never an index | FIXED | [§10](#10-stale-index-crash) |
| 11 | Dead-controls saga | UI ↔ shader-uniform drift in both directions; capability flags are the guard | MANAGED | [§11](#11-the-dead-controls-saga) |
| 12 | Frame-overlay darkening | JPEG mid-gray deadband + real-alpha gating in the luminance mask | FIXED | [§12](#12-frame-overlay-darkening) |
| 13 | Priority inversion (PR #11) | `Task {}` from @MainActor escalates actors to User-initiated QoS over CG's Default workers | OPEN PR | [§13](#13-priority-inversion) |
| 14 | Color-space + serialization bugs (PR #12) | Untagged CGColor shifted every color; enum-convention collisions; missing YAML keys | OPEN PR | [§14](#14-pr-12-color-and-serialization-bugs) |
| 15 | feature/video-support parked | 19-commit AVAssetWriter pipeline ends at a `wip:` commit; start there, not from scratch | PARKED | [§15](#15-parked-video-support) |
| 16 | Bucket history destroyed by cherry-pick | `feat/grainrad-gpu-effects` deleted after ffeffe1; matrix doc survives but is stale | ACCEPTED LOSS | [§16](#16-destroyed-history-and-dead-paper) |
| 17 | Build broken on main (c515147) | Commits were not always build-verified | FIXED (cautionary) | [§17](#17-the-build-break-pair) |

---

## 1. E2E testing died twice

**SYMPTOM.** Main has zero E2E/UI tests. `Tests/` contains only FramerCoreTests,
FramerCLITests, FramerAppTests.

**ROOT CAUSE (death #1 — PR #6, closed unmerged).** PR #6
"test: add end-to-end testing foundation" (branch `test/e2e-foundation`, 8 commits,
opened 2026-04-12, closed 2026-04-17) built CLI E2E coverage, launch-driven bootstrap
hooks for both apps, and UI smoke-test targets. It died on two machine blockers,
recorded verbatim in the PR body:

- macOS UI test runner: `Authentication canceled. System authentication is running.`
- iOS UI test runner: simulator preflight/launch errors for `FramerMobileUITests.xctrunner`.
- CLI E2E tests DID pass in-package (`swift test`, 225 tests at the time).

While it sat blocked, PR #7 (GPU-effects migration, merged 2026-04-14) rewrote the code
underneath it and the branch diverged unrecoverably.

**ROOT CAUSE (death #2 — the salvage).** Branch `salvage/e2e-test-scaffolding`
(single commit `aa60b94`, 2026-04-17) imported the test bundles, fixtures, and
`E2ETestConfiguration` sources — but its commit message explicitly lists what was
NOT landed: Package.swift / project.yml wiring for the new test bundles; the
AppState / ExportBar / PresetPreviewCard / LayerDetailView hooks the test-config type
drives; and UI-test scheme additions in project.pbxproj. Its own words: "compiles but
the new test code is not runnable until the wiring is restored." It was never merged.

**EVIDENCE.** PR #6 (CLOSED); `git show -s aa60b94`; branch `pr6-check` preserves the
full original 8 commits (verify: `git log --oneline origin/main..origin/pr6-check`,
8 commits from `f87c53a` fixtures to `c980a1f` XcodeGen wiring); as of 2026-07-09,
`pr6-check` is 8 ahead / 10 behind and `salvage/e2e-test-scaffolding` is 1 ahead / 10 behind.

**STATUS: OPEN WOUND.** The revival spec is the salvage branch plus aa60b94's
"Not landed" checklist. The executable revival plan lives in
`framer-campaign-restore-validation`. Do not start E2E from scratch — the fixtures,
bootstrap hooks, and accessibility identifiers already exist on `pr6-check`.

## 2. The CGBitmapContext saga

Three fix attempts in one day (2026-04-14) for one symptom class. Read all three
before touching CGContext creation anywhere.

**SYMPTOM.** "Image isn't loading correctly" / wrong colors after loading certain
PNG/HEIC/JPEG files; console spam:
`CGBitmapContextCreate: unsupported parameter combination`.

**ROOT CAUSE, in three layers:**

1. `f0de444` — non-premultiplied `.alphaLast` images break MTKTextureLoader's internal
   CGBitmapContext; normalize to premultipliedLast before upload. Necessary, not sufficient.
2. `35c7886` — the normalization check compared only alpha bits, so decoder-added flags
   like `kCGImagePixelFormatPacked` slipped through; tightened to full-`bitmapInfo`
   equality. Still not sufficient.
3. `6635746` "the real culprit" — **three other sites** created CGContexts with the
   source image's `bitmapInfo` copied verbatim: the downscale helpers in both
   `Sources/FramerApp/Editor/PreviewViewModel.swift` and
   `Sources/FramerMobile/Preview/PreviewViewModel.swift`, and
   `Sources/FramerCore/Processing/BorderRenderer.swift` `createContext`. When ImageIO
   decoded a source carrying unsupported flag combinations, CGContextCreate rejected
   them and the surrounding guard **silently fell back to the un-downscaled original**.

**EVIDENCE.** `git show 6635746` (full write-up in the commit body); all three commits
dated 2026-04-14.

**STATUS: FIXED.** The standing rule, quoted from the final fix: never inherit source
`bitmapInfo`. Always allocate canonical contexts —
`bitsPerComponent: 8, bytesPerRow: w*4, DeviceRGB, premultipliedLast` — and let
`ctx.draw(src, in:)` do the format conversion. Note: synthetic test fixtures for the
packed-flag combos are impossible (`CGImage.init` rejects them); only real ImageIO
decodes reproduce the bug, so this rule is enforced by convention, not by test.

## 3. CPU/GPU parity incidents

This is the recurring failure mode of the entire GPU program: **every shader port has
historically shipped 1–3 parity bugs**. "Parity" = the CPU fallback and the GPU shader
had to produce the same output for the same parameters, because `ShaderRenderer.gpuOrCPU`
fell back to CPU on `MetalEffectError` and users silently got whichever path ran.

HISTORICAL CONTEXT ONLY as of 2026-07-09: the CPU effect path was RETIRED
(docs/adr/2026-07-09-retire-cpu-effect-path.md) — `gpuOrCPU` and the CPU twins are gone,
errors propagate, and regression is anchored to EffectGPUGoldenTests' frozen goldens
(+ EffectGPUBehaviorTests invariants). The incidents below remain instructive: they are
why the divergence class was worth eliminating.

The complete incident list, each verified via `git show -s <hash>`:

| Commit | Date | Divergence class | What was wrong |
|--------|------|------------------|----------------|
| `d61f9d9` | 2026-04-13 | Geometry | Bucket-system effects rendered upside-down — a redundant Y flip on top of the vertex shader's built-in flip. |
| `035116a` | 2026-04-13 | Operation order | ColorGrade GPU blurred then graded; CPU grades then blurs. Order matters. |
| `5e20c5a` | 2026-04-13 | Kernel edges | ColorGrade box-blur didn't clip the kernel at image borders (Codex-review follow-up). |
| `e82823e` | 2026-04-13 | Algorithm fidelity | ASCII GPU shader was not a faithful port of the CPU algorithm; rewritten until `testASCIIParity` went green. |
| `ec59a5d` | 2026-04-13 | Pixel-grid phase | CRT + Halftone sampled at fragment centers (`in.uv`), a half-texel phase shift vs CPU's integer-pixel loop; mean parity delta was 32/255 before pinning to `floor(uv*res)` (comment preserved at `Sources/FramerCore/Effects/Metal/Halftone.metal:60-64`). Rule: any shader ported from a CPU integer-pixel loop must pin uv to the integer grid. |
| `a757e67` | 2026-04-14 | Gamma + contract | Dither compared thresholds in nonlinear sRGB and inverted the UI's "higher = brighter" threshold contract — re-breaking the contract originally established by `3070fba` (2026-03-08). Contracts must be written down or they get re-broken. |
| `2a2ecba` | 2026-04-14 | Degenerate output | Several dither algorithms produced **byte-identical** output: all IGN (Interleaved Gradient Noise) approximations sampled the noise field at the same position, differing only by amplitude. Fixed with per-algorithm spatial phase offsets. |
| `761fae6` | 2026-04-16 | Scoring math | CPU pixel-sort `pixelScore`: `.brightness` returned Rec.709 luminance (identical to `.luminance`) instead of `max(r,g,b)`; `.hue` returned unnormalized HSV sectors in `[-1,6)` so blue-dominant pixels never crossed any positive threshold and were left unsorted. |
| `f21a6fe` | 2026-04-16 | Parameter semantics | Pixel-sort `amount`: CPU used it as sort-rank scaling (amount=0 rendered the darkest 20% of every span!) while the GPU used it as a `mix()` blend factor. CPU rewritten to match shader semantics; also set `usesCommonAdjustments = false` for `.pixelSort` since neither path consumes the common block. |

**Accepted divergences (do not "fix" these):**

- `cmykHalftone`: CPU deliberately degrades to a monochrome 6×6 clustered-dot screen;
  true per-channel rotated CMYK screens are GPU-only. Documented as intentional in
  `docs/gpu-migration-mac-resume.md` ("§3 CMYK halftone parity (intentional divergence)").
  No parity test exists for it, by design.
- Pixel-sort long streaks: the GPU samples at most 24 positions per span
  (`PIXEL_SORT_SAMPLE_COUNT = 24`, `Sources/FramerCore/Effects/Metal/PixelSort.metal:30`),
  so spans longer than 24 look coarser on GPU than CPU. Accepted approximation.

**STATUS:** each listed incident FIXED; the *class* recurs with every new port. When
porting an effect, treat CPU-fallback parity as part of the definition of done and add
a parity test with a mean-delta tolerance (see `framer-validation-and-qa` for test
conventions and `framer-metal-pipeline-reference` for the porting checklist).

## 4. LUT Metal flip-flop

**SYMPTOM.** Within one day (2026-04-01, inside the LUT-layer work that merged as
PR #4 on 2026-04-02), Metal GPU LUT rendering was enabled, disabled, and re-enabled.

**SEQUENCE (all verified):** `2576b97` "feat: re-enable Metal GPU LUT rendering" →
`d47970e` "fix: disable Metal GPU — shader returning incorrect values" →
`b2e7698` "fix: harden LUT CPU pipeline" → `e0f31fe` "feat: enable metal LUT parity".

**STATUS: FIXED.** The lesson is process, not code: GPU features in this repo ship
behind a working CPU path and get *toggled off* when wrong, rather than blocking the
feature. If you see a GPU path disabled in history, check whether a later commit
re-enabled it before assuming it's dead.

## 5. SPM does not compile .metal

**SYMPTOM.** Under `swift build` / `swift test`, every GPU effect silently renders via
the CPU fallback (all effects look subtly different and slower at once).

**ROOT CAUSE.** SPM 5.10 does not compile `.metal` resources into a metallib; the
files ship verbatim and `makeDefaultLibrary(bundle:)` finds nothing.

**EVIDENCE.** `5492a67` "fix: actually compile Metal shaders at runtime (CLI/tests now
run GPU)" and `90e7336` "fix: MetalEffectLibrary — try precompiled metallib first,
source fallback second" (both 2026-04-13).

**STATUS: FIXED, but a standing invariant.** The loader tries a precompiled metallib
(Xcode builds), then concatenates shader source and compiles at runtime (SPM builds).
The full mechanics — per-file `.process` entries in Package.swift, the
`_EffectTemplate.metal` exclusion, uniform stride rules — are owned by
`framer-metal-pipeline-reference`. What belongs *here*: a passing `swift test` does
not prove the Xcode metallib path works, and "all effects look CPU-rendered at once"
means the library failed to load, not that ten shaders broke simultaneously.

## 6. The ASCII stub renderer

**SYMPTOM (historic).** "ASCII is broken" — the bucket ASCII effect rendered
placeholder horizontal bars instead of glyphs.

**ROOT CAUSE.** The renderer was a *fully-wired stub*: dispatch, parameters, YAML
round-trip, and tests all existed end-to-end, but `paintASCII()` painted bars. A real
CPU ASCII implementation existed elsewhere (`ShaderASCIIRenderer.swift`) and simply
wasn't connected.

**EVIDENCE.** `docs/gpu-migration-plan.md` line ~197 documents the stub and its
location at the time.

**STATUS: FIXED** by the GPU migration (PR #7). Cautionary tale: end-to-end wiring and
green tests can mask a placeholder renderer. When output looks like a placeholder,
read the render function itself before debugging the wiring around it.

## 7. Custom-palette snap-back

The same bug class shipped **twice in two days**, plus an edge-case third strike.

**SYMPTOM.** User picks "Custom" in a preset dropdown (ASCII characters, dither
palette); the picker silently snaps back to a named preset. A silent no-op.

**ROOT CAUSE (pattern).** Picker selection is *derived on every render* from the
stored values via a `matching()` function. If the seed data used when the user picks
"Custom" equals a canonical preset's data, the next render derives that preset and the
picker snaps back.

**THE THREE STRIKES (all verified):**

1. `9ad0f2c` (2026-04-14) — ASCII characters: Custom seed was Classic's literal
   string. Fix: seed with a 5-char ramp matching no preset; preserve any existing
   non-preset string.
2. `9a5857f` (2026-04-16) — Dither palette: Custom seed was `VintagePalette.gameBoy`.
   Fix: append a neutral `#808080` swatch so the shape matches no preset, plus an
   early-bail guard when re-picking the already-selected preset
   (documented in `.sisyphus/notepads/sidebar-harmony/learnings.md`).
3. `761fae6` (2026-04-16) — edge case: when the palette was already at
   `MAX_PALETTE_COLORS`, the appended neutral swatch got dropped by `prefix(MAX)`, the
   palette stayed identical to a known preset, and the snap-back returned. Fix: trim
   the base to MAX−1 *before* appending the neutral.

**STATUS: FIXED individually; pattern still live.** Any NEW derived-selection preset
picker can reintroduce this. Rules for new pickers: seed Custom with data guaranteed
to match no preset; preserve the user's current values; guard same-value re-dispatch;
account for capacity caps when appending sentinel data.

## 8. The result-builder revert

**SYMPTOM you will feel.** A reviewer (human or AI) flags
`SidebarControlRowTrailingValueContent` and `SidebarCompoundControlBlockSecondaryContent`
(in `Sources/FramerApp/Sidebar/`) as over-engineered and suggests replacing the
result-builders with a plain generic `TrailingValue: View` parameter.

**WHAT HAPPENED.** During PR #8 pass 3, that exact refactor was attempted per
swift-expert review advice. A snapshot test failed: `secondary: { if flag { row } }`
resolves to `_ConditionalContent<Row, EmptyView>`, which a type-based `== EmptyView`
check misses — so a divider rendered under conditionally-empty secondary content. The
refactor was reverted and the WHY documented. The runtime `.absent` case is the only
reliable way to distinguish "no trailing closure provided" from "trailing closure's
current branch is empty".

**EVIDENCE.** `.sisyphus/notepads/sidebar-harmony/learnings.md`
("Result-builders earn their keep" entry) and the PR #8 body. This is the one true
revert surviving on main.

**STATUS: INTENTIONAL DESIGN.** Do not "simplify" these two primitives. Sidebar
component grammar is owned by `framer-ui-design-system`.

## 9. renderTasks UUID leak

**SYMPTOM.** Preset thumbnail renders leaked and wrote stale previews into app state
from a background context after the photo changed.

**ROOT CAUSE.** `PresetPreviewGrid` kept `renderTasks: [UUID: Task]` keyed by a *fresh
`UUID()` on every call* — each call overwrote nothing and cancellation iterated an
already-rotated map, orphaning the original task. When `.onChange(of: renderKey)` and
`.onAppear` both fired (they do on first appear), two batches raced.

**EVIDENCE.** `.sisyphus/notepads/sidebar-harmony/learnings.md`
("`renderTasks[UUID()] = task` leak" entry); fixed in `761fae6`.

**STATUS: FIXED** with a single `@State var renderTask: Task<Void, Never>?`,
cancel-before-replace, plus `.onDisappear` cancellation. Pattern rule: a task registry
keyed by a value nobody else holds cancels nothing.

## 10. Stale-index crash

**SYMPTOM.** Crash (`layers[staleIdx]` out of bounds) when deleting or reordering a
layer while its detail view was still in the view tree.

**ROOT CAUSE.** `LayerListSection.binding(for index: Int)` captured the array index by
value; one tick after a delete/reorder the index was stale.

**EVIDENCE.** `0debb71` (2026-04-14, "feat(ui): GPU-effects panel polish + fix
layer-binding crash") and the CHANGELOG.md `[Unreleased]` entry ("Stale-index crash in
layer bindings", line 27 as of 2026-07-09).

**STATUS: FIXED** — bindings re-keyed by `layer.id` with a captured layer-value
fallback for the empty-list edge case. Rule: SwiftUI bindings into mutable arrays must
look up by stable identity, never by captured index.

## 11. The dead-controls saga

**SYMPTOM.** Sliders and pickers visible in the inspector that change nothing — or the
inverse, live shader parameters with no UI at all. Drift in both directions between
shader uniforms and inspector controls is the top recurring audit finding of the GPU
program.

**THE INCIDENT CHAIN (all verified):**

| Commit | Date | Direction | What |
|--------|------|-----------|------|
| `0debb71` | 2026-04-14 | dead control | matrixRain Threshold slider removed — the GPU encoder overwrites the shader's threshold uniform with `trailLength`, so the slider had no effect. Also removed a dead Palette color-mode option and the in-panel ShaderStyle picker (silently rewrote params without changing layer kind). |
| `17f8111` | 2026-04-14 | systemic prune | Per-variant UI prune: the global control block was shown on every variant regardless of what its shader reads; introduced capability-flag gating (`usesGeometry`, `usesColorModeAndFgBg`, ...) per `docs/gpu-effects-parameter-matrix.md`. |
| `06749e2` | 2026-04-14 | both | Wired missing core sliders (PrintSampling `threshold`, EdgeField `lineStrength`/`fieldIntensity` — primary strength controls that had NO UI) and removed orphaned ones (waveLines Line Count/Animate; noiseField Noise Type/Speed/Animate/Distort-Only — no time uniform, IGN hardcoded). Also fixed edgeColor's black-disables-tint semantics. |
| `9dfc4ca` | 2026-04-16 | dead control | Sharpness slider rendered in every GPU-effect editor but no shader reads it — `ShaderCommon.h` marks the field "not consumed by helpers". |
| `f21a6fe` | 2026-04-16 | dead controls | Common-adjustment sliders (brightness/contrast/…) dead for pixelSort; `usesCommonAdjustments` now false for `.pixelSort`. |
| `4977e13` | 2026-05-25 | live-params-no-UI | Audit found shader uniforms fed from model fields the sidebar never exposed: PixelSort Threshold+Amount, VHS Amount (pinned at 0.75 — at 0 the effect vanishes entirely), waveLines/noiseField edge-color picker (stuck white), Blockify/matrixRain Intensity. |

**STATUS: MANAGED** via capability flags on `GPUEffectKind`
(`Sources/FramerCore/Effects/Models/GPUEffectKind.swift` — note the path: `Effects/Models/`,
not `Models/`). Open PR #12 extends the flag gating to iOS. The flag catalog and the
add-a-parameter checklist are owned by `framer-config-and-flags`. Rule when adding any
shader parameter: wire shader + uniforms + UI + capability flag **in the same change**,
and audit the variant against its shader, not against the parameter struct.

## 12. Frame-overlay darkening

**SYMPTOM.** Frame-overlay layers (textures where mid-gray means transparent) darkened
the photo center that should be untouched.

**ROOT CAUSE — two independent bugs in the luminance-deviation alpha mask
(α = |L − 0.5| × 2 × opacity):**

1. JPEG-authored overlays store "gray" as byte 128 → L ≈ 0.502, so deviation ≠ 0 and
   the whole frame window darkened faintly. Fix: a 0.005 deadband
   (≈ 1/255 of luminance range) subtracted before scaling — commit `7c54a27`
   (2026-04-14, "add deadband to overlay strength mask").
2. PNG frames with real alpha rasterize transparent pixels as premultiplied black
   (rgb=0), which the luminance mask reads as maximally-deviant dark. Fix: multiply
   the mask by the overlay's real alpha channel.

**EVIDENCE.** `Sources/FramerCore/Processing/BorderRenderer.swift` — the commented
mask formula and both corrections live around lines 747 and 792–807 as of `48d85a5`
(`grep -n "negDeadband\|overlay.alpha" Sources/FramerCore/Processing/BorderRenderer.swift`).

**STATUS: FIXED.** Blend-math theory is owned by `framer-image-processing-reference`.

## 13. Priority inversion

**SYMPTOM.** Xcode's Thread Performance Checker flags, at `BorderRenderer.swift:519`
(`ctx.draw` inside `resize`) during live preview:
"Thread running at User-initiated quality-of-service class waiting on a lower QoS
thread running at Default quality-of-service class."

**ROOT CAUSE (full RCA in the PR body — ingested here because branch context
evaporates).** `FrameProcessor` is an actor, and actors inherit the awaiting task's
QoS via priority escalation. Two paths launched renders with plain `Task {}` from the
`@MainActor` — `PreviewViewModel.updatePreview` and `AppState.exportItems` — which
inherits **User-initiated** QoS. Awaiting the actor escalated it, and the synchronous
CG draws inside BorderRenderer then blocked on CoreGraphics' **Default**-QoS internal
worker threads: User-initiated waiting on Default = priority inversion. (The
preset-thumbnail and original-image paths use `Task.detached` and suspend rather than
block, so they were never flagged.)

**FIX (on the branch).** `Task(priority: .utility)` at both call sites — at/below CG's
Default workers so no high-priority thread waits on a lower one. The preview's 150 ms
debounce makes the QoS drop imperceptible; export has its own progress UI.

**EVIDENCE.** PR #11 (`fix/preview-priority-inversion`, 1 commit).

**STATUS: OPEN** — diagnosed and fixed on the branch, awaiting human merge decision
(no autonomous merges — see `framer-change-control`) as of 2026-07-09; PR is 0 behind main.

## 14. PR #12 color and serialization bugs

Three distinct root causes fixed on the open branch `fix/effect-params-and-editor-bugs`
(11 commits, 0 behind main as of 2026-07-09). Ingested here from the PR body and
review threads before that context evaporates.

**14a. Untagged CGColor sRGB shift.** SYMPTOM: every color swatch, picker round-trip,
and CPU-rendered color was slightly off from the stored hex value. ROOT CAUSE:
`CodableColor.cgColor` built an *untagged Generic RGB* CGColor, so the system
interpreted the components in the wrong color space everywhere. FIX: tag sRGB
(plus 3-digit hex input, iOS dynamic-color resolution, round-instead-of-truncate).
Note the PR's warning: existing presets may read marginally different once hex values
render exactly.

**14b. Blockify color-mode enum collision.** SYMPTOM (found by Codex bot review):
a fresh Blockify layer rendered white/black blocks instead of a blockified source
image. ROOT CAUSE: the Blockify shader borrowed ASCII's separate `asciiColorMode`
numbering (0 = flat, 1 = sampled), which **inverts** the bucket convention
(0 = source, 1 = fg/bg, 2 = monochrome, 3 = palette) — user picks "flat" and gets
"sampled". FIX (`12c42a9`, 2026-06-10): remap the shader to the dots convention rather
than papering over with a different default, so picker labels are truthful; regression
tests cover all modes. TRAP that remains: multiple parallel color-mode numbering
schemes exist across shader families (ascii, bucket/dots, dither) — when wiring a
color mode, verify which numbering the target shader actually decodes.

**14c. Missing YAML key.** SYMPTOM: the Dot Size control's value was silently lost on
preset save/load. ROOT CAUSE: `gpu_text_size_multiplier` was never written to YAML.
FIX: add the key, plus tolerant `decodeIfPresent` decoders for
PrintSampling/EdgeField/Glitch params so adding fields can't break old projects. Same
PR: `EdgeFieldRenderer` now dispatches by layer kind, with `gpu_edge_variant` still
written on encode for older-app back-compat.

**STATUS: OPEN PR** — all three fixed on the branch, unmerged. Schema conventions are
owned by `framer-config-and-flags`.

## 15. Parked: video support

**WHAT EXISTS.** Branch `feature/video-support`: 19 commits (2026-03-15/16), a full
video pipeline including `Sources/FramerCore/Processing/VideoProcessor.swift` and
`Sources/FramerCore/Processing/CIFilterPipeline.swift` (verified present on the
branch), codec picker, trim UI. The tip is `2df2fa4`
"wip: GPU dithering, pre-scale optimization, and memory fixes for video export".

**STATUS: PARKED** at that `wip:` memory-fixes commit — 19 ahead / 255 behind main as
of 2026-07-09. No recorded reason for parking (open maintainer question: performance,
memory, or preempted by the GPU-effects work?). **Any future video attempt starts by
reading this branch, not from scratch** — but expect a heavy rebase; main's rendering
core has been rewritten underneath it (GPU effects bucket, sidebar refactor).

## 16. Destroyed history and dead paper

**16a. Bucket-system history destroyed by cherry-pick.** The `.gpuEffect` bucket
architecture entered main via `ffeffe1` (2026-04-13, "feat: cherry-pick .gpuEffect
bucket-system from feat/grainrad-gpu-effects WIP") and the source branch was then
deleted. Its development history — the reasoning behind the bucket design — is gone.
The surviving spec is `docs/gpu-effects-parameter-matrix.md` (added in `835a9cb`), but
it is **stale in load-bearing detail**: it states the common adjustments block is read
by "No — none of the bucket shaders" (line 28), yet `applyCommonAdjustments` now
appears in `EdgeField.metal`, `Glitch.metal`, `PrintSampling.metal`, and
`TextCell.metal` (wired by `d928370`, with GPU matrixRain/vhs in `b4545fa`/`fbd2a84`,
all 2026-04-14). Ground truth for what a shader reads = the `.metal` source plus the
capability flags in `Sources/FramerCore/Effects/Models/GPUEffectKind.swift`. The full
staleness ledger is owned by `framer-docs-and-writing`.

**16b. `docs/plans/2026-04-01-metal-dither-plan.md` is dead paper.** It plans GPU
dithering under `Sources/FramerCore/Processing/Metal/` — that directory has never
existed on main. GPU dither actually shipped via the Effects bucket
(`Sources/FramerCore/Effects/Metal/Dither.metal` +
`Sources/FramerCore/Effects/Renderers/DitherGPURenderer.swift`). Treat the plan as
superseded; do not execute it.

**16c. Acerola handoff doc is stale.**
`docs/superpowers/plans/2026-04-02-acerola-shader-layer-handoff.md` describes a "live
branch" and a worktree at `../framer-acerola-shader`. The branch
`feat/acerola-shader-layer` is fully merged (`git branch --merged origin/main`), the
worktree is gone, and the doc's "uncommitted work" (`dominantTwoTone`) is on main at
`Sources/FramerCore/Models/CompositionLayer.swift:571`. Only its "Recommended Next
Steps" (visual tuning of ASCII / PixelSort / composite looks) remain live — that work
feeds `framer-campaign-gpu-effects-quality`.

## 17. The build-break pair

**WHAT HAPPENED.** `c515147` (2026-04-13, "fix: filter ASCII / Halftone / PixelSort
duplicates from bucket picker") referenced a `userFacingCases` static that didn't
exist and broke the build on main; `ae4b8ba` repaired it minutes later ("fix: add
missing userFacingCases static (c515147 broke the build)").

**STATUS: FIXED**, kept as evidence: commits in this repo's history were not always
build-verified. The current gating rules that prevent this are owned by
`framer-change-control`.

---

## Provenance and maintenance

Everything above was verified on 2026-07-09 against main at `48d85a5` on the
maintainer's machine (Apple Silicon, macOS). Verification methods: `git show -s
--format='%h %ad %s'` for every cited hash; full commit bodies read for `6635746`,
`761fae6`, `f21a6fe`, `0debb71`, `06749e2`, `9dfc4ca`, `9ad0f2c`, `4977e13`,
`aa60b94`, `17f8111`; `gh pr view 4/6/7/8/11/12` for PR states, bodies, and #12 review
threads; direct file reads for BorderRenderer, Halftone.metal, PixelSort.metal,
learnings.md, CHANGELOG.md, gpu-migration-plan.md, gpu-effects-parameter-matrix.md,
gpu-migration-mac-resume.md; effect suites at the time of writing (27 parity tests,
0 failures).

Volatile facts and one-line re-verification commands:

| Fact (may drift) | Re-verify with |
|---|---|
| PRs #11 and #12 still open | `gh pr list --state open` |
| pr6-check still preserves the 8 PR #6 commits | `git log --oneline origin/main..origin/pr6-check` |
| salvage branch unmerged | `git branch -a --contains aa60b94` (should list only salvage/e2e-test-scaffolding) |
| feature/video-support parked, 19 ahead | `git rev-list --count origin/main..origin/feature/video-support` |
| Golden/behavior suites green (13/14; parity suite retired 2026-07-09) | `swift test --filter EffectGPUGoldenTests` ; `swift test --filter EffectGPUBehaviorTests` |
| userFacingCases + capability flags location | `grep -n 'userFacingCases\|usesCommonAdjustments' Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| Overlay deadband + alpha gating in place | `grep -n 'negDeadband\|overlay.alpha' Sources/FramerCore/Processing/BorderRenderer.swift` |
| Result-builder revert rationale on record | `grep -n '_ConditionalContent' .sisyphus/notepads/sidebar-harmony/learnings.md` |
| Stale-index crash in CHANGELOG Unreleased | `grep -n 'Stale-index' CHANGELOG.md` |
| Matrix doc still stale re: common block | `grep -n 'none of the bucket shaders' docs/gpu-effects-parameter-matrix.md` and `grep -l applyCommonAdjustments Sources/FramerCore/Effects/Metal/*.metal` |
| PIXEL_SORT_SAMPLE_COUNT still 24 | `grep -n 'PIXEL_SORT_SAMPLE_COUNT' Sources/FramerCore/Effects/Metal/PixelSort.metal` |

When a saga's STATUS changes (e.g. PR #11/#12 merge, e2e revival lands, CPU path
retired), update the entry and the index row in the same commit as the change — this
skill is only useful while it stays true.
