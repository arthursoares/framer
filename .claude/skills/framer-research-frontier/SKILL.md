---
name: framer-research-frontier
description: Load when asked "what should we work on next", "where can this project advance the state of the art", "is X worth researching", "can we claim Y publicly", or when evaluating frontier work — true blue-noise dithering, Metal-texture-resident preview, video support revival, retiring the CPU render path, deferred Grainrad features (chromatic aberration, JPEG-glitch, modulation overlays), or parity-verification as a discipline. Also owns the research methodology (evidence bar, predicted-numbers-first, adversarial review, plan lifecycle) and external positioning / claim discipline (what is genuinely novel here, what must be proven before it is said out loud).
---

# framer-research-frontier

Open problems where this repo can push past current state of the art, the methodology that
turns a hunch into an accepted result here, and the rules for what may be claimed publicly.

**The maintainer's definition of "beyond state of the art" (ruling, 2026-07-09):**
Grainrad-class GPU effect quality, **verified by measurement — never judged by eye**.
"Grainrad" is the reference hobby shader tool whose WGSL effect notes seeded this repo's
GPU effects program (cited throughout `docs/gpu-migration-plan.md` and
`docs/gpu-migration-mac-resume.md`). Grainrad-class tools have great-looking shaders but
no verification story: no CPU/GPU parity, no preview/export agreement checks, no numbers.
This repo's edge is that it verifies.

## When NOT to use this skill

| You are trying to... | Use instead |
|---|---|
| Actually execute the effects-quality program (add/tune an effect) | framer-campaign-gpu-effects-quality |
| Apply day-to-day evidence rules (what counts as a passing test) | framer-validation-and-qa |
| Decide/record an architectural invariant (e.g. the CPU-path decision itself) | framer-architecture-contract |
| Understand Metal mechanics (uniforms, textures, adding a shader) | framer-metal-pipeline-reference |
| Understand dithering/blend/LUT theory as implemented | framer-image-processing-reference |
| Run measurements (benchmark recipes, analysis scripts) | framer-diagnostics-and-proof |
| Look up an incident's full story | framer-failure-archaeology |
| Check which docs are stale / write a plan document | framer-docs-and-writing |

---

## Frontier problems

Each problem: why current SOTA fails → this repo's specific asset → first three steps in
THIS repo → falsifiable "you have a result when…" milestone. Facts verified 2026-07-09 at
commit 48d85a5 unless noted.

### 1. Measurement-verified effect parity as a discipline

**Why SOTA fails.** Hobby/creative shader tools (Grainrad-class) ship one GPU path and
judge output by eye. Nothing guarantees the preview matches the export, or that a refactor
didn't silently change the look. There is no published discipline for "this effect renders
what it rendered yesterday, provably."

**This repo's assets (all verified in code):**
- **Dual render paths with a strict fallback contract**: `ShaderRenderer.gpuOrCPU`
  (Sources/FramerCore/Processing/ShaderRenderer.swift:75-90) runs the GPU path and falls
  back to CPU only on `MetalEffectError`; any other error propagates. The CPU path is the
  de-facto reference implementation.
- **A parity harness**: Tests/FramerCoreTests/EffectGPUParityTests.swift — 27 tests
  asserting mean/max per-channel byte deltas per effect (e.g. color grades mean < 6/255,
  ASCII mean < 25/255), self-skipping when Metal is unavailable. Ran live 2026-07-09:
  `swift test --filter EffectGPUParityTests` → "Executed 27 tests, with 0 failures".
- **A WYSIWYG contract**: scale-sensitive layers (Dither, LUT, Shader) take a
  `previewBaseDimension` so pattern density matches between preview and export; the
  rationale comment is at Sources/FramerCore/Processing/FrameProcessor.swift:40-47.
  ("WYSIWYG" = what-you-see-is-what-you-get: preview pixels predict export pixels.)
