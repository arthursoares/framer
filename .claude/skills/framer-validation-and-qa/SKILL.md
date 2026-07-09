---
name: framer-validation-and-qa
description: >
  Load when running, writing, interpreting, or updating tests in this repo — "run the tests",
  "tests pass/fail", snapshot test failed, "Actual SHA256" in a failure message, expectedSHA256
  hash mismatch, XCTSkip, GPU parity tolerance changes, adding a test to FramerCore/FramerCLI/
  FramerAppTests, "is X covered by tests?", or deciding whether a change is validated enough to
  commit. Owns the test-estate map, the snapshot-hash update protocol (house rule: never
  blind-refresh), test-writing conventions, and the honest no-tests map.
---

# framer-validation-and-qa

What counts as evidence in this repo, how the two test tiers work, the snapshot-hash
house rule, how to write and add tests, and — just as important — what has NO tests.

There is **no CI** (no `.github/`, no `scripts/`, no Makefile — as of 2026-07-09,
commit 48d85a5). Every validation claim in this repo is a claim about commands YOU ran
locally. That makes the evidence bar below load-bearing, not bureaucratic.

## When NOT to use this skill

| You actually want | Go to |
|---|---|
| Fix the broken xcodebuild test tier / revive E2E | framer-campaign-restore-validation |
| Environment setup, toolchain traps, LFS, xcodegen mechanics | framer-build-and-env |
| Measuring pixels / writing diagnostics instead of eyeballing | framer-diagnostics-and-proof |
| Commit/branch/PR rules, the cloud-handoff checklist itself | framer-change-control |
| Why parity exists / whether the CPU path should be retired | framer-architecture-contract |
| Triage of a specific failure symptom | framer-debugging-playbook |
| Full incident histories referenced here by name | framer-failure-archaeology |

## The evidence bar

A change is "validated" only when you can quote the command AND its output:

1. Run the command. Copy the summary line (e.g. `Executed 268 tests, with 0 failures
   (0 unexpected)`), not a paraphrase.
2. **Report skip counts.** "Green" without a skip-check is not evidence — see the
   XCTSkip section below. If the output contains `skipped`, say how many and why.
3. If you could not run a tier (broken env, cloud session without a Mac), hand off with
   an explicit ✅/❌ checklist. Precedent in-repo: docs/gpu-migration-mac-resume.md
   ("Validation status when leaving the cloud session" — `✅ git push passes /
   ❌ swift build not run / ❌ swift test not run / ❌ Visual smoke test not run`).
   The canonical handoff checklist is owned by framer-change-control.
4. Anything that renders pixels is judged by **measurement, never by eye** —
   parity deltas, bitmap hashes, frame-containment walks. See
   framer-diagnostics-and-proof for the measuring tools.

## Test-estate map (two tiers)

| | Tier 1: SPM | Tier 2: Xcode app tests |
|---|---|---|
| Targets | FramerCoreTests (264 tests) + FramerCLITests (9 tests) | FramerAppTests (12 files, 63 test methods) |
| Total | 273 tests, ~4s execution (2026-07-09, post CPU-path retirement) | 63 methods |
| Declared in | Package.swift (`.testTarget`) | project.yml ONLY — **not** in Package.swift |
| Run with | `swift test` | `xcodegen generate` then `xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'` |
| Needs | Swift toolchain; Metal device for full coverage (see skips) | Xcode, valid signing, Metal Toolchain component |
| Status | GREEN (verified 2026-07-09 post-retirement: `Executed 273 tests, with 0 failures (0 unexpected)`, zero skips on this host) | **BROKEN on the primary dev Mac** as of 2026-07-09 |
| Contains | All FramerCore rendering/config/preset logic, GPU golden-reference + behavior tests, CLI helper units | All SwiftUI snapshot/containment/resolver tests for the sidebar + inspector |

Counts date-stamped 2026-07-09, commit 48d85a5.

### Tier 1: run it

```bash
swift test                                   # full suite, ~4s test execution
swift test --filter EffectGPUGoldenTests     # one suite
swift test --list-tests | wc -l              # expect 273
```

