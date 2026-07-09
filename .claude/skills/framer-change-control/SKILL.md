---
name: framer-change-control
description: >
  Load before making, committing, reviewing, or merging ANY change to the framer repo —
  code, shaders, schemas, UI, tests, or docs. Covers change classification and gating
  (which bar a change must clear), the non-negotiable house rules (no autonomous merges,
  snapshot-hash discipline, back-compat decoding, parity tests, no cherry-picks),
  conventional-commit and branch/PR conventions, the cloud-session handoff checklist,
  review culture, and the danger list of stale PRs and dead command files. Triggers:
  "commit this", "open a PR", "merge", "can I change this enum/schema/YAML key", "the
  snapshot hash changed", "handoff", "which branch", "/commit", "/pr", "/validate".
---

# framer — change control

How changes are classified, gated, committed, reviewed, and merged in this repo.
This skill library is the source of truth for process; CLAUDE.md routes here
since its 2026-07-09 rewrite. The older instruction chain it once pointed at
(`.ai-assistant/`) is dead — see "Stale doctrine" below.

## When NOT to use this skill

| You actually want | Go to sibling |
|---|---|
| Triage a bug / failure symptom | framer-debugging-playbook |
| Full story behind an incident named here | framer-failure-archaeology |
| Why an invariant exists architecturally | framer-architecture-contract |
| Metal shader mechanics (adding a GPU effect) | framer-metal-pipeline-reference |
| Add/modify a config parameter or YAML key (the checklist) | framer-config-and-flags |
| Build/toolchain setup, xcodegen, signing | framer-build-and-env |
| What counts as test evidence; snapshot test mechanics | framer-validation-and-qa |
| Which docs are stale (full ledger) | framer-docs-and-writing |
| Sidebar/UI component rules | framer-ui-design-system |

---

## The non-negotiables

Each rule below is: **rule → rationale → incident/evidence**. Violating these
is how real damage happened in this repo's history.

### 1. No autonomous merges or pushes to main

**Rule (maintainer ruling, 2026-07-09):** AI sessions may branch, commit
locally, and open PRs *when asked*. A human decides every merge to main. Never
`git merge` into main, never `git push origin main`, never `gh pr merge`.

**Rationale:** Development here is heavily multi-agent (Claude Code, Codex,
cloud Linux sessions, the Sisyphus orchestrator all appear in history).
The human maintainer is the only serialization point. Merges also carry data
risk here (see rule 4 — a bad decode change deletes user preset files).

### 2. Never blind-refresh snapshot-test hashes

**Rule (maintainer ruling, 2026-07-09):** `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`
locks UI surfaces as SHA-256 hashes of rendered bitmaps (`expectedSHA256:` string
literals in the file). When a baseline shifts unexpectedly:

1. Do NOT paste the new hash in and move on.
2. Render and READ the pixels; explain WHY the bitmap changed. From the
   sidebar-harmony learnings (`.sisyphus/notepads/sidebar-harmony/learnings.md`):
   "Snapshot diff is the forcing function; read the pixels, not the diff."
3. Land the hash refresh **in the same commit** as the change that caused it —
   historically 1–4 hashes per commit — so `git bisect` can attribute any
   visual regression to one step.