- **A shipped-but-unwired comparator**:
  Sources/FramerCore/Effects/Utilities/EffectPreviewComparator.swift computes mean
  absolute channel delta between two renders. As of 2026-07-09 it has **zero call sites**
  outside its own file, and its `previewExportDefault` tolerance is 0.6 in normalized 0–1
  units (≈153/255) — effectively vacuous. Wiring and recalibrating it is open work.

**The gap.** Coverage is uneven: `GPUEffectKind.userFacingCases`
(Sources/FramerCore/Effects/Models/GPUEffectKind.swift:42-49) exposes 12 bucket effects,
but Tests/FramerCoreTests/GPUEffectBucketDispatchTests.swift has only 4 smoke/dispatch
tests for the whole bucket family — no per-effect parity for voronoi, vhs, matrixRain,
dots, blockify, threshold, edgeDetection, crosshatch, waveLines, noiseField, contour.
History says every new shader port shipped 1–3 parity bugs (see framer-failure-archaeology:
pixel-sort took 6 fix rounds across 3 PRs).

**First three steps:**
1. Build the coverage matrix: every case in `GPUEffectKind.userFacingCases` plus the
   `.shader`/`.dither` layer effects, vs the test list from
   `grep -n "func test" Tests/FramerCoreTests/EffectGPUParityTests.swift`.
2. Wire `EffectPreviewComparator` into one real preview-vs-export test for a
   scale-sensitive layer (dither is the sharpest case), and recalibrate
   `previewExportDefault` to a meaningful tolerance — predict the number before running.
3. Add one bucket-effect parity test (pick voronoi or vhs) following the
   EffectGPUParityTests pattern (`requireMetal()` skip helper, mean/max delta asserts).

**You have a result when:** every user-facing effect has either a CPU/GPU parity test
with a stated tolerance or a documented intentional divergence (the cmykHalftone
precedent — its CPU fallback deliberately degrades to mono clustered dot, recorded in
docs/gpu-migration-plan.md), AND a preview/export comparison runs through
EffectPreviewComparator. Falsified the day a new effect merges without one.

### 2. Metal-texture-resident preview (README's own stated next step)

**Why SOTA fails / why here.** The repo's preview pipeline renders on GPU, then blocks on
GPU→CPU readback ("readback" = copying the rendered texture back to CPU memory) plus
`CGImage` reconstruction on every LUT change. README.md ("Next LUT performance step",
written 2026-04-01) names keeping preview output as a Metal texture as the next
high-impact optimization, deferred because it touches preview/UI architecture.

**This repo's asset.** A staged benchmark already exists:
`swift run framer benchmark lut --input docs/sample.jpg --lut assets/luts/ANDP-KodakPortra800-32bit.CUBE --preview-base 1200 --iterations 10 --warmup 2`
(Sources/FramerCLI/Commands/BenchmarkCommand.swift). It reports per-stage Metal timings —
upload / gpu / readback — via `LUTMetalRenderer.applyProfiled`. README records the dated
baseline (2026-04-01, docs/sample.jpg at 3000×1987): preview CPU 233.04 ms vs Metal
32.44 ms (7.18x); full export 1964.00 ms vs 78.16 ms (25.13x). Both input files are
checked in (docs/sample.jpg, assets/luts/ANDP-KodakPortra800-32bit.CUBE).

**First three steps:**
1. Re-run the exact README command on current hardware; record the staged breakdown to
   establish what fraction of the 32 ms-class preview time is readback + CGImage
   reconstruction. (If readback is a small fraction, the whole hypothesis dies here —
   that is the point.)
2. Prototype `LUTMetalRenderer` returning an `MTLTexture` and displaying it without CPU
   readback (CIImage-backed layer or MTKView). Expect this to touch
   PreviewViewModel/AppState — the deferral reason was UI architecture, not LUT internals.
3. Measure end-to-end preview latency before/after with the same command plus a UI-level
   timing probe; run the parity/no-regression check with EffectPreviewComparator.