Expect: `Executed 273 tests, with 0 failures (0 unexpected)`. If you see fewer tests
than 273 executed or any `skipped` lines, read the XCTSkip section before declaring green.

### Tier 1: the XCTSkip trap (silent coverage loss)

Metal-dependent tests guard themselves with `XCTSkip` instead of failing. On a host
WITHOUT a Metal GPU device (cloud containers, Linux, some sandboxes), these silently
skip — the run still prints "0 failures":

| File | Metal-guarded tests | Guard |
|---|---|---|
| Tests/FramerCoreTests/EffectGPUGoldenTests.swift | all 13 | `requireMetal()` → `XCTSkip` when `MetalEffectLibrary.shared == nil` |
| Tests/FramerCoreTests/EffectGPUBehaviorTests.swift | 13 of its 14 (the Riemersma routing test runs everywhere — it exercises the kept CPU capability) | `requireMetal()` per test |
| Tests/FramerCoreTests/DitherRendererTests.swift | 20 of its 27 (6 pure param/YAML-Codable tests + the Riemersma render test carry no guard and run everywhere) | `requireMetal()` per render test |
| Tests/FramerCoreTests/ShaderRendererTests.swift | all 16 | class-level `setUpWithError` skip — every test renders, and ShaderRenderer is GPU-only post-retirement |
| Tests/FramerCoreTests/LUTRendererTests.swift | 5 | `guard LUTMetalRenderer.isAvailable` |
| Tests/FramerCoreTests/MetalTextureSupportTests.swift | 1 | `MTLCreateSystemDefaultDevice()` |
| Tests/FramerCoreTests/ASCIIAtlasGeneratorTests.swift | 1 | `MTLCreateSystemDefaultDevice()` |

That is **69 tests that vanish on Metal-less hosts** while the suite still reads
"passed" (up from 32 pre-retirement: effect rendering now requires Metal, so whole
render suites skip rather than silently exercising a deleted CPU path). The two ASCII
golden tests additionally skip if the LUT atlas PNGs are unreachable. (Other
`XCTSkip`s in EXIFReaderTests / TextureFrameProviderTests guard fixture-construction
failures, not Metal.)

**Rule: a test report is `Executed N, failures F, skipped S` — always all three.**
On the primary dev Mac (Metal present, atlases present) the expected skip count is 0.

Note: the test files' skip messages mention "CI sandbox" — there is no CI; those
comments describe hypothetical environments. Don't go looking for a CI config.

### Tier 2: run it (currently broken locally)

```bash
xcodegen generate   # MANDATORY after any file add under Sources/FramerApp/ or Tests/FramerAppTests/
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
# narrow to one class:
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
  -only-testing:FramerAppTests/SidebarMetricsTests
```

As of 2026-07-09 this fails on the primary dev Mac, twice over:

1. Revoked signing certificate (`CSSMERR_TP_CERT_REVOKED` — revoked, not merely
   expired, so waiting won't help; framer-campaign-restore-validation P1 owns cert
   state and remediation): `Signing certificate "Apple Development:
   arthur@arthursoares.com.br (P7K6Z5BCV4)" ... is not valid for code signing.`
2. With signing disabled (`CODE_SIGNING_ALLOWED=NO`): `cannot execute tool metal due
   to missing Metal Toolchain` (Xcode 26 ships it as a separate component; the error's
   own remedy is `xcodebuild -downloadComponent MetalToolchain`).

Do not chase phantom code bugs when you hit either string. Repairing this tier is the
mission of **framer-campaign-restore-validation**. The asymmetry to remember: `swift
test` works fine on the same machine because SPM ships `.metal` files as source and
compiles them at runtime — only xcodebuild needs the offline Metal compiler
(framer-build-and-env owns the details).

Known trap (recorded three times in .sisyphus/notepads/sidebar-harmony/learnings.md):
new files under Sources/FramerApp/ or Tests/FramerAppTests/ are invisible to xcodebuild
until `xcodegen generate` reruns, and stale test discovery sometimes needs
`xcodebuild clean test` on top.

## THE SNAPSHOT PROTOCOL (house rule)

Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift locks 10 sidebar/inspector
surfaces (sidebar-shell, output-rows-png, output-rows-jpeg, simple-canvas-editor,
simple-border-editor, dense-caption-editor, dense-dither-editor, overlay-editor,
preset-grid-support-surfaces, export-support-surfaces) as **inline SHA-256 hashes.
There are no golden image files.**

