---
name: framer-campaign-gpu-effects-quality
description: EXECUTABLE campaign plan for raising Framer's GPU effects (dither, pixel sort, halftone, textCell/edgeField/glitch buckets) to Grainrad-class quality verified by measurement. Load when asked to tune/improve/re-tune an effect's look, close CPU/GPU parity gaps, implement deferred Grainrad features (blue-noise mask, modulation overlays, JPEG-glitch, chromatic aberration), acquire reference renders, or decide what "effect quality" means here. Keywords - Grainrad, parity, EffectGPUParityTests, dither coefficients, pixel sort streak, cmykHalftone, benchmark lut, reference frames, tuning loop.
---

# Campaign: Grainrad-class GPU effect quality, verified by measurement

**Mission (maintainer ruling, 2026-07-09):** "Beyond state of the art" for this
project means GPU effect quality on par with Grainrad (a free WebGPU effects
studio at grainrad.com whose techniques inspired several Framer shaders),
**verified by measurement — never judged by eye**.

This skill is the executable campaign: decision-gated phases, exact commands,
expected numbers, a ranked gap menu, and fenced wrong paths. It tells you what
to do next and how to prove you did it. For the theory behind the effects, see
**framer-image-processing-reference**. For Metal mechanics (uniforms, shader
loading, adding an effect), see **framer-metal-pipeline-reference**. For
measurement tooling and analysis recipes, see **framer-diagnostics-and-proof**.

Jargon used throughout:

- **Parity test** — a test asserting the GPU (Metal shader) and CPU (Swift
  loop) implementations of one effect produce nearly-identical pixels, within
  a per-effect mean-delta tolerance (bit-exactness is impossible by design).
- **Bucket effect** — a `.gpuEffect` layer variant dispatched through one of
  four shader "buckets" (TextCell, PrintSampling, EdgeField, Glitch), distinct
  from the older `.shader`/`.dither` layer types. Same shaders, leaner params.
- **IGN** — Interleaved Gradient Noise (Jimenez 2014), the procedural noise
  Framer uses to approximate serial error-diffusion dithering on the GPU.
- **WGSL** — WebGPU Shading Language; the language of Grainrad's reference
  shaders (Framer's are MSL, written fresh — see the licensing fence in P2).

## Standing rules (binding on every phase)

1. **No autonomous merges or pushes.** Branch, commit locally, open PRs when
   asked; a human decides every merge to main (house rule — see
   framer-change-control).
2. **Never blind-refresh snapshot or parity baselines.** When a number shifts
   unexpectedly, read the pixels and explain the shift before accepting; the
   refresh lands in the same commit as the change that caused it.
3. **CPU/GPU parity is current mechanical reality, not eternal doctrine.**
   `ShaderRenderer.gpuOrCPU` (Sources/FramerCore/Processing/ShaderRenderer.swift,
   ~lines 72–90) falls back to CPU **only** on `MetalEffectError`; while the
   CPU path exists, EffectGPUParityTests must stay green. But "retire the CPU
   path entirely" is an OPEN architectural decision (the maintainer questions
   whether CPU is needed at all — owned by framer-architecture-contract and
   framer-research-frontier). Do not canonize parity as sacred; do not treat
   it as retired. Open PR #12 already deletes the Glitch/EdgeField CPU pixel
   loops (−594 lines) — check its merge state before any parity work (P0).
4. **Metric before change.** Every tuning change needs a metric defined and a
   baseline number recorded BEFORE the code changes. Before/after image grids
   are illustration, never acceptance evidence.
5. The `xcodebuild` app-test tier is broken on the maintainer's machine
   (revoked signing cert — `CSSMERR_TP_CERT_REVOKED` — + missing Metal
   Toolchain; cert state and remediation owned by
   framer-campaign-restore-validation P1). This campaign runs entirely on the
   `swift build` / `swift test` / `swift run` tier, which works.

## Phase map

| Phase | Goal | Gate to pass |
|-------|------|--------------|
| P0 | Preserve knowledge in open PRs #11/#12 | RCAs archived; merge recommendation recorded (human merges) |
| P1 | Dated measurement baseline | Baseline table exists with real numbers |
| P2 | Reference targets acquired | Every effect to be tuned has a checked-in reference target — **DECISION GATE, biggest blocker** |
| P3 | Ranked gap menu worked | Each item: theory note → change → measured proof |
| P4 | Repeatable per-effect tuning loop | Predicted vs measured numbers recorded per change |
| P5 | Promotion via change control | PR per effect; flags + UI wired; human merges |