**You have a result when:** LUT preview latency on the README's exact input measurably
drops below the current Metal readback path (state the predicted number first, per the
methodology below), with no visual regression by measurement. Publish only in the
README-benchmark format (see External positioning).

### 3. True blue-noise dithering (void-and-cluster mask)

**Why SOTA fails.** Grainrad's "Floyd-Steinberg" — and this repo's port of it — is not
error diffusion at all. Error diffusion is inherently serial (each cell's error feeds the
next), so fragment shaders approximate it with IGN — Interleaved Gradient Noise (Jimenez,
SIGGRAPH 2014) — scaled and phase-shifted per algorithm. This repo documents its own
approximation honestly: Sources/FramerCore/Effects/Metal/Dither.metal (~lines 240–310)
carries the full per-algorithm coefficient/phase table, and the `DITHER_IGN` case comment
says outright: *"If a true void-and-cluster blue noise mask is ever added,
DITHER_BLUE_NOISE switches to it and this offset can drop."* Today `DITHER_BLUE_NOISE`
is pure IGN — not real blue noise. ("Blue noise" = noise whose energy sits in high
spatial frequencies, so dithered output has no low-frequency clumping;
"void-and-cluster" = Ulichney's 1993 offline algorithm for generating such masks.)

**This repo's asset.** The gap is explicit and localized (one shader case + one texture
resource), and the quality harness to lock the result already exists (dither tests like
`testDitherBayerOutputIsBinaryBW` assert output invariants).

**First three steps:**
1. Generate a void-and-cluster mask offline (64×64 or 128×128), commit it as a texture
   resource — mind the per-file SPM resource rules (owned by
   framer-metal-pipeline-reference).
2. Add a mask-sampling path for `DITHER_BLUE_NOISE` in Dither.metal, keeping `DITHER_IGN`
   as-is; wire the texture through the dither renderer's aux-texture slots.
3. Write the measurement before shipping: radially-averaged power spectrum of the
   thresholded output of a flat 50%-gray input, IGN vs mask. Blue noise must show
   measurably lower low-frequency energy. (Measurement recipes belong in
   framer-diagnostics-and-proof.)

**You have a result when:** the spectral measurement shows blue-noise characteristics
(quantified low-frequency energy reduction vs IGN, numbers stated in advance) AND a test
locks the new output (binary-BW invariant + statistical or hash lock). If the spectrum
does not measurably differ, the mask is not an improvement — do not ship it on vibes.

### 4. Video support revival (candidate — unmerged, gate on product intent)

**Status (verified 2026-07-09):** branch `origin/feature/video-support` is 19 commits
ahead / 255 behind main. It contains a full pipeline: `VideoProcessor` actor using
`AVAssetWriter` (Sources/FramerCore/Processing/VideoProcessor.swift on the branch),
`CIFilterPipeline`, codec picker, trim UI, plus branch-only design docs (commits
0c42b4d, c62699c). The tip commit is `2df2fa4 "wip: GPU dithering, pre-scale
optimization, and memory fixes for video export"` — it parked on memory problems, and
the failure mode is stated in its own commit subject.

**Why it is frontier-adjacent.** Frame-by-frame export-quality styling with this layer
stack (dither, LUT, shaders, overlays) is something neither hobby shader tools nor
consumer editors do with verification. But it is primarily a product decision; the
maintainer has not green-lit it.

**First three steps:**
1. Read the branch's design + implementation-plan docs (they exist only on the branch:
   `git show origin/feature/video-support --stat` from 0c42b4d/c62699c).
2. Feasibility spike on integration: 255 commits behind means the entire Effects bucket
   architecture landed after this branch; expect a restart-with-reference rather than a
   rebase. Do not merge it as-is (house rule: humans decide merges —
   framer-change-control).
3. Before writing code, measure the WIP branch's peak memory on an N-second test clip so
   the "memory fixes" problem is quantified, not remembered.

**You have a result when:** an N-second clip exports with a stated layer stack under a
stated peak-memory bound, measured, on main. Until then this is a parked branch — never
describe video support as a feature.