How it works (`assertSnapshot`, lines 270–307 of that file): the view is wrapped in
`.environment(\.colorScheme, .dark)` + fixed `CGSize`, hosted in an `NSHostingView`
with `NSAppearance(named: .darkAqua)`, laid out via `layoutSubtreeIfNeeded()`, rendered
with `bitmapImageRepForCachingDisplay` + `cacheDisplay`, PNG-encoded, hashed with
CryptoKit SHA256, and compared to the `expectedSHA256:` string literal. On mismatch the
failure message prints the new hash: `Snapshot <name> changed. Actual SHA256: <hex>`.

### The update loop — follow exactly

1. Run the affected test (Tier 2 command above, `-only-testing:FramerAppTests/SidebarHarmonySnapshotTests`).
2. Read the failure. Note which named surface shifted and its new hash.
3. **LOOK AT THE RENDERED PIXELS AND EXPLAIN THE SHIFT.** Never paste the new hash on
   faith. No reference PNGs are stored, so to see pixels: temporarily add
   `try? data.write(to: URL(fileURLWithPath: "/tmp/snap-\(name).png"))` inside
   `assertSnapshot` just before hashing, run on your branch and on the parent commit,
   and diff the two PNGs (framer-diagnostics-and-proof has pixel-diff recipes). Remove
   the debug line before committing.
4. Only when the shift is explained by your change: paste the new hash into
   `expectedSHA256`, rerun, confirm green.
5. Land the hash refresh **in the same commit as the change that caused it**, keeping
   it to **1–4 hashes per commit** so `git bisect` attributes any visual regression to
   a single step. (Pass-3 precedent: ~12 hash updates across 10 commits, every one
   attributable — learnings notepad.)

**MAINTAINER RULE (2026-07-09): never blind-refresh snapshot hashes.** The archetype
incident: a "semantically transparent" refactor of a result-builder to generic
`TrailingValue: View` shifted a snapshot; reading the pixels showed a divider rendering
under a conditionally-empty secondary row (`_ConditionalContent` defeating an
`== EmptyView` type check). The refactor was reverted — the snapshot was the only thing
that caught it. Lesson recorded in .sisyphus/notepads/sidebar-harmony/learnings.md:
"Snapshot diff is the forcing function; read the pixels, not the diff."

### Known limitation: hashes are single-machine

Exact PNG SHA-256 depends on font rasterization and GPU compositing. The current
baselines were recorded on one Mac; a different machine or a macOS update can fail all
10 at once. The author's recorded verdict: "fragile on cross-machine ... but locally
it's been catching EVERY layout drift — including ones the author didn't expect. Worth
keeping." Cross-machine mismatch is therefore **expected, not a regression** — the
open policy decision (re-baseline vs tolerant comparison) is driven by
framer-campaign-restore-validation's P3 decision gate; the resulting standing rule
gets recorded here. If you hit it, do not refresh hashes from a second
machine without a maintainer decision.

## Measured-test patterns (use these, not your eyes)

