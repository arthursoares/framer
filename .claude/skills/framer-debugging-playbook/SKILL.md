---
name: framer-debugging-playbook
description: >
  Symptom-to-cause triage for framer's known failure modes. FIRST STOP for live triage.
  Load when something renders wrong or crashes and you need to find out WHY — GPU
  effects look different/slow, garbled colors, parameters or sliders do nothing, wrong
  colors only for HEIC/PNG images, preset picker snaps back on "Custom", new file not
  compiling under xcodebuild, signing-certificate or Metal Toolchain errors, overlays
  rendering as garbage, snapshot-test SHA-256 hash mismatches, preview-vs-export
  differences, crashes on layer deletion, Thread Performance Checker priority-inversion
  warnings, or a preset rendering differently on two machines. Keywords: debug, triage,
  wrong render, silent fallback, MetalEffectError, uniform layout, bitmapInfo, xcodegen,
  LFS pointer, parity.
---

# Framer Debugging Playbook

Symptom → cause → discriminating experiment, for THIS repo's known failure modes.
Facts verified against main @ 48d85a5 on 2026-07-09 unless labeled otherwise.

## Discipline (read once, then use the table)

1. **Reproduce first.** Get a command or click-path that shows the bug on demand before changing anything.
2. **One variable at a time.** This codebase has paired implementations (CPU/GPU, preview/export, macOS/iOS) — isolate which side is wrong before touching either.
3. **Instrument before guessing.** The console log, the parity test suite, and the snapshot failure message all print discriminating evidence for free. Check them before reading code. To *measure* pixels quantitatively, see **framer-diagnostics-and-proof**.
4. **Never blind-fix a snapshot hash or a parity tolerance.** Explaining the shift IS the debugging (house rule — see **framer-change-control**).

Jargon used below, defined once:
- **Bucket / `.gpuEffect` layer**: one of 4 GPU effect families (textCell, printSampling, edgeField, glitch) dispatched via `GPUEffectsPlatform`; distinct from the older `.shader` layer effects dispatched via `ShaderRenderer`.
- **CPU fallback**: every GPU effect has a CPU implementation; the GPU path is tried first and CPU runs only when the GPU path throws `MetalEffectError` (any other error propagates). See `Sources/FramerCore/Processing/ShaderRenderer.swift:76-90`.
- **metallib**: a precompiled Metal shader library. Under Xcode builds SPM compiles the `.metal` files into `default.metallib`; under plain `swift build`/`swift test` it does NOT — `MetalEffectLibrary` concatenates the `.metal` sources and compiles them at runtime instead (`Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift:54-120`).
- **Uniforms**: the parameter struct passed from Swift to a Metal shader; Swift and MSL (Metal Shading Language) struct layouts are mirrored by hand.

## Quick triage table

| # | Symptom | Most likely cause | First experiment |
|---|---------|-------------------|------------------|
| 1 | Every GPU effect looks subtly different / renders slowly | Silent CPU fallback | Grep console for `[ShaderRenderer] CPU fallback` |
| 2 | Garbled colors AND parameters do nothing | Swift/MSL uniform layout drift | Run Xcode app with Metal validation; look for `has space for N bytes, but argument has a length(M)` |
| 3 | Wrong colors only for HEIC / some PNGs | `bitmapInfo` inherited from source image | Re-export the file as plain sRGB JPEG — bug disappears |
| 4 | Preset picker snaps back when choosing "Custom" | Derived `matching()` selection | Check if the Custom seed value equals a named preset's literal |
| 5 | New file doesn't compile / test invisible under xcodebuild | Stale generated Xcode project | `xcodegen generate`, then `xcodebuild clean test` |
| 6 | `Signing certificate … is not valid for code signing` | Environment, not code | None needed — see **framer-campaign-restore-validation** |
| 7 | `The Metal Toolchain was not installed …` from xcodebuild | Missing Xcode component | `xcodebuild -showComponent metalToolchain` |
| 8 | Overlays render as garbage or missing | Git LFS pointers not hydrated | `ls -la assets/textures/` — pointer files are exactly 132 bytes |
| 9 | Snapshot test SHA-256 mismatch | Real layout drift, OR machine/OS change | Read the rendered pixels FIRST (house rule) |
| 10 | A slider does nothing | Capability-flag / encoder wiring drift | Grep the `.metal` file for the uniform field |
| 11 | Preview looks different from export | `previewBaseDimension` not honored | Compare pattern density at same crop, preview vs exported file |
| 12 | Crash deleting a layer while its editor is open | Index-captured binding | Check the binding is by `layer.id`, not array index |
| 13 | Thread Performance Checker: priority inversion | `Task {}` from `@MainActor` + actor QoS escalation | Check `Task(priority:)` at spawn sites |
| 14 | Same preset renders differently on two machines | GPU float/rounding drift across devices (CPU fallback no longer exists) | `swift test --filter EffectGPUGoldenTests` on both — goldens were frozen on one machine; deltas within tolerance are expected drift |