### 5. The retire-the-CPU-path decision study (open architectural question)

**The question (maintainer, 2026-07-09):** "we will always have Metal available" — is the
CPU render path needed at all? Note the tension already in the record:
docs/gpu-migration-plan.md's Target section says "GPU-only — CPU renderers deleted as
each bucket lands… `MTLCreateSystemDefaultDevice()` is always available", yet the shipped
code kept CPU fallbacks everywhere. Per the maintainer's ruling, CPU/GPU parity is
**current mechanical reality, not eternal doctrine**: keep EffectGPUParityTests green
while the CPU path exists; do not canonize parity as sacred; do not treat it as retired.
The decision itself is owned by framer-architecture-contract; this skill owns the study.

**What the CPU path uniquely provides today (all verified in code):**

| Capability | Evidence |
|---|---|
| Riemersma (Hilbert-curve) dither — inherently serial, no GPU port | DitherGPURenderer.swift:148-152 throws `metalUnavailable` to force CPU; test `testDitherRiemersmaRoutesToCPU` |
| The reference implementation parity tests measure against | EffectGPUParityTests compares GPU output to CPU output — retire CPU and the current definition of "correct" goes with it |
| Headless/Metal-less operation (CI sandboxes) | `requireMetal()` skips parity tests when `MetalEffectLibrary.shared == nil` ("likely CI sandbox"). NOTE: GPUEffectKind.swift's doc comment still claims "the CPU loop in GlitchRenderer as a headless-host fallback", but PR #12 (merged 2026-07-09) deleted that loop — the Glitch/EdgeField buckets are GPU-only and throw; the comment is stale in code |
| LUT CPU reference used by the benchmark | LUTRenderer.applyCPU / applyCPUReference; BenchmarkCommand measures CPU as the baseline |
| Known intentional divergence to resolve either way | cmykHalftone CPU fallback is deliberately degraded (mono 6×6 clustered dot; docs/gpu-migration-plan.md) |

**First three steps:**
1. Complete the inventory: grep every `gpuOrCPU` / `MetalEffectError` fallback site and
   every CPU-only algorithm; classify each as "reference", "capability", or "dead weight".
2. Define the replacement verification strategy if retired: golden reference images
   generated once and committed (per snapshot discipline — never blind-refreshed;
   framer-validation-and-qa), plus statistical invariant tests (binary-BW, palette-only,
   dimensions), possibly keeping `applyCPUReference` solely as a benchmark baseline.
3. Write an ADR (Architecture Decision Record): both options with costs — maintenance tax
   of dual paths vs losing the executable reference — and put it in front of the
   maintainer.

**You have a result when:** a written ADR-style decision exists in the repo and the
maintainer has signed it — either direction counts as the result. Until then, new
effects still need matching CPU semantics and a parity test.

### 6. Deferred Grainrad features (each gated on product intent)

docs/gpu-migration-plan.md, section "Algorithms still NOT ported" (verified): modulation
overlays (wave / grid / radial / horizontal / rgbSplit on top of the threshold), epsilon
glow post-pass, JPEG-glitch effects (block-shift, channel-swap, scanline-offset), and
chromatic aberration as part of the dither pass. The plan's own judgment: "Most of these
probably belong as separate effect layers rather than dither sub-modes."

None of these are green-lit (open question to the maintainer). When one is: it goes
through framer-campaign-gpu-effects-quality's add-an-effect pipeline, with the problem-1
discipline (parity test + reference comparison) from day one — not retrofitted. The
milestone per feature is the same as problem 1's: shipped with its verification, or not
shipped.

---

## Methodology: what turns a hunch into an accepted result here

### The evidence bar

1. **One mechanism must explain ALL observations, including the negatives.** The house
   cautionary tale is the CGBitmapContext saga: three fix attempts in one day because the
   first two explanations didn't cover every failing input (full story in
   framer-failure-archaeology). If your root cause doesn't explain why the thing
   *sometimes worked*, you don't have the root cause. The gold-standard worked example is
   PR #11's writeup (merged 2026-07-09): complete QoS priority-inversion mechanism (actor
   escalation → CoreGraphics Default-QoS workers) before a one-line fix.