---

## P0 — Knowledge preservation gate (do FIRST, cheap)

Two open PRs contain fully-written root-cause analyses that evaporate from
easy reach once merged (or go stale if abandoned). Verified state as of
2026-07-09: **both OPEN and MERGEABLE, 0 behind main**.

```sh
gh pr view 11 --json state,title,mergeable   # QoS priority-inversion fix
gh pr view 12 --json state,title,mergeable   # GPU-effects parameter consistency
```

- **PR #11** (`fix/preview-priority-inversion`, 1 commit): full RCA of a
  CoreGraphics priority inversion — `FrameProcessor` is an actor; `Task {}`
  from `@MainActor` inherits User-initiated QoS; actor escalation made
  `ctx.draw` block on CG's Default-QoS threads. Fix: `Task(priority: .utility)`
  in `PreviewViewModel.updatePreview` and `AppState.exportItems`.
- **PR #12** (`fix/effect-params-and-editor-bugs`, 11 commits): directly
  load-bearing for THIS campaign —
  - single source of truth for per-kind defaults (`GPUEffectKind.defaultParameters()`),
  - sRGB tagging for `CodableColor.cgColor` (was untagged Generic RGB — every
    swatch and CPU-rendered color was shifted),
  - Blockify color-mode enum remap (had borrowed ASCII's inverted numbering),
  - iOS adoption of capability-flag gating (on main, only
    `Sources/FramerApp/Editor/LayerListSection.swift` consumes the flags — verified by grep),
  - **deletion of Glitch/EdgeField CPU pixel-loop fallbacks (−594 lines)**,
  - `usesPalette` flag + saved user palettes.

**Actions:**

1. Confirm the RCA essentials are archived in **framer-failure-archaeology**
   (that skill owns incident histories). If they are missing there, that is a
   gap — archive `gh pr view 11 --json body -q .body` and the same for #12
   into that skill before doing anything else. (unverified at write time —
   the sibling skill was authored in parallel; check it.)
2. Record the recommendation: merging #12 first is strongly preferred before
   any P3 work, because it moves parameter defaults, deletes two CPU paths,
   and remaps an enum — any effect-tuning branch cut before #12 merges will
   conflict. **The merge itself is the human's decision; the campaign only
   records the recommendation.**

---

## P1 — Baseline measurement

**Gate: a dated baseline table exists before any tuning.**

### 1. Parity suite

```sh
swift test --filter EffectGPUParityTests
```

Expect (measured 2026-07-09, commit 48d85a5, Apple Silicon Mac with Metal):
**27 tests, 0 failures, 0 skips, ~2.3 s**. Tests self-skip with `XCTSkip` when
no Metal device exists (CI sandboxes), so 27-executed-0-skipped is itself a
signal that the GPU path ran.

The suite asserts mean/max per-channel byte deltas (0–255 scale) but does
**not print** the measured values when passing — to capture actual deltas for
the baseline table, temporarily instrument the `compare(_:_:)` helper in
Tests/FramerCoreTests/EffectGPUParityTests.swift with a `print((mean, max))`,
or use the recipe in **framer-diagnostics-and-proof**. That skill ships
`.claude/skills/framer-diagnostics-and-proof/scripts/parity-report.sh` — use it
to verify pass/fail/skip counts, but note it does NOT print mean/max deltas, so
instrumenting `compare(_:_:)` remains the only way to capture delta numbers for
the baseline table. (The repo root itself has no `scripts/` directory.)

Tolerance ceilings to record alongside measured values (verified in
Tests/FramerCoreTests/EffectGPUParityTests.swift):

| Test(s) | Mean tolerance (0–255) | Notes |
|---------|------------------------|-------|
| ASCII parity | < 25 (max < 255) | loosest: GPU does 4×4 stratified sampling per cell |
| ASCII edge-direction stripes | < 30 | |
| Crimewave / Narc / Shiba (± softness) | < 6 (max < 40) | tightest — pure color grades |
| DistantPast (± softness) | < 12 | |
| CRT | < 8 | |
| Halftone mono | < 15 | |
| Kuwahara | < 12 | |
| PixelSort default span | < 12 | |
| PixelSort threshold-skip | < 2 (max < 8) | below-threshold pixels must pass through |
| Dither property tests (binary output, palette-only, two-tone, Riemersma→CPU routing, CMYK fallback, dimensions) | structural (<1% violating pixels) | not parity — invariants |

### 2. Performance baseline

```sh
swift run framer benchmark lut \
  --input docs/sample.jpg \
  --lut assets/luts/ANDP-Film-Fading.CUBE \
  --iterations 10 --warmup 2
```

Measured 2026-07-09 (Apple Silicon, 3000×1987 image — recorded with
`--iterations 3`, not the 10/2 command above, so your re-run's numbers will
differ slightly): CPU mean
~1253 ms; Metal auto ~76 ms (**16.5× speedup**; gpu 4.3 ms, upload 16.4 ms,
readback 24.6 ms — readback dominates GPU wall time). Hardware-dependent:
re-measure on your machine, don't compare against these absolutes. Note the
benchmark covers the LUT stack only; there is no per-effect benchmark command
yet (candidate tooling — see framer-diagnostics-and-proof).

### 3. Write the table

Record date, commit, machine, per-test measured mean/max, tolerance ceilings,
and benchmark numbers. This table is the "before" for everything in P3/P4.

---

## P2 — Reference acquisition (DECISION GATE — the campaign's biggest blocker)

**State it plainly: without reference targets, "Grainrad-class" is
unfalsifiable.** Nothing in this repo contains Grainrad output to compare
against.

What the repo has (verified):

- Shader headers citing Grainrad **notes**, not code:
  Sources/FramerCore/Effects/Metal/PixelSort.metal lines 7–10 cite
  ``Grainrad's `pixel-sort__GS__L16326.wgsl``` and a notes path;
  Sources/FramerCore/Effects/Metal/Dither.metal line 4 says "read
  grainrad/notes/dithering.md before changing". Both explicitly state **"No
  Grainrad code is copied."**
- The Acerola-derived effects cite `AcerolaFX_DistantPast.ini` palette values
  (Sources/FramerCore/Processing/ShaderRenderer.swift:195,
  Sources/FramerCore/Effects/Metal/DistantPast.metal:15) — the .ini and any
  reference frames are likewise not in the repo.

What exists OUTSIDE the repo (verified 2026-07-09, machine-local — this will
NOT exist on another machine or a cloud session): the maintainer's study repo
at `~/Github/grainrad` containing `notes/` (00-overview, ascii, dithering,
dots, pixel-sort), `reference/shaders/` (21 WGSL shaders extracted from
Grainrad's public JS bundle, including the exact `pixel-sort__GS__L16326.wgsl`
the Metal header cites), `port/` (early MSL sketches), and `CREDITS.md`.

**LICENSING FENCE (from that CREDITS.md, verified):** Grainrad's shaders are
under default copyright (no published license). The WGSL extracts are
read-only study material and are "not imported, bundled, compiled, or
redistributed by Framer". **Never vendor the WGSL files into this repo** —
doing so would break the "no Grainrad code is copied" attribution discipline
every Framer shader header relies on.

### Options, ranked

| Rank | Option | Who acts | Notes |
|------|--------|----------|-------|
| (a) | Maintainer vendors the reference material into `docs/references/`: the maintainer-authored `notes/*.md` (own authorship, safe) plus exact reference **renders** with provenance (tool, date, input image, parameter values) | **USER-ACTION** | Best. Renders of a fixed input at fixed params are the actual comparison targets. Redistribution of renders is still the maintainer's call — record the decision. |
| (b) | Generate reference stills manually from grainrad.com (and AcerolaFX for the color grades) on a fixed input image, check them in with a provenance README | Engineer + maintainer sign-off | Acceptable. Use docs/sample.jpg as the canonical input so targets and tests share a fixture. |
| (c) | Define quality purely self-referentially: parity + property tests + spectral metrics against Framer's own CPU serial implementations | Fallback only | Weakest — proves internal consistency, not Grainrad-class. Label any result achieved this way as such. |

**Milestone to pass this gate:** every effect selected for tuning has a
checked-in reference target and a scripted, measured comparison against it.
Until then, P3 items 3–5 can only run in mode (c).

---

## P3 — The ranked gap menu

Work top-to-bottom. Each item: current state → theory obligation → measurement
that proves it. Every item lands via P4's loop and P5's promotion.

### 1. pixelSort common-adjustments wiring

- **Current:** `usesCommonAdjustments` returns `false` for `.pixelSort` —
  the doc comment at Sources/FramerCore/Effects/Models/GPUEffectKind.swift
  lines 106–124 (verified) says: "Wire a colour pre-pass into both GPU and CPU
  pixel-sort paths before flipping this to true." PixelSort.metal marks its
  color block unused; showing the sliders now would recreate the dead-control
  bug class.
- **Theory obligation (write before coding):** define pre-pass semantics.
  Does brightness/contrast adjustment happen BEFORE span detection (adjusted
  luminance changes which pixels form sortable spans — visually different
  effect) or only on the output color? Document the choice in
  framer-image-processing-reference. Note PR #12 deletes the Glitch CPU loop;
  after it merges "both paths" may reduce to shader + `ShaderPixelSortRenderer`
  (the `.shader`-layer CPU path) — re-check what still exists.
- **Measurement:** parity test extension with a pre-declared tolerance, plus
  a property test: with brightness raised, span coverage must change
  identically on both paths. Only then flip the flag and surface the sliders.

### 2. cmykHalftone CPU parity — decide, don't drift

- **Current:** ACCEPTED divergence. CPU degrades to a monochrome 6×6
  clustered-dot screen (`cmykHalftoneDither`,
  Sources/FramerCore/Processing/DitherRenderer.swift:482–485); true
  per-channel rotated screens (cyan 15°, magenta 75°, yellow 0°, black 45°)
  are GPU-only. Documented as "intentional divergence" in
  docs/gpu-migration-mac-resume.md (§"CMYK halftone parity"). Coverage is
  routing-only: `testDitherCMYKHalftoneFallsBackOnEmptyMetal`. No parity test
  by design.
- **Decision required:** implement true CPU rotated screens, OR formally
  retire CPU parity for this algorithm. This is the concrete test case for
  the retire-the-CPU-path question — route the decision through
  framer-architecture-contract's open-questions list.
- **Measurement if implemented:** new parity test with stated tolerance +
  a screen-angle check (dominant dot-lattice orientation per channel).

### 3. Dither coefficient/phase re-tuning

- **Current:** the per-algorithm IGN amplitude coefficients (floyd 0.85,
  stucki 0.80, atkinson 0.75, artisticDrip 0.65, sierra 0.84, sierraTwoRow
  0.74, sierraLite 0.64, JJN 0.90, burkes 0.83) and spatial phase offsets are
  **eyeballed** — Sources/FramerCore/Effects/Metal/Dither.metal lines 19–23
  says so verbatim, and its advice ("tune by comparing output side-by-side")
  predates the measurement ruling. **Superseded for this campaign: metric
  first.** (Background: true error diffusion is serial and cannot run in a
  fragment shader; the IGN approximation is the whole design — see
  framer-image-processing-reference.)
- **Theory obligation:** define a spectral or perceptual metric FIRST — e.g.
  radially-averaged power spectrum distance between GPU output and the CPU
  serial implementation (DitherRenderer) or the P2 reference render, per
  algorithm, on fixed fixtures. Build the comparison harness under
  framer-diagnostics-and-proof. Note: `EffectPreviewComparator`
  (Sources/FramerCore/Effects/Utilities/EffectPreviewComparator.swift,
  verified) exists but only computes a mean absolute channel delta between
  two CGImages — and it currently has **no callers** anywhere in Sources/ or
  Tests/ (verified by grep, 2026-07-09). It is a building block, not the
  harness.
- **Measurement:** per-algorithm metric recorded before/after any coefficient
  change; a coefficient change with no predicted metric movement is rejected.

### 4. Deferred Grainrad features — product gate first

Each needs **product-intent sign-off [DECISION GATE, human]** plus a theory
note before any code. The deferred list (verified in
docs/gpu-migration-plan.md, §"Algorithms still NOT ported", which itself says
"Most of these probably belong as separate effect layers rather than dither
sub-modes"):

| Feature | Natural first metric |
|---------|----------------------|
| True void-and-cluster blue-noise mask (Dither.metal's DITHER_IGN comment, ~line 289, already plans the switch-over for DITHER_BLUE_NOISE) | spectral flatness / low-frequency energy of the mask itself — the most measurable item on this list |
| Modulation overlays (wave / grid / radial / horizontal / rgbSplit) | reference-render diff (needs P2) |
| Epsilon glow post-pass | reference-render diff (needs P2) |
| JPEG-glitch (block-shift, channel-swap, scanline-offset) | reference-render diff (needs P2) |
| Chromatic aberration (in or out of the dither pass) | channel-offset measurement on edge fixtures |

### 5. Long-streak pixel-sort fidelity

- **Current:** the GPU shader samples ≤24 evenly-spaced positions per span
  (`PIXEL_SORT_SAMPLE_COUNT = 24`, walk bounded by
  `PIXEL_SORT_MAX_WALK = 1024` — PixelSort.metal lines 30–31); CPU sorts
  every pixel. The shader header says "For long deliberate streaks, prefer
  the CPU export path" — but **no code prefers CPU at export**; CPU runs only
  on `MetalEffectError` (verified). Since commit 4cf8ec2 (2026-05-25) the
  bucket's Streak is resolution-relative:
  `spanCap = streakLength² × sortAxisDimension`, clamped to 1024
  (Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift:158–165).
- **Decision:** did 4cf8ec2 close the long-streak gap, or is 24-sample
  subsampling visible at Grainrad-class quality? **Measure before deciding:**
  build a long-span fixture (e.g. bright horizontal bands), plot GPU-vs-CPU
  mean delta as a function of span length, and eyeball-check only AFTER the
  curve exists.
- **Options if the gap is real:** raise SAMPLE_COUNT (measure register
  pressure/frame time), multi-pass sort, or accept + document the bound.

---

## P4 — The per-effect tuning loop (repeatable recipe)

For ONE effect at a time:

1. **Pick** the effect from P3; open a branch (see framer-change-control for
   naming).
2. **Baseline:** parity mean/max (instrumented as in P1) + reference diff
   against the P2 target + relevant perf number. Write them down.
3. **Hypothesis with predicted numbers:** "changing X will move metric M from
   A to approximately B." No prediction, no change.
4. **Change BOTH implementations in the same patch** while a CPU path exists
   for that effect. Every historical parity incident (blend-semantics f21a6fe,
   sort-criterion 761fae6, operation-order, Y-flip, pixel-grid pinning — full
   stories in framer-failure-archaeology) came from editing one path.
5. **Measure.** Compare against the prediction; explain any surprise before
   proceeding.
6. **Update parity tolerances only with justification** in the test comment,
   in the same commit as the change that moved them. Never blind-loosen.
7. **Illustrate** with a before/after grid for the PR description —
   illustration only, never the acceptance evidence.
8. If macOS snapshot hashes shift (sidebar UI changes), same-commit rule,
   1–4 hashes per commit for bisectability (see framer-validation-and-qa).

---

## P5 — Promotion via change control

- **One PR per effect.** Small, bisectable, with the P4 numbers in the body.
- Pre-PR checklist:
  - [ ] `swift build && swift test` green (not just the parity filter).
  - [ ] New/changed parameters follow the add-a-parameter checklist in
        **framer-config-and-flags**: uniform field + Swift mirror struct
        (stride-padded — see framer-metal-pipeline-reference), YAML key,
        defaults, capability flag.
  - [ ] **No dead sliders** — the recurring audit finding. Every exposed
        control must be read by the shader; every read uniform should have a
        control or a documented reason not to. Capability flags on
        `GPUEffectKind` are the gate; as of 2026-07-09 (commit 48d85a5) only
        `Sources/FramerApp/Editor/LayerListSection.swift` consumes them —
        iOS gating arrives with PR #12, so verify both platforms at the time
        you work.
  - [ ] Parity tolerance changes justified in-comment, same commit.
  - [ ] Reference comparison result recorded in the PR body (or explicitly
        labeled mode-(c) self-referential if P2 is still blocked).
- **A human merges.** Record your merge recommendation; never push to main.

---

## Wrong paths (fenced — do not re-walk)

| Wrong path | Why it's wrong | Evidence |
|------------|----------------|----------|
| Trusting docs/gpu-effects-parameter-matrix.md | STALE snapshot: its line 28 claims "**No** — none of the bucket shaders apply these" about common adjustments, but `applyCommonAdjustments` is present in EdgeField/Glitch/PrintSampling/TextCell.metal (verified by grep). Truth = `GPUEffectKind` capability flags + the .metal sources. Staleness ledger: framer-docs-and-writing. | grep vs doc, 2026-07-09 |
| Changing one path's semantics | Produced the pixel-sort amount blend-vs-rank divergence and the .hue/.brightness sort-criterion bugs | commits f21a6fe, 761fae6; framer-failure-archaeology |
| Adding params without capability flags + both UIs | Dead sliders / live params with no UI are the top recurring audit finding | commits 17f8111, f21a6fe; PR #12 extends gating to iOS |
| Seeding preset pickers with canonical-matching values | Derived-selection pickers snap "Custom" back to a preset — happened twice in two days | commits 9ad0f2c, 9a5857f; framer-failure-archaeology |
| Tuning by eye without a recorded metric | Directly violates the 2026-07-09 maintainer ruling; the Dither.metal header's side-by-side advice is superseded for this campaign | ruling; Dither.metal:19–23 |
| Vendoring Grainrad WGSL into this repo | Default copyright; the study repo's CREDITS.md restricts extracts to read-only study; Framer's shader headers promise "No Grainrad code is copied" | grainrad CREDITS.md (machine-local), PixelSort.metal:9–10 |
| Validating via `xcodebuild test` | That tier is broken on the maintainer's machine; also `swift test` passing does NOT exercise Xcode's Metal validation layer — a separate known trap | framer-campaign-restore-validation; framer-metal-pipeline-reference |

## When NOT to use this skill

- Debugging a rendering failure or CPU-fallback symptom → **framer-debugging-playbook**.
- How the Metal pipeline works / adding a brand-new effect → **framer-metal-pipeline-reference**.
- Dithering/pixel-sort/blend theory → **framer-image-processing-reference**.
- Building the measurement harness or analysis scripts → **framer-diagnostics-and-proof**.
- Fixing the xcodebuild/e2e test tiers → **framer-campaign-restore-validation**.
- Commit/branch/PR mechanics and gating → **framer-change-control**.
- What the frontier means and the research evidence bar → **framer-research-frontier**.

## Provenance and maintenance

All claims verified 2026-07-09 against commit 48d85a5 on an Apple Silicon Mac
with Metal, unless labeled otherwise. Volatile facts and how to re-verify:

| Fact | Re-verify with |
|------|----------------|
| PRs #11/#12 open + mergeable | `gh pr view 11 --json state,mergeable && gh pr view 12 --json state,mergeable` |
| Parity suite: 27 tests, 0 failures | `swift test --filter EffectGPUParityTests` |
| Parity tolerance ceilings | `grep -n XCTAssertLessThan Tests/FramerCoreTests/EffectGPUParityTests.swift` |
| LUT benchmark numbers (16.5× on 3000×1987) | `swift run framer benchmark lut --input docs/sample.jpg --lut assets/luts/ANDP-Film-Fading.CUBE --iterations 10 --warmup 2` |
| pixelSort excluded from common adjustments + pre-pass note | `grep -n 'usesCommonAdjustments' -A 6 Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| Dither coefficients "eyeballed" + coef/phase table | `grep -n 'eyeballed' Sources/FramerCore/Effects/Metal/Dither.metal` and lines ~251–305 |
| PixelSort 24-sample cap / 1024 walk bound | `grep -n 'PIXEL_SORT_SAMPLE_COUNT\|PIXEL_SORT_MAX_WALK' Sources/FramerCore/Effects/Metal/PixelSort.metal` |
| Resolution-relative streak formula | `grep -n 'spanCap' Sources/FramerCore/Effects/Renderers/GlitchGPURenderer.swift` |
| cmykHalftone CPU mono fallback | `grep -n 'cmykHalftone' Sources/FramerCore/Processing/DitherRenderer.swift` |
| EffectPreviewComparator exists but uncalled | `grep -rn EffectPreviewComparator Sources/ Tests/` |
| parameter-matrix doc still stale | `grep -n 'none of the bucket shaders' docs/gpu-effects-parameter-matrix.md; grep -ln applyCommonAdjustments Sources/FramerCore/Effects/Metal/*.metal` |
| Capability flags consumed on macOS only (pre-#12) | `grep -rln 'usesCommonAdjustments\|usesGeometry' Sources/FramerApp Sources/FramerMobile` |
| grainrad study repo present (machine-local) | `ls ~/Github/grainrad/notes ~/Github/grainrad/reference/shaders` |
| Deferred-features list | `sed -n '150,180p' docs/gpu-migration-plan.md` |
| No repo-root scripts/ dir (parity-report.sh lives in the diagnostics skill) | `ls scripts` (expect: not found) ; `ls .claude/skills/framer-diagnostics-and-proof/scripts/` (expect: parity-report.sh) |