## Detailed entries

### 1. Effects throw MetalEffectError / render nothing → shader library failed to load

**Mechanism (updated 2026-07-09 — CPU path retired, docs/adr/2026-07-09-retire-cpu-effect-path.md).** Effect renderers are GPU-only and `MetalEffectError` propagates to the caller: a Metal failure now surfaces as a thrown error (CLI failure, app error state), NOT as a silently different render. The historical "silent CPU fallback made everything look subtly different" failure mode — and the `[ShaderRenderer] GPU path ✓ / CPU fallback` log lines — no longer exist. If effects render AND look wrong, you are NOT in this entry; see #2 (uniforms) or the golden tests.

**Experiment.** Run `swift test --filter EffectGPUGoldenTests` (self-skips with `XCTSkip("Metal device unavailable…")` when there's no GPU library) and check stdout for `MetalEffectLibrary` load errors.

**Discriminator for scope.** ONE effect falling back = that effect's pipeline/function failed. MANY effects falling back simultaneously = the whole shader library failed to build — either `default.metallib` missing from the bundle, or one bad `.metal` file breaking the *concatenated* runtime source compile (all `.metal` files compile as one translation unit under `swift build`; a typo in any one kills all of them). `docs/gpu-migration-mac-resume.md` calls this out: "multiple effects 'look like CPU' simultaneously is the signature." Look for `MetalEffectLibrary: makeLibrary failed: <compile error>` on stdout (`MetalEffectLibrary.swift:113`).

**Also note:** a GPU command buffer finishing with error status *throws* `commandEncodingFailed` rather than returning garbage (`Sources/FramerCore/Effects/GPU/MetalRenderPass.swift:88-90`) — so corrupt pixels from a successful render point elsewhere (usually entry #2). Loader mechanics live in **framer-metal-pipeline-reference**; the SPM-doesn't-compile-metal saga in **framer-failure-archaeology**.

### 2. Garbled colors, parameters do nothing → uniform layout drift

**Mechanism.** Swift uniform structs mirror MSL structs field-for-field by hand. If they drift (missing `_pad` field, reordered member), the shader reads parameter bytes at wrong offsets — output is garbled and moving sliders changes nothing recognizable. A second variant: passing `MemoryLayout<T>.size` bytes where Metal validates against alignment-rounded *stride*.

**Experiment.** Run the app from Xcode with Metal API validation on. The stride bug trips this exact validation error (documented verbatim in `Sources/FramerCore/Effects/GPU/MetalUniformEncoding.swift:11-12`):

```
Fragment Function(x): argument uniforms[0] from Buffer(0) with offset(0)
and length(152) has space for 152 bytes, but argument has a length(160).
```

Trap: this error appears ONLY in the Xcode-built app (Metal validation layer); `swift build`/`swift test` pass cleanly with the same bug. A green `swift test` does not clear you here.

**Fix direction.** Change the MSL struct and its Swift mirror in the same patch (rule stated at `Sources/FramerCore/Effects/GPU/SharedUniforms.swift`), keep explicit `_pad` fields, and ALWAYS encode via `uniformBytes(_:)` (`MetalUniformEncoding.swift:24-33`) — never `withUnsafeBytes(of:) { Data($0) }`.

### 3. Wrong colors only for HEIC / some PNGs → bitmapInfo inheritance

**Mechanism.** Some ImageIO decoders return CGImages with exotic `bitmapInfo` (e.g. `kCGImageAlphaLast | kCGImagePixelFormatPacked`). Code that copies the *source's* bitmapInfo into a new `CGContext` or hands the raw image to `MTKTextureLoader` gets either a rejected context ("unsupported parameter combination", silently skipping a downscale) or visibly wrong colors.

**The rule (project invariant).** Never inherit source bitmapInfo. All pixel paths normalize to canonical **8-bit premultipliedLast RGBA**: `MetalTextureSupport.normalizedForTextureUpload` (exact-match fast path + canonical redraw, `Sources/FramerCore/Effects/GPU/MetalTextureSupport.swift:87-111`) and `PreviewViewModel`'s downscale context (`Sources/FramerApp/Editor/PreviewViewModel.swift:~134-146`, comment explains why).

**Experiment.** Re-encode the offending file as a plain sRGB JPEG. If colors fix themselves, it's this. Note: synthetic test fixtures can't reproduce it — only real ImageIO decodes produce the exotic flag combos.

**Saga (one line).** Took three commits in one day to nail — `f0de444` → `35c7886` → `6635746` "the real culprit". Full story: **framer-failure-archaeology**.

### 4. Picker selection snaps back when choosing "Custom" → derived matching()

**Mechanism.** Preset pickers in the sidebar don't store their selection — it's *derived* each render by running `matching(storedValue)` over the current data (e.g. `VintagePalette.Preset.matching(colors)` at `Sources/FramerApp/Editor/LayerListSection.swift:3627`, `ASCIIPreset.matching(...)` at `:4348`). If choosing "Custom" seeds the stored value with data that *equals a named preset's literal*, the next render re-derives that preset and the picker snaps back — a silent no-op.

**Experiment.** Read the picker's setter: does the Custom branch seed with a preset's exact value? Then it will snap back.

**Fix pattern (from the shipped fixes).** Seed Custom with data guaranteed not to match any preset (the dither fix appends a neutral `#808080` swatch — see comment at `LayerListSection.swift:3642-3651`), guard re-selecting the already-selected preset, and trim to `MAX_PALETTE_COLORS - 1` before appending so the sentinel isn't dropped at capacity.

**Saga.** Happened twice in two days: ASCII characters (`9ad0f2c`) and dither palette (`9a5857f`), plus the at-capacity variant (`761fae6`). Any NEW preset picker using derived selection can reintroduce it. Full story: **framer-failure-archaeology**.

### 5. New file doesn't compile / test not discovered under xcodebuild

**Mechanism.** `Framer.xcodeproj` is generated by XcodeGen and committed; its file lists are a snapshot resolved at generate time. A new file under `Sources/FramerApp/` or `Tests/FramerAppTests/` is invisible to `xcodebuild` until regeneration — even though `project.yml` globs the whole directory. (`swift build` is unaffected: SPM targets don't use the xcodeproj.)

**Fix.**

```bash
xcodegen generate
```

If tests *still* aren't discovered after regeneration (stale discovery state), additionally:

```bash
xcodebuild clean test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
```

Both steps are documented from experience in `.sisyphus/notepads/sidebar-harmony/learnings.md` ("`xcodegen generate` must run after every new `Sources/FramerApp/Sidebar/*.swift` or `Tests/FramerAppTests/*.swift` file"; "`xcodegen generate` followed by `xcodebuild clean test …` forced Xcode to pick up newly added sidebar test methods"). Note: as of 2026-07-09 the xcodebuild tier itself is broken on the primary dev machine (see entries 6–7), so this fix may be blocked behind environment repair.

### 6. "Signing certificate … is not valid for code signing" → environment, not code

`xcodebuild test -scheme Framer -destination 'platform=macOS'` fails with `Signing certificate "Apple Development: …" … is not valid for code signing` (observed 2026-07-09 on the primary dev machine — the cert is revoked, `CSSMERR_TP_CERT_REVOKED`, not merely expired, so waiting won't help). Nothing you changed caused this; do NOT start reverting code. Repairing this tier is an executable campaign: **framer-campaign-restore-validation**. Environment setup generally: **framer-build-and-env**. Meanwhile, `swift build && swift test` (268 tests, FramerCore + FramerCLI) still works and needs no signing.

### 7. Metal Toolchain errors from xcodebuild → missing Xcode component

With signing disabled (`CODE_SIGNING_ALLOWED=NO`), xcodebuild next fails on `CompileMetalFile` with `The Metal Toolchain was not installed and could not compile the Metal source files` (observed 2026-07-09). Xcode 26 ships the Metal compiler as a separately-downloaded component.

**Experiment (verified 2026-07-09):**

```bash
xcodebuild -showComponent metalToolchain   # prints "Status: uninstalled"
```

**Fix (per Apple's own error text; not yet executed on this machine):** `xcodebuild -downloadComponent MetalToolchain`.

**Deceptive part:** `swift build`/`swift test` pass WITHOUT the Metal Toolchain, because `MetalEffectLibrary` runtime-compiles shader source (`MetalEffectLibrary.swift:54-120`). The environment looks fine until you touch app targets. Owned by **framer-build-and-env** / **framer-campaign-restore-validation**.

### 8. Overlays render as garbage / missing → Git LFS pointers

**Mechanism.** The ~168 texture overlays in `assets/textures/` are stored via Git LFS. Cloning without `git lfs pull` leaves text pointer stubs where JPEGs should be, so overlay layers render nothing/garbage.

**Discriminator (verified: a pointer blob in git is exactly 132 bytes):**

```bash
ls -la assets/textures/ | head        # pointer files are exactly 132 bytes
head -c 60 assets/textures/<file>     # pointers start "version https://git-lfs.github.com/spec/v1"
```

**Fix:** `git lfs install && git lfs pull`. Note the two ASCII atlas PNGs in `Sources/FramerCore/Resources/textures/` are deliberately OUTSIDE LFS so core tests pass without it — "ASCII works but overlays don't" is consistent with missing LFS. Setup details: **framer-build-and-env**.

### 9. Snapshot hash mismatch → read the pixels first (house rule)

**Mechanism.** FramerAppTests snapshot tests render views into a dark `NSHostingView`, PNG-encode, and compare a SHA-256 against an inline string; the failure message prints the actual hash (`Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift:270-307`: `"Snapshot <name> changed. Actual SHA256: <hash>"`). A one-bit render difference flips the hash — the hash tells you *that* something changed, never *what*.

**House rule (binding):** NEVER blind-copy the new hash into the test. Render the view, look at the pixels, explain the shift; hash refreshes land in the same commit as the change that caused them (1–4 hashes per commit, for bisectability). The learnings file's lesson verbatim: "Snapshot diff is the forcing function; read the pixels, not the diff" (`.sisyphus/notepads/sidebar-harmony/learnings.md`).

**Discriminator.** ALL snapshots failing at once on a machine that didn't touch UI code = cross-machine/OS fragility (font rasterization, GPU compositing — a known limitation), not a regression. Full snapshot protocol and update workflow: **framer-validation-and-qa**.

### 10. A slider does nothing → capability-flag / encoder wiring drift

**Mechanism.** GPU bucket effects share common/geometry/color parameter blocks, but each shader variant reads only some fields. Historically the UI rendered every control for every variant, shipping dead sliders. Ground truth for what a variant consumes is the capability flags on `GPUEffectKind` — `usesGeometry`, `usesColorModeAndFgBg`, `usesBackgroundIntensity`, `usesCommonAdjustments` (`Sources/FramerCore/Effects/Models/GPUEffectKind.swift:81-124`) — which the macOS sidebar gates on (`LayerListSection.swift:325-379`). Notably `usesCommonAdjustments == false` for `.pixelSort` only: its shader never calls `applyCommonAdjustments`.

**Warning:** `docs/gpu-effects-parameter-matrix.md` is a STALE snapshot of this information (predates the common-adjustments wiring and the vhs/matrixRain GPU paths). Trust the flags and the `.metal` sources, not the doc. (Staleness ledger: **framer-docs-and-writing**.)

**Experiment.** Three-point check — the slider works only if all three hold:
1. Shader reads it: `grep <fieldName> Sources/FramerCore/Effects/Metal/<Bucket>.metal`
2. Encoder sends it: grep the field in the bucket's GPU renderer (`Sources/FramerCore/Effects/Renderers/`)
3. Flag exposes it: the relevant `uses*` flag returns true for that `GPUEffectKind` case

**Fix direction.** Wire shader + uniform mirror + encoder + capability flag together in one patch. Parameter catalog: **framer-config-and-flags**. Full checklist for new params: **framer-metal-pipeline-reference**.

### 11. Preview looks different from export → previewBaseDimension plumbing

**Mechanism.** Scale-sensitive layers (dither, LUT, shader) sample per-pixel, so pattern density depends on resolution. The preview renders at 1200–3000px while export is full-res; WYSIWYG holds only because these layers receive a `previewBaseDimension` and scale their pixel math by `currentMax / previewBase` (export path: `Sources/FramerCore/Processing/FrameProcessor.swift:88-98`; scaling math example: `Sources/FramerCore/Processing/DitherRenderer.swift:172-177`). Extra wrinkle: a `.gpuEffect` layer forces the preview to render at FULL resolution then downscale, so mixed stacks need `previewMax` passed as the base for the CPU layers (`FrameProcessor.swift:32-47,62-64` — the comment there explains the mismatch that occurs otherwise).

**Experiment.** Export the image, crop both preview screenshot and export to the same region, compare pattern grain size. Density mismatch = this entry. Then check the suspect layer's renderer actually *receives and uses* `previewBaseDimension`.

**Fix direction.** Any NEW scale-sensitive layer must accept and honor `previewBaseDimension` — it's an invariant, owned by **framer-architecture-contract**.

### 12. Crash deleting a layer while its editor is open → index-captured bindings

**Mechanism.** A `binding(for index: Int)` that captures the array index by value crashes (index out of range) when the layer is deleted while its detail view is still in the view tree. Fixed by id-based lookup: `CHANGELOG.md:27` records the incident, and the current code binds via `layers.firstIndex(where: { $0.id == id })` with a captured fallback (`Sources/FramerApp/Editor/LayerListSection.swift:266-272`).

**Rule.** Bind layers by `layer.id`, never by array index. Any new list-of-layers UI (macOS or iOS) must follow this. UI grammar: **framer-ui-design-system**.

### 13. Thread Performance Checker: priority inversion → QoS at Task spawn

**Mechanism (fully diagnosed in open PR #11, unmerged as of 2026-07-09).** `FrameProcessor` is an actor; actors inherit the awaiting task's QoS via priority escalation. `Task {}` spawned from `@MainActor` inherits **User-initiated** QoS, so the actor's synchronous CoreGraphics draws (`BorderRenderer.swift:519` per the checker) block on CG's **Default**-QoS internal threads — user-initiated waiting on default = the inversion Xcode flags.

**Status check.** Main still spawns with plain `Task {` at `Sources/FramerApp/Editor/PreviewViewModel.swift:49` (verified 2026-07-09) — the warning is expected until PR #11 (`Task(priority: .utility)` in `PreviewViewModel.updatePreview` and `AppState.exportItems`) merges. Read `gh pr view 11` for the full analysis before re-deriving it. This is a diagnostic warning, not a crash — don't panic-fix it in an unrelated PR; merging is a human decision (**framer-change-control**).

### 14. Same preset renders differently on two machines → CPU-vs-GPU path

**Mechanism.** If one machine's GPU path fails (no Metal device, broken library), it silently renders via CPU (entry 1), and CPU≠GPU is only *tolerance*-equal, never bit-equal. Historically, every new shader port also shipped 1–3 genuine parity bugs (pixel-sort `amount` semantics `f21a6fe`, sort-criterion math `761fae6`, dither gamma `a757e67`, Y-flip `d61f9d9`, …).

**Experiment (verified 2026-07-09: 27 tests, 0 failures, ~2.3s):**

```bash
swift test --filter EffectGPUGoldenTests
```

Run on BOTH machines. All-skip (`XCTSkip`) on one machine = that machine has no working Metal → it's on CPU fallback, expected divergence. Failures = a real parity bug.

**Known ACCEPTED divergences (don't chase these):** cmykHalftone (CPU degrades to monochrome clustered dot; true rotated CMYK screens are GPU-only), Riemersma dither (CPU-only by design), pixel-sort spans > 24 samples (GPU sub-samples, coarser streaks).

**Doctrine note (updated 2026-07-09):** the CPU effect path was RETIRED (docs/adr/2026-07-09-retire-cpu-effect-path.md). Keep `EffectGPUGoldenTests` + `EffectGPUBehaviorTests` green; golden refresh follows snapshot-hash discipline. Contract: **framer-architecture-contract** I3. Historical parity incidents: **framer-failure-archaeology**.

## When NOT to use this skill

| You actually need to… | Go to |
|---|---|
| Set up the environment / fix toolchain from scratch | **framer-build-and-env** |
| Execute the repair of the broken xcodebuild test tier | **framer-campaign-restore-validation** |
| Write new tests, refresh snapshot baselines properly | **framer-validation-and-qa** |
| Measure pixels / prove a visual claim quantitatively | **framer-diagnostics-and-proof** |
| Read the full story behind an incident named here | **framer-failure-archaeology** |
| Understand Metal loading/uniforms/textures to build something | **framer-metal-pipeline-reference** |
| Look up what a parameter/flag does | **framer-config-and-flags** |
| Run the CLI/app and find output files | **framer-run-and-operate** |

## Provenance and maintenance

Verified 2026-07-09 against main @ 48d85a5 on the primary dev Mac (Apple Silicon, Xcode 26.6, Swift 6.3.3). What may drift, and how to re-check:

| Fact | Re-verification |
|---|---|
| Fallback log strings | `grep -n 'ShaderRenderer]' Sources/FramerCore/Processing/ShaderRenderer.swift` |
| Uniform length validation error text | `sed -n '5,17p' Sources/FramerCore/Effects/GPU/MetalUniformEncoding.swift` |
| Silent bucket fallback (no log) | `grep -n 'fall through to CPU' Sources/FramerCore/Effects/Renderers/GlitchRenderer.swift` |
| premultipliedLast normalization | `grep -n 'normalizedForTextureUpload' Sources/FramerCore/Effects/GPU/MetalTextureSupport.swift` |
| matching()-derived pickers | `grep -n 'Preset.matching' Sources/FramerApp/Editor/LayerListSection.swift` |
| Capability flags (incl. pixelSort exception) | `grep -n 'usesCommonAdjustments' Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| UI gates on flags | `grep -n 'params.kind.uses' Sources/FramerApp/Editor/LayerListSection.swift` |
| previewBaseDimension plumbing | `grep -n 'previewBaseDimension' Sources/FramerCore/Processing/FrameProcessor.swift` |
| id-based layer binding | `sed -n '266,275p' Sources/FramerApp/Editor/LayerListSection.swift` |
| PR #11 merged yet? (entry 13 stale once merged) | `gh pr view 11 --json state` and `grep -n 'Task(priority' Sources/FramerApp/Editor/PreviewViewModel.swift` |
| Golden/behavior suites passing (13/14) | `swift test --filter EffectGPUGoldenTests` ; `swift test --filter EffectGPUBehaviorTests` |
| Metal Toolchain installed yet? (entries 6–7 stale once env repaired) | `xcodebuild -showComponent metalToolchain` |
| LFS pointer size (132 bytes) | `git cat-file blob HEAD:$(git lfs ls-files -n \| head -1) \| wc -c` |
| Snapshot assert message | `sed -n '299,306p' Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` |
| Command-buffer error → throw (no silent garbage) | `grep -n 'commandEncodingFailed' Sources/FramerCore/Effects/GPU/MetalRenderPass.swift` |
| Incident commits still resolve | `git show -s --oneline f21a6fe 761fae6 9ad0f2c 9a5857f f0de444 35c7886 6635746 a757e67 d61f9d9` |
