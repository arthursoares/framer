# Develop cleanup audit

Baseline: `1f15cb2`, reviewed 2026-09-05. Scope: core/CLI, macOS/iOS state and UI,
tests, and release branch configuration.

## Cleanup plan (written before code changes)

1. Prepare local `develop` by fast-forwarding `origin/develop` to the released
   `origin/main` baseline (seven commits); work on `chore/develop-cleanup` with
   `develop` as the intended PR base. Publishing and merging are separate steps.
2. Establish baseline build/tests in `/tmp/framer-cleanup-build`. The existing
   `.build` contains compiler artifacts from the repository's previous location.
   Baseline: 308 tests, zero failures, zero skips.
3. Lock legacy text-cell CPU ASCII output with regression coverage before deleting
   unreachable CPU dots/blockify/matrix-rain branches and their private helpers.
   Preserve the GPU dispatch and legacy parameter decoding exactly.
4. Add regression tests for YAML-to-JSON preset saves (success and failed
   replacement), then write the replacement before removing the YAML original.
   Avoid deleting files derived from an unchecked preset display name.
5. Include `develop` in the existing CI push trigger. Retain pull-request checks.
6. Run focused tests, full SPM build/tests, GPU golden/behavior coverage, and a
   CLI image smoke check for renderer changes. Review the integrated diff
   independently. No new dependencies or snapshot/golden refreshes.

## Initial findings and final disposition

The findings below describe the initial `1f15cb2` baseline. The completed PR
stack addresses them as follows (merge from bottom to top):

1. `chore/develop-release-baseline` → `develop`: released baseline, PR #24.
2. `chore/develop-cleanup` → baseline: safe saves/dead renderer deletion, PR #25.
3. `fix/preset-recovery` → cleanup: preserve unreadable originals, PR #26.
4. `fix/cli-config-safety` → recovery: captions/output collision checks, PR #27.
5. `chore/package-pin-parity` → CLI: identical dependency pins, PR #28.
6. `fix/app-state-lifecycle` → pins: stable editor IDs and async state, PR #29.
7. `refactor/layer-editors` → lifecycle: separate layer-control files.

Retarget each upper PR to `develop` as lower PRs merge, preserving ancestry
with merge commits. No merge was performed by the agent.

- High: `PresetStore.list()` silently deletes unreadable JSON. Recommend preserving
  and skipping these files. Arthur authorized continuing with these findings
  as stacked PRs after reviewing the initial audit.
- High: `ProcessCommand.run()` constructs a caption and replaces all configured
  captions even when no caption flags are supplied (lines 81–115). Preserve the
  authored stack without explicit overrides; decide how font-only flags affect
  multiple existing captions. Needs config-to-CLI regression coverage.
- High: CLI batch output names drop the input extension, so `foo.jpg` and
  `foo.png` both write `foo_solid.jpg` (ProcessCommand.swift:156–198, 241–255).
  Recommend rejecting duplicate output paths before starting the batch; this
  preserves current filenames without silently overwriting one result.
- High: iOS synthesizes fresh default layers on each binding read while
  `currentConfig.layers` is nil (LayerStrip.swift:7–12, EditorView.swift:21–25).
  Their new UUIDs cannot match the later navigation destination lookup
  (EditorView.swift:46–66). Persist defaults before navigation, mirroring macOS.
- Medium: iOS preset previews regenerate only on photo/library changes, so
  imported/saved presets can keep blank previews (EditorView.swift:163–188).
  Observe preset changes and invalidate the cache.
- Medium: an older iOS photo-import task can clear a newer task's handle and
  loading state in its unconditional defer (EditorView.swift:292–318). Guard
  completion and cleanup by task identity/generation.
- Medium: desktop preview generations are not advanced for nil selection, and
  stale tasks can still write error/loading state (PreviewViewModel.swift:21–95).
  Guard all completion paths, including reset, after adding controlled async tests.
- macOS `LayerListSection.swift` is 5,272 lines; iOS `LayerDetailView.swift` is
  3,891 lines. Split along existing layer-editor boundaries after app-level
  regression checks are operational, rather than sharing platform UI wholesale.
- SwiftPM and Xcode pin ArgumentParser to 1.7.0 and 1.7.1 respectively. Align
  using package resolution in a separate dependency change.
- `EffectPreviewComparator` has no call sites or tests, but is public API and
  documented as a future validation hook. Retained for compatibility; removal
  or adoption into new preview/export validation remains a separate decision.

The initial app findings came from source inspection. The final stack adds a
mobile test target and controlled regressions for the fixed lifecycle issues.
Legacy decoding, intentional CPU ASCII/Riemersma/LUT paths, and conditional
sidebar result builders remain required compatibility behavior.

Final integrated validation: normal `swift build` and `swift test` pass
**330 Core/CLI tests**; Xcode passes **65 macOS + 7 iOS tests**, all with zero
failures/skips. App tests use signing disabled and unchanged visual snapshots.
Physical-device signing is not verified; existing iOS warnings remain.

## Verification and remaining findings

- Completed: unreachable text-cell branches and three private drawing helpers
  removed; legacy ASCII and GPU dispatch retained. Removed stale agent-history
  commentary and corrected the misleading description of error propagation.
- Completed: preset replacement writes JSON atomically before retiring YAML;
  cleanup matches deterministic identity within the preset directory. Display
  names are never used to construct deletion paths.
- Added six preset tests and one four-scenario exact CPU output regression.
  Before the save fix: four new tests failed (five failed assertions). After:
  all 25 PresetStoreTests passed. CPU output baselines were captured and checked
  against the unmodified renderer before deleting the unreachable code.
- `swift build --scratch-path /tmp/framer-cleanup-build`: passed, no warnings.
- `swift test --scratch-path /tmp/framer-cleanup-build`: **Executed 315 tests,
  with 0 failures (0 unexpected)**; zero skips. This includes
  EffectGPUGoldenTests, EffectGPUBehaviorTests, and bucket dispatch tests.
- CLI smoke: `/tmp/framer-cleanup-build/debug/framer process --input
  Tests/FramerCoreTests/Resources/sample.jpg --output-file
  /tmp/framer-slop-ascii.png --config /tmp/framer-slop-smoke.yaml --no-caption
  --no-metadata` passed with a `gpu_effect` / `ascii` layer. Inspected the
  output image; regression hashes establish unchanged output for test fixtures.
- CI YAML parses successfully and includes both `develop` pushes and PRs.
  `git diff --check` passed. No configured lint tool was found; SPM compilation
  checked types. Xcode app/iOS tests were not run; their sources are unchanged.
- Initial scan left the branch local and uncommitted. Follow-up delivery uses
  stacked PRs: released baseline into `develop`, then this cleanup, preset
  recovery, CLI safety, and app lifecycle fixes. Main remains unchanged.
- Independent review found no implementation defects. It identified that the
  new exact CPU fixtures included context-selected image resizing. Removed that
  test variability by generating inputs at each scenario's output dimensions;
  re-established and passed all four expectations against the original renderer
  from HEAD before restoring the cleanup. Hashes changed because the input
  fixtures changed, not because the renderer changed. These new tests remain
  unverified on the macOS 15 CI runner; existing GPU goldens are unchanged.