| Pattern | Exemplar | When to copy it |
|---|---|---|
| Golden-reference regression: mean + max per-channel byte delta vs a committed PNG, per-effect tolerance, deterministic 256×256 gradient+checkerboard fixture | Tests/FramerCoreTests/EffectGPUGoldenTests.swift (`compare(_:_:)`, `assertMatchesGolden`; regeneration env-gated per the file header) | Any "this effect must render what it rendered yesterday" claim |
| Statistical property assertions (color-variety reduction, channel bias, premultiplied-alpha invariants) | Tests/FramerCoreTests/ShaderRendererTests.swift (e.g. `test_crimewaveShader_pushesNeonBias`, `test_pixelSortMaintainsPremultipliedAlpha`) | Directional effects with no exact expected output |
| Per-pixel membership (output must be binary B/W or drawn only from a palette) | EffectGPUBehaviorTests dither tests (`testDitherBayerOutputIsBinaryBW`, `testDitherPaletteUsesOnlyPaletteColors`) | Quantizing/dithering effects |
| Bitmap INEQUALITY: two renders must hash differently (machine-independent) | Tests/FramerAppTests/StyledSliderSuffixTests.swift (`bitmapSHA256`, pumps the run loop with `RunLoop.main.run(until:)`) | "This parameter must visibly change rendering" |
| Layout containment: walk the NSView tree, fail on frames whose `maxX` exceeds the sidebar width + 0.5, excluding `NSClipView` descendants | Tests/FramerAppTests/SidebarLayoutContainmentTests.swift (`assertFitsSidebarWidth`, `visibleDescendantFrames`) | "This view must not overflow" |
| Pure-resolver seam: extract decision logic into a value-type function, test it directly | LayerPanelRowStateResolver, StyledSliderValueResolver, InspectorOutputControlState (tests in Tests/FramerAppTests/) | SwiftUI state logic — see conventions below |
| Body-type reflection guards (`String(reflecting: type(of: view.body))` contains/doesn't-contain a type name) | StyledSliderSuffixTests (`_ConditionalContent` check), SidebarHarmonySnapshotTests (`StyledToggle` must contain `Toggle`) | Cheap structural regression traps |

"Looks right in the screenshot" is never acceptance for anything FramerCore renders.

## Test-writing conventions

- **XCTest only.** Zero Swift Testing usage anywhere (verified: no `import Testing` in
  Sources/ or Tests/; the Swift Testing runner reports "0 tests in 0 suites"). Do not
  introduce `@Test`/`#expect` without a maintainer decision.
- Layout: `Tests/<TargetName>Tests/` — FramerCoreTests, FramerCLITests, FramerAppTests.
- Imports: `@testable import FramerCore` / `@testable import FramerCLI`; for app tests
  it is `@testable import Framer` — **the macOS app module is named `Framer`, not
  `FramerApp`** (a documented gotcha).
- Naming: dominant style is `test_subject_condition` (majority of test files). Older
  files use legacy `testCamelCase` (ASCIIAtlasGeneratorTests, EffectGPUBehaviorTests,
  EffectGPUGoldenTests, GPUEffectBucketDispatchTests, LayerCompositorTests,
  MetalTextureSupportTests). Write
  new tests in `test_subject_condition`; match the local file's style when appending.
- `@MainActor` on any test class that hosts AppKit/SwiftUI views (all snapshot,
  containment, and bitmap tests carry it).
- Environment-dependent tests use the `XCTSkip` guard pattern — copy `requireMetal()`
  from EffectGPUGoldenTests (per test; scope the guard to tests that actually need
  the environment) or the `setUpWithError` class-level skip from ShaderRendererTests
  (only when EVERY test in the class needs it). Never let a missing GPU/fixture
  produce a red test.
- Fixtures: `Bundle.module` + `.copy` resources. Exemplar: FrameProcessorTests reads
  Tests/FramerCoreTests/Resources/sample.jpg via
  `Bundle.module.url(forResource: "sample", withExtension: "jpg", subdirectory: "Resources")`,
  declared as `.copy("Resources")` in Package.swift.
- **Zero third-party test dependencies — deliberately.** No view-inspection libraries.
  When SwiftUI logic needs testing, extract a pure resolver (see table above) instead
  of adding a dependency. Package.swift's only deps are swift-argument-parser and Yams.

## Adding a test — checklist

**To FramerCore or FramerCLI (plain):**
1. Add the file under Tests/FramerCoreTests/ or Tests/FramerCLITests/. Nothing else —
   SPM discovers it.
2. New fixture files go in Tests/FramerCoreTests/Resources/ (already `.copy`-declared).
3. `swift test --filter <YourSuite>` then full `swift test`; quote executed/failed/skipped.

**To the app (FramerAppTests):**
1. Add the file under Tests/FramerAppTests/, `@testable import Framer`, `@MainActor`
   if it touches views.
2. `xcodegen generate` — non-negotiable; the committed .xcodeproj is a snapshot.
3. Run the Tier 2 xcodebuild command. If new tests aren't discovered:
   `xcodebuild clean test`.
4. Do not strip `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` from the FramerAppTests target
   in project.yml — the bundle and the app target must match or macOS refuses to load
   the test bundle into Framer.app (Team ID mismatch, a recorded incident).

## Golden-reference discipline (was: parity tolerance discipline)

The CPU effect path was retired 2026-07-09 (docs/adr/2026-07-09-retire-cpu-effect-path.md
— executed the same day; see framer-architecture-contract I3 for the new contract).
Pixel-level regression is now anchored to frozen golden PNGs in
Tests/FramerCoreTests/Resources/GoldenReferences/, compared in
EffectGPUGoldenTests.swift with the per-effect tolerances inherited from the retired
CPU-vs-GPU parity tests, e.g. Crimewave `mean < 6.0`, `max < 40`; PixelSort
default-span `mean < 12.0`. On the machine that generated the goldens the delta is 0;
the tolerances are cross-machine headroom.

Rules:

- **Golden refresh follows the snapshot-hash discipline (house rule 2): never
  blind-refresh.** Regeneration is env-gated
  (`FRAMER_REGENERATE_GOLDENS=1 swift test --filter EffectGPUGoldenTests`); the new
  PNGs land in the same commit as the shader change that caused the shift, with an
  explanation of WHY the pixels moved.
- Changing any tolerance REQUIRES a written justification in the commit message with
  the measured before/after delta numbers (mean and max). Get the numbers from the
  test's own failure message or the recipes in framer-diagnostics-and-proof. Older
  guidance in docs/gpu-migration-mac-resume.md says "raise the tolerance after
  eyeballing the diff" — superseded: measure, don't eyeball (maintainer ruling 2026-07-09).
- Rough triage, still valid: PixelSort mean delta 12–20 → likely legitimate rank-flip
  cascade, investigate then justify; 50+ → real bug (check sweep direction, sort
  order, intensity blend factor).
- Kept CPU code, by design: Riemersma dither (sole implementation — serial
  Hilbert-curve walk, dispatched by algorithm), the hidden legacy bucket variants
  (textCell `.ascii`, printSampling `.halftone`/`.dithering`), and the LUT stack's
  `applyCPU`/`applyCPUReference` (LUT oracle tests + `benchmark lut` baseline). The
  degraded mono cmykHalftone CPU fallback is GONE — cmykHalftone is GPU-only.

## The honest no-tests map

Assume NO safety net in these areas (as of 2026-07-09, commit 48d85a5):

| Area | Coverage | Notes |
|---|---|---|
| FramerMobile (iOS) | **Zero.** No test target exists in project.yml or Package.swift | Manual-only |
| CLI process-level | **Zero on main.** The 9 FramerCLITests are static-helper units (`validatedWorkers`, `applyOutputFormatOverride`, `shellQuote`, one ArgumentParser parse) — nothing spawns the binary | E2E spec exists only on branch `salvage/e2e-test-scaffolding` (commit aa60b94, +265 lines, 11 files) — **not wired into any build manifest**, so it executes nothing. Revival is owned by framer-campaign-restore-validation |
| Metal shaders directly | Only indirect, via golden-reference + behavior/statistical tests | No per-shader unit tests |
| FramerApp outside sidebar/inspector | **Untested**: Canvas/, ZoomState, AppState behavior, export execution | `exportQueue` appears in tests only as snapshot fixture state |
| E2E (any target) | **Does not exist on main** | The salvage branch is the design spec, not a runnable suite |

### Golden/fixture inventory

- `docs/examples/*.jpg` — 10 published sample images, **non-regenerable**: no
  generation script exists, and docs/index.html documents them with legacy v1 CLI
  syntax that no longer parses (staleness ledger: framer-docs-and-writing). They are
  plain git blobs, not LFS.
- Snapshot baselines — inline SHA-256 hex strings in SidebarHarmonySnapshotTests.swift.
  **No stored reference PNGs anywhere.**
- `Tests/FramerCoreTests/Resources/sample.jpg` — SPM test fixture.
- `Tests/FramerCoreTests/Resources/GoldenReferences/*.png` — 16 frozen GPU effect
  references (2026-07-09), regenerable only via the env-gated command in
  EffectGPUGoldenTests.swift's header; plain git blobs, not LFS.
- ASCII LUT atlases in Sources/FramerCore/Resources/textures/ are deliberately outside
  LFS so Tier 1 passes on a fresh clone without `git lfs pull` (framer-build-and-env).

## Provenance and maintenance

All facts verified 2026-07-09 against commit 48d85a5 on the primary dev Mac
(arm64, Swift 6.3.3, Xcode 26.6) by running the commands below — except the two
Tier-2 failure strings (signing cert, Metal Toolchain), which reproduce the state
recorded the same day; re-running full `xcodebuild test` is expensive and was not
repeated for this document.

Re-verification one-liners:

| Fact | Command |
|---|---|
| 273 SPM tests (264 Core + 9 CLI) | `swift test --list-tests \| cut -d. -f1 \| sort \| uniq -c` |
| Suite green, ~4s | `swift test 2>&1 \| grep Executed \| tail -1` |
| Zero skips on this host | `swift test 2>&1 \| grep -c skipped` (expect 0) |
| 12 app-test files / 63 methods | `ls Tests/FramerAppTests \| wc -l` ; `grep -rc 'func test' Tests/FramerAppTests/*.swift \| awk -F: '{s+=$2} END{print s}'` |
| FramerAppTests not in SPM | `grep -c FramerAppTests Package.swift` (expect 0) ; `grep -n 'FramerAppTests' project.yml` |
| Golden/behavior/dither Metal guards (13/13, 13/14, 20/27) | `grep -c 'try requireMetal()' Tests/FramerCoreTests/EffectGPUGoldenTests.swift Tests/FramerCoreTests/EffectGPUBehaviorTests.swift Tests/FramerCoreTests/DitherRendererTests.swift` ; class-level: `grep -n 'setUpWithError' Tests/FramerCoreTests/ShaderRendererTests.swift` |
| Other Metal guards (5+1+1) | `grep -rn 'LUTMetalRenderer.isAvailable' Tests/FramerCoreTests/LUTRendererTests.swift \| wc -l` ; `grep -rn 'MTLCreateSystemDefaultDevice' Tests/FramerCoreTests/MetalTextureSupportTests.swift Tests/FramerCoreTests/ASCIIAtlasGeneratorTests.swift` |
| Snapshot harness + failure message | `grep -n 'Actual SHA256' Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` |
| 10 snapshot surfaces | `grep -c 'expectedSHA256: "' Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` |
| No Swift Testing | `grep -rln 'import Testing' Sources/ Tests/` (expect empty) |
| Naming split (29 vs 5 files) | `grep -rl 'func test_' Tests --include='*.swift' \| wc -l` |
| ShaderRenderer is GPU-only (no gpuOrCPU) | `grep -c 'gpuOrCPU\|catch let error as MetalEffectError' Sources/FramerCore/Processing/ShaderRenderer.swift` (expect 0) |
| Riemersma dispatched by algorithm | `grep -n 'riemersma' Sources/FramerCore/Processing/DitherRenderer.swift \| head -3` |
| Example tolerances | `grep -n 'meanTolerance' Tests/FramerCoreTests/EffectGPUGoldenTests.swift` |
| 16 golden PNGs committed | `ls Tests/FramerCoreTests/Resources/GoldenReferences \| wc -l` |
| No CI / scripts | `ls .github scripts` (expect ENOENT for both) |
| No iOS tests | `grep -rn 'FramerMobileTests' project.yml Package.swift` (expect empty) |
| No E2E on main | `grep -rln 'E2E' Sources Tests Package.swift project.yml` (expect empty) ; branch: `git branch -a \| grep e2e` |
| Salvage branch shape | `git show origin/salvage/e2e-test-scaffolding --stat` |
| docs/examples not LFS, 10 files | `ls docs/examples \| wc -l` ; `git lfs ls-files \| grep -c docs` (expect 0) |
| Tier-2 failure strings (env-state, may heal) | `xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' 2>&1 \| grep -m2 -i 'certificate\|Metal Toolchain'` |
| xcodegen ritual + team-ID + cross-machine-hash lessons | `grep -n 'xcodegen generate\|DEVELOPMENT_TEAM\|fragile on cross-machine' .sisyphus/notepads/sidebar-harmony/learnings.md` |