2. **State predicted numbers BEFORE running.** Parity work predicts a mean-delta bound
   per effect (the committed tolerances — 6/255 for color grades, 25/255 for ASCII — are
   calibrated predictions, with per-test comments justifying looseness). Performance work
   predicts a latency delta before benchmarking. A number you predicted and hit is
   evidence; a number you found and rationalized is a story.
3. **Survive adversarial review.** House pattern: dispatch 2–3 parallel review agents
   with **deliberately different prompts** (bug-hunter / language-idiom / architecture).
   At sidebar-harmony pass 3 this found real bugs the author had missed — a task
   dictionary leak, the CPU/GPU pixelSort divergence, and a palette identity flicker —
   with near-zero duplicate findings because the prompts differed. (Recorded in
   .sisyphus/notepads/sidebar-harmony/learnings.md, "Review process" section; lesson
   copied here because notepads look disposable.) Judged "worth the token spend."

### The idea lifecycle

Dated plan → TDD execution → learnings notepad → CHANGELOG → (if superseded) documented
retirement. Concretely:

1. **Plan**: dated markdown in `docs/plans/` or `docs/superpowers/plans/` (templates and
   house style owned by framer-docs-and-writing).
2. **Execute**: strict TDD, one task per commit (gating rules owned by
   framer-change-control).
3. **Learnings**: `.sisyphus/notepads/<topic>/learnings.md` updated at checkpoints.
4. **Record**: CHANGELOG.md `[Unreleased]` entry (Keep-a-Changelog format).
5. **Retire honestly when superseded.** Worked example:
   `docs/plans/2026-04-01-metal-dither-plan.md` was never executed as written — GPU
   dithering shipped through the Effects bucket architecture
   (Sources/FramerCore/Effects/Metal/Dither.metal + DitherGPURenderer) instead of the
   plan's `Sources/FramerCore/Processing/Metal/` layout, which does not exist on main
   (verified). A dead plan left looking alive costs the next engineer a day; the
   staleness ledger lives in framer-docs-and-writing.

### Where good ideas historically came from (verified provenance)

| Source | Example |
|---|---|
| Reference implementations studied, not copied | Grainrad notes drive docs/gpu-migration-plan.md (techniques reimplemented, attribution headers per the plan); Acerola-inspired shader layer (PR #5, docs/superpowers/plans/2026-04-02-acerola-shader-layer-handoff.md) |
| Post-pass audits | Sidebar harmony passes each ended with an audit that seeded the next pass |
| Parallel review agents | The pass-3 findings listed above |
| User smoke tests | "Dithering doesn't have the presets" report → hiding half-shipped bucket variants from the picker (doc comment in GPUEffectKind.swift:20-40) |

---

## External positioning: what may be said publicly

### Novel vs known — be honest about which is which

| Aspect | Status |
|---|---|
| Layer-fold composition architecture | **Common** — every editor has one; not a claim |
| Dual-path effects with enforced CPU/GPU parity tests + WYSIWYG previewBaseDimension contract | **Uncommon** — this is the defensible technical story, and it strengthens as problem 1 closes |
| The AI-assisted-development experiment itself | **Notable** — and already public: README.md line 5 declares "created using Claude Code as an experiment in AI-assisted development" |
| True blue-noise dithering, video support, texture-resident preview | **Candidates** — not implemented / unmerged; may not be claimed |

### Claim discipline

Any public performance or quality claim must follow the README-benchmark pattern
(README.md "LUT Benchmark" section is the template): **dated**, exact input file **with
dimensions** ("2026-04-01, docs/sample.jpg, 3000×1987"), exact secondary inputs (the
.CUBE file), warmup + iteration counts, **both modes** (preview and export, CPU and
Metal), and the exact copy-pasteable command. A number without all of these is marketing,
not a claim.

### Reproducibility standard

A claim is one someone else can re-run from a clean clone (`git lfs pull` required —
overlays are LFS pointers otherwise; setup owned by framer-build-and-env). Known
anti-pattern, do not repeat: the example output images committed under `docs/examples/*.jpg`
have no committed script or command that regenerates them (verified by grep, 2026-07-09)
— so nobody can tell if they still reflect the code. Every new published artifact ships
its generation command.

### The no-oversell ledger (as of 2026-07-09, commit 48d85a5)

- Video support: parked branch, 255 behind — **not a feature**.
- Blue-noise dither: the UI says "Blue Noise" but the shader is IGN — do not describe it
  as true blue noise externally until problem 3 lands.
- PRs #11 (QoS fix) and #12 (parameter consistency) MERGED 2026-07-09 (`b06601c`,
  `f2c9521`) — their fixes are now shipped behavior on main. PR #1 was CLOSED unmerged
  2026-07-09 (was 295 commits stale).
