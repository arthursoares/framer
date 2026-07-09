---
name: framer-diagnostics-and-proof
description: >
  Load when you need to PROVE something about rendering or performance in the framer
  repo instead of eyeballing it — verifying a GPU effect matches CPU, interpreting
  EffectGPUParityTests mean/max byte-delta failures, deciding whether to raise a parity
  tolerance, checking whether the GPU path is even running (CPU-fallback console logs),
  byte-comparing "suspiciously identical" effect variants, diagnosing grid/half-texel
  misalignment, backing performance claims with `swift run framer benchmark lut`, or
  checking environment health (git-lfs pointers, Metal Toolchain, signing cert) with the
  shipped scripts. Keywords: parity, mean delta, tolerance, XCTSkip, benchmark, fallback,
  measure, evidence, diff.
---

# Diagnostics and proof: measure, never eyeball

This skill is the measurement toolbox for the framer repo: the diagnostic
instruments with interpretation guides, three verified runnable scripts, and
analysis recipes each anchored to a real incident from this repo's history.

**The doctrine (non-negotiable):** any claim about rendering correctness or
performance must be backed by numbers taken before AND after the change.
Screenshots are illustration, never evidence. "Looks right" is not a result;
"mean per-channel delta 3.2/255 on the parity fixture" is. Maintainer ruling
2026-07-09: "beyond state of the art" here means Grainrad-class effect quality
*verified by measurement, never judged by eye* (the executable campaign lives
in **framer-campaign-gpu-effects-quality**).

## When NOT to use this skill

| You actually want to... | Go to sibling |
|---|---|
| Write or update tests, snapshot-hash refresh protocol, test naming/layout | **framer-validation-and-qa** |
| Repair the broken xcodebuild test tier / revive E2E | **framer-campaign-restore-validation** |
| Drive effect quality to Grainrad-class (campaign) | **framer-campaign-gpu-effects-quality** |
| Understand Metal mechanics (uniforms, texture upload, adding an effect) | **framer-metal-pipeline-reference** |
| Understand the image-processing math (color spaces, dithering, blend modes) | **framer-image-processing-reference** |
| Triage a symptom you can't yet name | **framer-debugging-playbook** |
| Full story of a past incident cited here by name | **framer-failure-archaeology** |
| Set up the environment from scratch | **framer-build-and-env** |

## Shipped scripts

Three POSIX shell scripts live in
`.claude/skills/framer-diagnostics-and-proof/scripts/`. All were written and
executed successfully on 2026-07-09 (commit 48d85a5, Apple Silicon, Swift
6.3.3). Run them from anywhere inside the repo; they `cd` to the git root
themselves. No dependencies beyond git and the Swift toolchain.

### scripts/env-doctor.sh — is this machine trustworthy?

```sh
.claude/skills/framer-diagnostics-and-proof/scripts/env-doctor.sh
```

Checks, printing one `PASS`/`WARN`/`FAIL` line each:
1. Swift toolchain present.
2. `xcodegen` present (WARN if absent — only app-target work needs it).
3. `git-lfs` installed AND all LFS-tracked files actually pulled: reads the
   first 64 bytes of every `git lfs ls-files` path looking for the LFS pointer
   spec line — an un-pulled texture is a ~132-byte text stub and overlays
   silently render as garbage (168 LFS files, all under `assets/textures/`,
   as of 2026-07-09).