**Incident:** During sidebar pass 3 (PR #8), a reviewer-suggested "simplification"
(replacing the `SidebarControlRowTrailingValueContent` result-builder with a
generic `TrailingValue: View`) looked semantically transparent — but a snapshot
hash failed. Investigation showed `if flag { row }` resolves to
`_ConditionalContent<Row, EmptyView>`, defeating type-based `== EmptyView`
checks, so a divider rendered under conditionally-empty content. The change was
**reverted because the hash caught it**. A blind refresh would have shipped the
regression. Full story: framer-failure-archaeology; the UI rule itself:
framer-ui-design-system.

Cross-machine caveat: the hashes are known fragile across machines (font
rasterisation, GPU compositing) but catch "EVERY layout drift" locally
(learnings.md). Do not refresh hashes from a second machine without a
maintainer decision. Baseline-regeneration policy on a new machine is an open
question — framer-campaign-restore-validation's P3 gate drives the decision;
the resulting rule gets recorded in framer-validation-and-qa (owner of the
refresh mechanics).

### 3. Conventional commits, with scopes

**Rule:** `type(scope): summary` — types `feat/fix/refactor/test/docs/chore`.
Scopes in real use (verified in `git log`, as of 2026-07-09): `(sidebar)`,
`(gpu-effects)`, `(dither)`, `(caption)`, `(presets)`, `(app)`, `(filmstrip)`.

Examples straight from main:

```
fix(gpu-effects): pixel-sort parity — blend semantics + hide dead common adjustments
refactor(presets): extract PresetThumbnailCache as dedicated @Observable
docs(sidebar): add pass-2 TDD plan to repo history
```

One task per commit; the commit is the bisect unit. Keep the app buildable at
every commit — history contains a cautionary pair: `c515147` broke the build
and `ae4b8ba` is literally titled "fix: add missing userFacingCases static
(c515147 broke the build)". Run `swift build` before committing.

### 4. Back-compat decoding: never remove legacy decode branches

**Rule:** Anything `Codable` that reaches a preset file or YAML config must
keep decoding every value it ever encoded. Add fields as `decodeIfPresent`
with legacy defaults; keep legacy keys readable forever; map old semantics in
the decoder.

**Rationale — this is a DATA-LOSS gate, not a style rule:**
`PresetStore.list()` in `Sources/FramerCore/Presets/PresetStore.swift`
(lines 56–65, as of commit 48d85a5) **deletes any preset JSON file that fails
to decode**:

```swift
} catch {
    // Remove corrupted/empty JSON files so they don't persist.
    try? FileManager.default.removeItem(at: url)
}
```

The deletion is intentional (one corrupt file must not persist), but it means
a Codable regression that makes *valid* stored presets undecodable will
silently and permanently destroy the user's preset library on the first
launch. There is no undo.

**Live exemplars of the pattern — study these before touching any schema:**

| Exemplar | Where | What it does |
|---|---|---|
| Kuwahara legacy `sharpness` | `Sources/FramerCore/Models/CompositionLayer.swift`, `KuwaharaShaderParams` (~lines 1411–1456) | Old field `sharpness` (0..8, inverted: higher = less effect) replaced by `softness` (0..1). Decoder accepts either; legacy maps via `softness = 1 - sharpness/8`. `sharpness` stays in `CodingKeys` as a read-only legacy key. |
| `CaptionMode.none` | `Sources/FramerCore/Models/ProcessingConfig.swift` (~line 146) | The `.none` case was removed from the UI picker (layer visibility toggle supersedes it) but the enum case stays for preset-YAML back-compat; legacy layers auto-migrate to `.template` in the UI. |
| Hidden `GPUEffectKind` cases | `Sources/FramerCore/Effects/Models/GPUEffectKind.swift`, `userFacingCases` (~lines 42–49) | `.ascii`, `.halftone`, `.dithering` are hidden from the layer-add picker (canonical paths live elsewhere) but the enum cases are explicitly "preserved (YAML back-compat, preset roundtrip, Codable)". Do not delete them. |

Adding a parameter end-to-end has its own checklist: framer-config-and-flags.

### 5. Parity tests stay green while the CPU path exists

**Rule:** Every GPU effect currently has a CPU twin. The dispatch contract is
mechanical: `ShaderRenderer.gpuOrCPU` (`Sources/FramerCore/Processing/ShaderRenderer.swift`,
~lines 72–90) falls back to CPU **only** on `MetalEffectError` — any other
error bubbles up so real bugs surface. `Tests/FramerCoreTests/EffectGPUParityTests.swift`
enforces CPU≈GPU tolerances (and self-skips via `XCTSkip` when no Metal device).
While both paths exist, a shader change means **both paths get the same patch
in the same commit**, and `swift test --filter EffectGPUParityTests` must pass.

**Rationale:** CPU/GPU divergence is the single most recurring bug class in
this repo (pixel-sort sort-criteria math, amount blend-vs-rank semantics,
gamma, Y-flips — see framer-failure-archaeology). The parity tests are the
only automated guard.

**Important nuance (maintainer, 2026-07-09):** parity is *current mechanical
reality, not eternal doctrine*. The maintainer questions whether the CPU path
is needed at all ("we will always have Metal available"). "Retire the CPU
path" is an OPEN architectural decision — owned by framer-architecture-contract
and framer-research-frontier. Do not treat parity as sacred forever; do not
treat it as already retired either. Today: keep the tests green.

### 6. Prefer true merges over cherry-picks

**Rule:** Land branch work through a PR with a real merge commit. Do not
cherry-pick a branch's content onto main and delete the branch.

**Incident:** The entire `.gpuEffect` bucket-system architecture entered main
via a single cherry-pick — commit `ffeffe1` "feat: cherry-pick .gpuEffect
bucket-system from feat/grainrad-gpu-effects WIP" — after which the source
branch was deleted. The bucket system's development history (why decisions
were made, intermediate states) is permanently gone; `docs/gpu-effects-parameter-matrix.md`
is the surviving spec (and is itself partially stale — see framer-docs-and-writing).
Merged PRs on main have true 2-parent merge commits (verified: `42a5b47` PR #8,
`0127ad4` PR #9, `48d85a5` PR #10).

Corollary: before deleting a branch, check `git cherry main <branch>` to
confirm its commits are patch-equivalent to main.

---

## Change classification: which bar must your change clear?

| Change touches | Gate (in addition to `swift build && swift test`) | Why this bar |
|---|---|---|
| **Core render path** — `Sources/FramerCore/Processing/`, `Sources/FramerCore/Effects/` | Highest bar: `swift test --filter EffectGPUParityTests` green; both CPU+GPU patched together (rule 5); visual check of a real image through the CLI (framer-run-and-operate) | Pixel output is the product; parity divergence is the top historical bug class |
| **Serialization / schema** — `CompositionLayer.swift`, `ProcessingConfig.swift`, `YAMLConfig.swift`, anything `Codable` in presets | Back-compat bar (rule 4): legacy keys keep decoding; round-trip tests (JSON + YAML) for new fields; NEVER remove a decode branch | `PresetStore.list()` deletes undecodable files — schema regressions destroy user data |
| **macOS UI** — `Sources/FramerApp/`, especially `Sidebar/` | Snapshot-hash discipline (rule 2); `xcodegen generate` after adding files, then `xcodebuild test` (broken on some machines — see framer-build-and-env and framer-campaign-restore-validation); design rules in framer-ui-design-system | SHA-256 snapshots are the only layout regression guard |
| **Metal shaders** — `Sources/FramerCore/Effects/Metal/*.metal` | Both-paths-same-patch while CPU path exists (rule 5); note `swift test` passing does NOT validate the Xcode-built Metal path (framer-metal-pipeline-reference) | Every new shader port has historically shipped 1–3 parity bugs |
| **Docs / skills** — `docs/`, `.claude/skills/` | Lowest gate: accuracy. Date-stamp volatile facts; never present unmerged work as shipped | Stale docs are an active hazard here (see staleness ledger in framer-docs-and-writing) |

If a change spans classes, it clears the highest applicable bar.

---

## Branch, PR, and merge conventions

- **Branch names** follow `type/short-description` matching the commit types:
  `fix/preview-priority-inversion`, `feat/lut-layer`, `chore/cleanup-legacy-configs`.
  Cloud sessions get generated names (`claude/gpu-effects-migration-MbMMo`);
  orchestrators use their own prefix (`sisyphus/swiftui-review`).
- **PRs** are the merge vehicle. PR bodies in this repo carry full root-cause
  analyses (PR #11 is a model: symptom → mechanism → fix → why it's safe).
  Write that way — the body outlives the branch.
- **Merging is human-only** (rule 1). Merges are true merge commits (rule 6).
- **Bot review:** `chatgpt-codex-connector[bot]` reviews PRs (verified on
  PR #12); its findings get addressed in follow-up commits cited in the reply
  threads (e.g. fix commit `12c42a9` answering Codex on PR #12).

## Cloud / remote-session handoff protocol

Some sessions run where the code cannot be compiled (the 7-commit GPU port was
written on Linux with no Swift toolchain or Metal device). The house protocol,
established by `docs/gpu-migration-mac-resume.md` (2026-04-13), is:

**Any session that cannot build/run what it wrote MUST hand off with an
explicit ✅/❌ validation-status checklist.** The original, verbatim from that
doc's "Validation status when leaving the cloud session":

```
- ✅ All files are syntactically structured (matched braces, sensible bodies)
- ✅ Imports look correct for macOS / iOS targets
- ✅ All commits pass `git push` (so no merge / authentication issues)
- ❌ `swift build` not run (no Swift toolchain in the cloud container)
- ❌ `swift test` not run (no Metal device in the cloud container)
- ❌ Visual smoke test not run
- ❌ Uniform layout sizes not verified at runtime
```

A conforming handoff doc also includes: the branch + commit list, a numbered
Mac-side resume checklist (build → targeted tests → visual smoke test), and a
**risk register** ordered by likelihood with symptom→fix pairs. Use
`docs/gpu-migration-mac-resume.md` as the template. The resuming session
treats every ❌ as its first task, in order.

## Review culture

- **Parallel reviewers with deliberately different prompts.** At the end of
  sidebar pass 3, three concurrent review agents — a bug-hunter, a Swift-idiom
  reviewer, and an architecture reviewer — each found real bugs the author had
  missed (a task-dictionary leak, CPU/GPU pixel-sort divergence, palette
  identity flicker), with near-zero duplicate findings because the prompts
  differed. Source: `.sisyphus/notepads/sidebar-harmony/learnings.md`
  ("Review process" section). This is the house pattern for end-of-pass review.
- **Verify review feedback before applying it.** The same pass produced the
  result-builder revert (rule 2's incident): a plausible reviewer suggestion
  broke a snapshot. Reviewer advice is a hypothesis, not an instruction.
- **When to request review:** end of any multi-commit pass; before opening a
  PR on core render path or schema changes; whenever a snapshot hash shifted
  for a reason you had to investigate.

## Stale doctrine — do NOT follow these

(As of 2026-07-09, commit 48d85a5.)

- **The old `.ai-assistant/` instruction chain is dead.** Until 2026-07-09,
  CLAUDE.md delegated to `.ai-assistant/` and `.ai-project/` — directories
  that never existed in git on any branch. CLAUDE.md was rewritten
  (2026-07-09) to route to this skill library. If you encounter the old
  CLAUDE.md — on a stale branch, or via PR #1 — do not follow it.
- **The 21 dead files in `.claude/commands/` (including `/validate`,
  `/implement`, `/wrap`, `/cover`, `/commit`, `/pr`) were REMOVED on
  2026-07-09.** Each began by delegating to a nonexistent
  `../../.ai-assistant/workflows/*.prompt.md`; some carried JS-project
  residue (npm audit, bundle size). If they reappear via a stale-branch
  merge, delete them again. Full staleness ledger: framer-docs-and-writing.
- `README.md` has materially stale facts (target list, preset paths) — details
  in framer-docs-and-writing.

## Danger list (as of 2026-07-09)

| Item | State | Ruling |
|---|---|---|
| **PR #1** `chore/cleanup-legacy-configs` | Open since 2026-03-14; 3 ahead / **295 behind** main; rewrites CLAUDE.md (85 lines changed) | Do NOT merge or rebase-and-merge as-is — it would clobber the rewritten CLAUDE.md with a 295-commit-stale version and resurrect the dead instruction chain. Human decision whether to close. |
| **PR #11** `fix/preview-priority-inversion` | Open, 1 commit, 0 behind; fully-diagnosed QoS priority-inversion fix | Merge is the maintainer's call (rule 1). Do not present its content as shipped. |
| **PR #12** `fix/effect-params-and-editor-bugs` | Open, 11 commits, 0 behind; Codex review findings addressed in `12c42a9` | Same: human-decision merge. Its parameter-defaults work is UNMERGED — don't cite it as current behavior. |
| `xcodebuild` test tier | Broken on the primary dev machine (revoked signing cert — `CSSMERR_TP_CERT_REVOKED`, not merely expired — + missing Metal Toolchain) | Repair campaign: framer-campaign-restore-validation (P1 owns cert state and remediation). Don't gate commits on it until repaired; `swift build && swift test` is the working gate. |

## Provenance and maintenance

All claims verified 2026-07-09 against main @ 48d85a5 by direct file reads and
read-only git/gh commands. Re-verify volatile facts with:

| Fact | Re-verification command |
|---|---|
| PresetStore deletes undecodable presets | `grep -n "removeItem" Sources/FramerCore/Presets/PresetStore.swift` (expect it inside `list()`'s catch) |
| Kuwahara legacy sharpness mapping | `grep -n "sharpness" Sources/FramerCore/Models/CompositionLayer.swift` |
| CaptionMode.none still present | `grep -n "case none" Sources/FramerCore/Models/ProcessingConfig.swift` |
| Hidden GPUEffectKind cases | `grep -n "userFacingCases" Sources/FramerCore/Effects/Models/GPUEffectKind.swift` |
| gpuOrCPU falls back only on MetalEffectError | `grep -n "MetalEffectError" Sources/FramerCore/Processing/ShaderRenderer.swift` |
| Parity tests exist + self-skip | `grep -n "XCTSkip" Tests/FramerCoreTests/EffectGPUParityTests.swift` |
| Snapshot hashes are SHA-256 literals | `grep -c "expectedSHA256" Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` |
| Cherry-pick incident commit | `git show -s ffeffe1` |
| Build-break commit pair | `git show -s --oneline c515147 ae4b8ba` |
| PRs merge as true merges | `git rev-list --parents -n1 48d85a5` (expect 2 parents) |
| Open PR set + staleness | `gh pr list --state open` ; `git rev-list --count origin/chore/cleanup-legacy-configs..origin/main` |
| Dead command files stay dead | `grep -rl ".ai-assistant" .claude/commands/ \| wc -l` (expect 0 — the 21 dead files were removed 2026-07-09) ; `ls .ai-assistant` (expect: no such directory) |
| Handoff checklist doc | `grep -n "not run" docs/gpu-migration-mac-resume.md` (expect the ✅/❌ block) |
| Review-culture source | `grep -n "Three parallel review agents" .sisyphus/notepads/sidebar-harmony/learnings.md` |

Facts most likely to drift: the open-PR table, the 21-file dead-command count,
the xcodebuild-tier brokenness, and rule 5's CPU-path status (an open
architectural decision — check framer-architecture-contract for updates).