- E2E/UI tests: none exist on main (revival is framer-campaign-restore-validation).
- Versioning is inconsistent (CHANGELOG says 2.0.0, git tags stop at v1.2.0) — do not
  cite a version number publicly without checking `git tag` (ledger in
  framer-docs-and-writing).
- README.md is stale; CLAUDE.md was rewritten 2026-07-09 to route to this skill
  library, which is the source of truth (staleness ledger: framer-docs-and-writing).
- House rule (framer-change-control): no autonomous merges or pushes — research results
  become "accepted" only when a human merges them.

---

## Provenance and maintenance

All claims verified 2026-07-09 against main @ 48d85a5 by reading the cited files, running
`swift test --filter EffectGPUParityTests` (27 tests, 0 failures, Apple Silicon), and
read-only git/gh commands. Maintainer rulings dated 2026-07-09 are recorded as such.
Volatile facts and their re-verification one-liners:

| Fact | Re-verify with |
|---|---|
| gpuOrCPU falls back only on MetalEffectError | `grep -n "catch let error as MetalEffectError" Sources/FramerCore/Processing/ShaderRenderer.swift` |
| 27 parity tests, current tolerances | `swift test --filter EffectGPUParityTests` and `grep -n "XCTAssertLessThan" Tests/FramerCoreTests/EffectGPUParityTests.swift` |
| EffectPreviewComparator still unwired | `grep -rn "EffectPreviewComparator" Sources Tests --include="*.swift"` (only its own file → still unwired) |
| userFacingCases hides ascii/halftone/dithering | `grep -n "userFacingCases" -A 8 Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| DITHER_BLUE_NOISE is still IGN; void-and-cluster note | `grep -n "void-and-cluster" Sources/FramerCore/Effects/Metal/Dither.metal` |
| Deferred Grainrad feature list | `grep -n "Algorithms still NOT ported" -A 12 docs/gpu-migration-plan.md` |
| Staged LUT benchmark exists (upload/gpu/readback) | `grep -n "MetalStageStats\|readbackMS" Sources/FramerCLI/Commands/BenchmarkCommand.swift` |
| README benchmark numbers + "next step" text | `grep -n "Next LUT performance step" -B 20 README.md` |
| video-support branch state | `git rev-list --count origin/main..origin/feature/video-support` (19) and `git log -1 --oneline origin/feature/video-support` (tip 2df2fa4 "wip: …") |
| Riemersma forces CPU | `grep -n "riemersma\|metalUnavailable" Sources/FramerCore/Effects/Renderers/DitherGPURenderer.swift` |
| Open PR set | `gh pr list --state open` (as of 2026-07-09: empty — #1 CLOSED, #11/#12 MERGED) |
| Retired-plan example still unexecuted | `ls Sources/FramerCore/Processing/Metal` (should not exist) |
| Review-agents lesson source | `grep -n "Three parallel review agents" .sisyphus/notepads/sidebar-harmony/learnings.md` |