4. Metal Toolchain status via `xcodebuild -showComponent metalToolchain`.
   WARN if `uninstalled` — breaks ONLY `xcodebuild` app builds ("cannot
   execute tool metal"); `swift build`/`swift test` compile shaders via
   FramerCore's runtime source-compile fallback and are unaffected.
5. Code-signing hint via `security find-identity -v -p codesigning`. On the
   primary machine this WARNs: cert `P7K6Z5BCV4` reports
   `CSSMERR_TP_CERT_REVOKED` (verified 2026-07-09), failing `xcodebuild test`
   before it compiles anything.

Exit code = number of FAILs. FAIL means the SPM tier or render output is
compromised; WARN means only the (currently broken anyway) xcodebuild tier is
affected. See **framer-build-and-env** for fixes and
**framer-campaign-restore-validation** for the repair campaign.

### scripts/parity-report.sh — did parity actually get verified?

```sh
.claude/skills/framer-diagnostics-and-proof/scripts/parity-report.sh                      # default: EffectGPUParityTests
.claude/skills/framer-diagnostics-and-proof/scripts/parity-report.sh ShaderRendererTests  # any suite name
```

Runs `swift test --filter <Suite>` and reports expected/passed/failed/skipped.
The critical feature is **skip detection**: every parity test calls
`requireMetal()` which throws `XCTSkip` (XCTest's "skip this test" mechanism)
when no Metal device exists, and the ASCII tests additionally skip when the
glyph atlases aren't reachable. A naive "tests passed" report in a headless
container can mean 25 fewer real verifications (25 of the 27 parity tests are
`requireMetal()`-guarded; 2 fallback-routing tests run even without Metal —
skip arithmetic owned by **framer-validation-and-qa**). The script computes
`skipped = (tests listed by --list-tests) − passed − failed`, which is robust
against XCTest output-format changes.

Exit codes: `0` all executed and passed · `1` failures · `2` green **but
skipped** — do NOT report "parity verified" · `3` suite not found.

Verified 2026-07-09: reports 27/27 passed, 0 skipped for
`EffectGPUParityTests` on the primary machine (Metal device present, atlases
present).

### scripts/test-inventory.sh — is coverage drifting?

```sh
.claude/skills/framer-diagnostics-and-proof/scripts/test-inventory.sh
```

Counts SPM tests per suite and per module via `swift test --list-tests`, plus
a static grep count of the xcodebuild-only `FramerAppTests` tier (invisible to
SPM). Baseline as of 2026-07-09, commit f2c9521 (post PR #12 merge): **273 SPM
tests** (264 FramerCoreTests + 9 FramerCLITests; was 268 at 48d85a5 before
GPUEffectRegressionTests landed) plus **63 FramerAppTests methods**. If
today's total is lower than the baseline, tests were deleted or a target fell
out of the manifest — investigate before celebrating a green run. The
test-estate map itself is owned by **framer-validation-and-qa**.

## Instrument catalog

| Instrument | What it measures | Where |
|---|---|---|
| EffectGPUParityTests | CPU-vs-GPU mean/max per-channel byte delta | `Tests/FramerCoreTests/EffectGPUParityTests.swift` |
| ShaderRendererTests | Statistical properties of effect output | `Tests/FramerCoreTests/ShaderRendererTests.swift` |
| DitherRendererTests | Per-pixel set-membership (binary BW, palette) | `Tests/FramerCoreTests/DitherRendererTests.swift` |
| StyledSliderSuffixTests | Bitmap INEQUALITY between two renders | `Tests/FramerAppTests/StyledSliderSuffixTests.swift` |
| SidebarLayoutContainmentTests | NSView frame overflow past sidebar width | `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift` |
| `swift run framer benchmark lut` | CPU vs Metal LUT timing + per-stage split | `Sources/FramerCLI/Commands/BenchmarkCommand.swift` |
| `[ShaderRenderer]` console lines | Whether the GPU path actually ran | `Sources/FramerCore/Processing/ShaderRenderer.swift:84,87` |
| EffectPreviewComparator | Preview-vs-export mean channel delta (currently unused) | `Sources/FramerCore/Effects/Utilities/EffectPreviewComparator.swift` |

### 1. EffectGPUParityTests — the parity meter

"Parity" here means: the CPU implementation and the Metal (GPU) implementation
of the same effect produce near-identical pixels for the same parameters. Each
test renders a deterministic 256×256 synthetic image — a gradient with a
16-px checkerboard dimming pattern, built in `makeTestImage()`
(EffectGPUParityTests.swift:34–64) so every effect has edges, gradients, and
saturation to act on — through both paths, then computes:

- **mean delta**: average absolute difference per RGB channel, in 0–255 byte
  units (alpha ignored) — `compare()` at EffectGPUParityTests.swift:70–91.
- **max delta**: the single worst channel difference.

Run it:
```sh
swift test --filter EffectGPUParityTests        # or scripts/parity-report.sh
```

**Tolerances are deliberately generous** (file header, lines 11–24) because
four divergence sources are legitimate, not bugs: CPU uses Double while GPU
uses Float/half; ASCII GPU samples 4×4 stratified per cell vs CPU's exhaustive
cell average; readback does an sRGB roundtrip through CIContext; CGContext
interpolates when GPU output is upscaled. Current mean-delta ceilings range
from 2.0 (pixel-sort threshold-skip passthrough) through 6.0 (color grades) to
25.0 (ASCII).

**Interpretation bands** (from `docs/gpu-migration-mac-resume.md:285–301`,
written for pixel-sort but the logic generalizes):

| Observed mean delta | Reading | Action |
|---|---|---|
| Under the test's ceiling | Parity holds | Nothing — record the number in your PR |
| Slightly over, ~12–20 | Probably legitimate divergence amplified | Render both outputs, inspect the diff, and only then consider raising the tolerance — in the same commit, with the measured number in the commit message |
| 50+ | Real bug | Work the checklist: sweep-direction invariant, ascending sort on both sides, blend-factor semantics (`mix(current, sorted, intensity)` must equal `params.intensity * amount` on both paths), uniform struct layout |

**Maintainer ruling (2026-07-09):** CPU/GPU parity is current mechanical
reality, not eternal doctrine. `ShaderRenderer.gpuOrCPU` falls back to CPU
only on `MetalEffectError`, and these tests must stay green **while the CPU
path exists** — but whether the CPU path should exist at all is an open
architectural question owned by **framer-architecture-contract**. Don't treat
parity as sacred; don't treat it as retired.

Skip behavior: `requireMetal()` (lines 115–119) throws XCTSkip without a Metal
device; ASCII tests also skip when `MetalTextureSupport.loadLUTTexture` can't
find `edgesASCII.png` in `TextureFrameProvider.searchPaths` (the atlases ship
in FramerCore's SPM resource bundle — NOT git-LFS files). The file header's
"Authored on Linux Cloud — has not yet been compiled" and its CI-sandbox
mentions are stale: the suite runs and passes here, and no CI exists
(staleness ledger: **framer-docs-and-writing**).

### 2. ShaderRendererTests — statistical-property assertions

When exact pixels can't be pinned (stylized effects), assert *directional
statistics* instead. Real examples (all in ShaderRendererTests.swift):

- `test_crimewaveShader_pushesNeonBias` (line 510): output average saturation
  must exceed input's, and blue-minus-green bias must grow.
- `test_narcShader_increasesTonalCrush` (line 526): bottom-quartile luminance
  drops, luminance standard deviation rises.
- `test_distantPastShader_reducesColorVariety` (line 495): unique-color count
  strictly decreases.
- `test_pixelSortMaintainsPremultipliedAlpha` (line 628): invariant that
  premultiplied alpha survives the effect.

Use this style for any new effect whose exact output is unstable but whose
*intent* is measurable. DitherRendererTests does the set-membership variant:
every output pixel must be near-black/near-white (BW mode) or within ±3 bytes
of a palette entry (e.g. `test_bayer_bw_producesOnlyBlackWhite`, line 102).

### 3. StyledSliderSuffixTests — bitmap INEQUALITY diffing

Machine-independent bitmap testing: instead of pinning a hash (fragile across
font rasterization), assert two renders are *different* or *same-shaped*.
`bitmapSHA256(of:size:)` (StyledSliderSuffixTests.swift:89–112) renders a
SwiftUI view through `NSHostingView` (dark appearance), pumps the run loop
0.05 s, encodes PNG, hashes with SHA-256. Then:

- `StyledSlider` vs `StyledUnitSlider` must hash DIFFERENTLY (a collapse means
  someone reintroduced the inline suffix).
- Two `StyledUnitSlider`s with different units must hash differently (unit
  label silently dropped otherwise).
- Plus a reflection guard: `body`'s type name must not contain
  `_ConditionalContent` (line 75), which is how an `if !suffix.isEmpty` branch
  betrays itself in the type system.

These inequality assertions travel across machines; the absolute-hash snapshot
suite (SidebarHarmonySnapshotTests) does not — its update discipline is owned
by **framer-validation-and-qa** and the never-blind-refresh house rule by
**framer-change-control**.

### 4. SidebarLayoutContainmentTests — measured layout overflow

Layout containment is measured, not screenshotted:
`assertFitsSidebarWidth` (SidebarLayoutContainmentTests.swift:80–109) hosts
the view at `SidebarMetrics().idealWidth`, walks the resulting NSView tree
(`visibleDescendantFrames`, line 117), and fails listing every frame whose
`maxX` exceeds the sidebar width + 0.5 pt (NSClipView descendants excluded —
scroll content legitimately overflows). Copy this pattern whenever "does it
fit" is the question.

### 5. `swift run framer benchmark lut` — the performance instrument

```sh
swift run framer benchmark lut \
  --input docs/sample.jpg \
  --lut assets/luts/ANDP-KodakPortra800-32bit.CUBE \
  --preview-base 1200 \
  --iterations 10 \
  --warmup 2
```

Flags (verified against `Sources/FramerCLI/Commands/BenchmarkCommand.swift`):
`--input`, `--lut`, `--intensity` (0…1, default 1.0), `--preview-base` (omit
to benchmark full-export size), `--iterations` (default 10), `--warmup`
(default 2). It prints mean/median/min/max per backend, the CPU-vs-Auto(Metal)
speedup, and — when Metal is available — a per-stage split (`upload`, `gpu`,
`readback`) that tells you WHERE the time goes. Verified run 2026-07-09
(preview-base 600, 2 iterations): CPU mean 70.71 ms, Auto(Metal) 19.10 ms,
speedup 3.70×, readback 26 ms > gpu 3.2 ms — i.e. readback dominates, matching
README's noted next-optimization target.

The methodology this command encodes IS the house benchmark discipline; see
recipe (d) below.

### 6. Console fallback logs — the "which path ran" tracer

`ShaderRenderer.gpuOrCPU` prints one line per effect invocation
(`Sources/FramerCore/Processing/ShaderRenderer.swift:84,87`):

```
[ShaderRenderer] GPU path ✓  applyCrimewave(to:params:intensity:)
[ShaderRenderer] CPU fallback (Metal error: ...) — applyCrimewave(...)
```

Only `MetalEffectError` triggers fallback; any other error propagates so real
bugs surface. Interpretation: ONE effect falling back = that effect's pipeline
or atlas is broken; MANY effects falling back simultaneously = the whole Metal
library failed to build (classic cause: a typo in a single `.metal` file
breaks the combined runtime source-compile — `docs/gpu-migration-mac-resume.md:303–307`).

### 7. EffectPreviewComparator — shipped but unwired

`Sources/FramerCore/Effects/Utilities/EffectPreviewComparator.swift` computes
a mean absolute channel delta between preview and export renders,
**normalized to 0–1** (each per-channel delta divided by 255 — different units
from EffectGPUParityTests' 0–255!). As of 2026-07-09 it has zero call sites
outside its own file, and its `previewExportDefault` tolerance of 0.6
normalized (= mean 153/255 bytes) is too loose to discriminate anything —
treat the constant as unvetted if you wire it up. Candidate harness only.

### 8. Xcode Thread Performance Checker — available, not wired

Xcode's runtime Thread Performance Checker (flags main-thread I/O, priority
inversion) is not enabled in any checked-in scheme (verified: no such setting
in `Framer.xcodeproj/xcshareddata/xcschemes/*.xcscheme`), and the xcodebuild
tier is currently broken on the primary machine anyway (revoked cert + missing
Metal Toolchain — see **framer-campaign-restore-validation**). Optional manual
diagnostic for hangs once that tier is repaired; not part of today's toolbox.

## Analysis recipes

Each recipe: when to use → steps → a worked example from this repo's history.
Full incident narratives live in **framer-failure-archaeology**.

### (a) Parity-delta analysis: from a failing number to a line of code

**When:** a parity test fails, or an effect "renders differently" between app
and CLI, or after touching any effect's CPU or GPU implementation.

**Steps:**
1. Run `scripts/parity-report.sh`. Record mean and max deltas from the failure
   message (every assertion interpolates them, e.g. "PixelSort mean delta too
   high (37.2)").
2. Place the number in the interpretation bands (instrument 1). Under ~20:
   suspect legitimate divergence; 50+: suspect a semantic bug.
3. For a semantic bug, do NOT stare at pixels — read the two scoring/decision
   functions side by side (CPU Swift vs `.metal` MSL) and diff their math
   term by term: value ranges, normalization, comparison direction, blend
   semantics.
4. If parameters seem ignored (output insensitive to sliders), suspect uniform
   struct layout drift instead — that's **framer-metal-pipeline-reference**
   territory.
5. Fix, re-run, record before/after deltas in the commit message.

**Worked example — the pixel-sort `.hue` bug (fixed in 761fae6, 2026-04-16;
the CPU loop involved was later deleted outright by PR #12, merged 2026-07-09,
so read this as method, not as current file contents):**
CPU pixel-sorting left blue-dominant regions untouched while GPU sorted them.
Reading `GlitchRenderer.pixelScore` next to `psSortValue` in `PixelSort.metal`
pinpointed two term-level divergences, documented at the time in a doc comment
in `GlitchRenderer.swift`:
`.brightness` returned Rec.709 luminance (identical to `.luminance`) instead
of `max(r,g,b)`, and `.hue` returned the raw HSV sector value in **[-1, 6)**
instead of a normalized [0, 1] hue — negative scores always fell below any
positive threshold, so blue hues never sorted on CPU. No eyeballing
distinguishes "different aesthetic" from "unnormalized score"; the
side-by-side read does. The companion `amount`-semantics divergence (CPU
rank-scaling vs GPU mix-blend) was fixed in f21a6fe the same day.

### (b) "Algorithms suspiciously identical": byte-compare across variants

**When:** N variants of an effect (dither algorithms, presets, modes) are
supposed to look different but users/tests can't tell them apart — or you just
added a variant and want proof it does something.

**Steps:**
1. Render the same input through each variant.
2. Compare outputs pairwise with the parity `compare()` metric (or any
   byte-diff). Identical bytes (mean delta 0) between differently-named
   variants is the smoking gun — visual similarity judgments are worthless
   here because dither patterns all "look noisy".
3. Trace the shared code path for the term that was supposed to vary.

**Worked example — the IGN phase collision (fixed in 2a2ecba, 2026-04-14,
"per-algorithm noise phase in dither shader so variants produce distinct
output"):** the GPU approximates error-diffusion dithers (Floyd-Steinberg,
Stucki, …) with Interleaved Gradient Noise (IGN) thresholds. All algorithms
sampled the noise field at the SAME position, differing only by amplitude —
several produced byte-identical output despite shipping under different
names. Fix: a per-algorithm spatial phase offset on the noise sample, e.g.
floyd `(7.31, 11.17)` × 0.85, stucki `(13.49, 17.83)` × 0.80 — the table and
the explanatory comment live at
`Sources/FramerCore/Effects/Metal/Dither.metal:241–260`. The regression fence
is the existing inequality-style tests (e.g. reverse-flag and randomness tests
in EffectGPUParityTests assert outputs DIFFER by mean delta > threshold).

### (c) Half-texel / grid-alignment analysis

**When:** a GPU port of a CPU integer-pixel loop shows a moderate,
*structured* parity delta (pattern shifted, moiré, dots drifting) rather than
random noise. Typical magnitude: mean delta in the tens.

**Steps:**
1. Confirm the delta is spatial: render both outputs and diff — a uniform
   color error is a color-math bug; a shifted pattern is an alignment bug.
2. Check how the shader derives coordinates. `in.uv` arrives at **fragment
   centers** (x + 0.5 texels); CPU loops use integer `x / width`. Any
   `sin(ux * frequency)`-style pattern math amplifies that half-texel into a
   visible phase shift.
3. Pin the shader to the integer grid:
   `int2 pixel = int2(floor(in.uv * resolution))`, then compute pattern
   coordinates from `pixel`, and sample the source at
   `(float2(pixel) + 0.5) / resolution`.

**Worked example — halftone mean-delta 32/255:** the halftone shader's dot
pattern drifted ~half a dot versus CPU, producing a mean parity delta of
32/255. The fix and the measured before-number are recorded in the shader
itself at `Sources/FramerCore/Effects/Metal/Halftone.metal:60–70` ("Pin to the
integer pixel grid… Mean delta on the parity test was 32/255 before this
fix."). General rule: any shader ported from a CPU integer-pixel loop must
floor `uv * resolution` before doing pattern math.

### (d) Performance claims: the benchmark discipline

**When:** you're about to write "faster", "optimized", or any number with
"ms" in it.

**Rules (all four, every time):**
1. **Warmup** — first iterations pay for pipeline compilation and cache fill;
   exclude them (`--warmup 2` minimum).
2. **Multiple iterations, report distribution** — mean/median/min/max, never a
   single sample (`--iterations 10`).
3. **Exact inputs recorded** — file, dimensions, LUT/params, machine, date.
4. **Both modes** — preview (`--preview-base 1200`) AND full export (omit the
   flag); GPU wins are usually much larger at export size.

**Worked example — the README LUT record (README.md:137–166), the house
template for reporting any performance result:** "Measured on `2026-04-01`
with `docs/sample.jpg` (`3000x1987`) and
`assets/luts/ANDP-KodakPortra800-32bit.CUBE`: Preview — CPU 233.04 ms,
Auto(Metal) 32.44 ms, speedup 7.18×; Full export — CPU 1964.00 ms, Auto(Metal)
78.16 ms, speedup 25.13×." Dated, exact inputs, both modes, plus a stated next
step (readback dominates preview cost — confirmed by the per-stage split in
the verified 2026-07-09 run: readback 26 ms vs gpu 3.2 ms). Numbers are
machine-dependent; only compare before/after on the same machine.

### (e) "Is the GPU path even running?"

**When:** an effect looks subtly wrong or slow, before ANY other debugging —
you may be staring at the CPU fallback, not the GPU code you're editing.

**Steps:**
1. Run the app or CLI from a terminal and watch for
   `[ShaderRenderer] CPU fallback (Metal error: ...)` lines (instrument 6).
   One effect falling back = that effect's problem; all effects falling back =
   the whole Metal library failed to compile (check for a typo in any
   `.metal` file — one bad file breaks the combined runtime compile).
2. Run `scripts/parity-report.sh` and read the **skipped** count. Exit code 2
   means the parity suite never exercised Metal on this host — a green run
   proved nothing about the GPU.
3. Run `scripts/env-doctor.sh` to rule out environment causes (though note:
   the SPM tier compiles shaders even without the Metal Toolchain component;
   only a missing Metal *device* forces fallback at runtime).
4. Only after confirming the GPU path executes, start reading shader code.

This is the cheapest discriminating experiment there is; the full
symptom→triage index lives in **framer-debugging-playbook**.

## Reporting results: the evidence bar

Any claim that a rendering or performance change works must state:

- [ ] The instrument used (test name, script, or benchmark command).
- [ ] Before AND after numbers (mean/max delta, ms, counts) — not adjectives.
- [ ] Exact inputs (fixture, dimensions, params) and date for benchmarks.
- [ ] Skip count if the parity suite was involved (0 skips, or say why not).
- [ ] Any tolerance change justified by an inspected diff, in the same commit.

Evidence standards for *tests in general* (and the snapshot-hash refresh
protocol) are owned by **framer-validation-and-qa**; change gating and the
no-blind-hash-refresh house rule by **framer-change-control**.

## Provenance and maintenance

Everything above was verified on 2026-07-09 against commit 48d85a5 on `main`,
on the primary machine (Apple Silicon, macOS 26, Swift 6.3.3, Xcode 26.6 build
17F113, with the Metal Toolchain component — build 17F109 — uninstalled and a
revoked signing cert). All three
scripts were executed and their outputs confirmed; the benchmark command was
run end-to-end; the 27-test parity suite passed with 0 skips.

Facts that may drift, with one-line re-verification commands:

| Claim | Re-verify with |
|---|---|
| 273 SPM tests / suite sizes | `scripts/test-inventory.sh` |
| 27 parity tests, 0 skips here | `scripts/parity-report.sh` |
| Parity metric + tolerances | `grep -n 'XCTAssertLessThan(mean' Tests/FramerCoreTests/EffectGPUParityTests.swift` |
| Interpretation bands 12–20 / 50+ | `sed -n '285,301p' docs/gpu-migration-mac-resume.md` |
| Fallback log lines at :84/:87 | `grep -n 'CPU fallback' Sources/FramerCore/Processing/ShaderRenderer.swift` |
| Benchmark flags/defaults | `swift run framer benchmark lut --help` |
| README benchmark template | `sed -n '137,166p' README.md` |
| Halftone 32/255 comment | `grep -n '32/255' Sources/FramerCore/Effects/Metal/Halftone.metal` |
| Dither phase table | `sed -n '241,260p' Sources/FramerCore/Effects/Metal/Dither.metal` |
| pixelScore CPU loop stays deleted (PR #12, 2026-07-09) | `grep -n 'pixelScore' Sources/FramerCore/Effects/Renderers/GlitchRenderer.swift` (expect NO hits — worked example above is historical) |
| EffectPreviewComparator still unused | `grep -rn EffectPreviewComparator Sources Tests \| grep -v Utilities/EffectPreviewComparator` |
| Metal Toolchain status | `xcodebuild -showComponent metalToolchain` |
| Signing cert status | `security find-identity -v -p codesigning` |
| LFS file count (168) | `git lfs ls-files \| wc -l` |
| Incident commits exist | `git show -s --oneline 2a2ecba f21a6fe 761fae6 a757e67 4cf8ec2` |

If a re-verification command fails, fix THIS file in the same change that
moved the fact — this skill library is the source of truth (CLAUDE.md routes
here since its 2026-07-09 rewrite; see **framer-docs-and-writing**).
