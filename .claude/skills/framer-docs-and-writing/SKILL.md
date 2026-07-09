---
name: framer-docs-and-writing
description: Load when reading or writing ANY documentation in this repo — before trusting CLAUDE.md, README.md, docs/*.md, docs/plans/, docs/superpowers/, docs/product-review/, or .claude/commands/; when a doc contradicts the code; when writing a new implementation plan, changelog entry, learnings notepad, cloud-handoff doc, or skill; or when doing release/version work (CHANGELOG vs git tags vs MARKETING_VERSION). Owns the staleness ledger (which docs lie and what to trust instead), the plan-driven house style, and all writing templates.
---

# framer-docs-and-writing — the record, what's stale, and how to write

This skill is the map of the repo's documentation: which docs are load-bearing,
which are stale (and exactly how), how releases are (mis)recorded, and the house
templates for plans, handoffs, learnings, and skills.

Baseline for every claim: **2026-07-09, main @ commit 48d85a5** unless noted.

## When NOT to use this skill

| You actually want | Go to sibling |
|---|---|
| Commit gating, branch/PR conventions, merge policy | framer-change-control |
| Triage a failure symptom | framer-debugging-playbook |
| Full story of a past incident | framer-failure-archaeology |
| Design decisions, invariants, open architecture questions | framer-architecture-contract |
| Test estate, snapshot-hash discipline (deep rules) | framer-validation-and-qa |
| Build/setup commands and toolchain traps | framer-build-and-env |
| Running the CLI/app, output locations | framer-run-and-operate |
| UI tokens and sidebar grammar | framer-ui-design-system |
| Actual release execution mechanics | framer-change-control + this skill's release section |

## 1. Docs-of-record hierarchy

When two sources disagree, trust the higher tier. **Code always beats docs.**

1. **`.claude/skills/` (this library)** — declared the source of truth by the
   maintainer on 2026-07-09. CLAUDE.md's old instruction chain is dead (see ledger).
2. **`docs/superpowers/plans/` + `docs/superpowers/specs/`** — executed TDD plans
   and design specs. These were run task-by-task and match shipped code closely
   (verify against code anyway; they are snapshots of intent at execution time).
3. **`docs/plans/` (dated files, 2026-02-22 … 2026-04-01)** — historical design
   records. Most shipped; at least one is dead paper (see ledger). Read as
   "why we did it", never as "how it works today".
4. **Code doc-comments** — e.g. the long rationale comment on
   `userFacingCases` in `Sources/FramerCore/Effects/Models/GPUEffectKind.swift`.
   These are maintained with the code and are the freshest prose in the repo.
5. **README.md / CLAUDE.md / docs/index.html** — stale entry points. Useful for
   flavor, unreliable for facts. Details in the ledger.

Special mention: **`.sisyphus/notepads/sidebar-harmony/learnings.md`** (107 lines,
checked into main) is the richest operational-lessons document in the repo despite
its disposable-looking path. Its content has been absorbed into the sibling skills
(framer-failure-archaeology, framer-validation-and-qa, framer-ui-design-system);
treat the file itself as a primary source of record, not scratch.

## 2. THE STALENESS LEDGER

Every entry below was re-verified against main @ 48d85a5 on 2026-07-09.
**Do not edit the stale docs to "fix" them without maintainer direction — but DO
update this ledger whenever you resolve or discover a doc-vs-code contradiction.**

| Doc | What's wrong | What to trust instead |
|---|---|---|
| `CLAUDE.md` | Tells assistants to read `.ai-assistant/.instructions.md` and `.ai-assistant/INDEX.md`, and points project config at `.ai-project/` — **neither directory exists** (verified: `ls` returns os error 2). Its "Available Commands" table (/implement … /pr) points at command files whose own instruction targets are dead (next row). | This skill library. The Quick Commands table in CLAUDE.md (swift build/test, xcodegen generate) is still accurate; see framer-build-and-env for the authoritative version. |
| `.claude/commands/*.md` (21 of 29 top-level files) | Each begins "Follow **[x.prompt.md](../../.ai-assistant/workflows/x.prompt.md)**" — all targets nonexistent. `validate.md` is a JS-project template ("npm audit", bundle size), and `.claude/settings.json` allowlists `npm run typecheck/lint/test/build` — this is a Swift repo with no npm. | framer-change-control for workflow; framer-validation-and-qa for what validation means here. The commands' inline text (phase gates, conventional commits) survives as de-facto convention only. |
| `README.md` | (a) Line 56: "Swift Package with three targets" listing FramerCore/FramerCLI/FramerApp — `Package.swift` actually declares only **FramerCore + FramerCLI** (plus two test targets); FramerApp (macOS, product name "Framer") and **FramerMobile (iOS, omitted entirely)** are XcodeGen targets in `project.yml`. (b) Line 52: presets "save and load from `~/.config/framer/presets/`" — wrong; `PresetStore.swift` uses `~/Library/Application Support/Framer/presets/`, and `~/.config/framer/` only holds `default.yaml` as the last-resort config fallback (`YAMLConfig.loadDefault`, priority: `--config` → App Support preset → `./.framer.yaml` → `~/.config/framer/default.yaml`). (c) Layer list (lines 28–34) stops at Dither — omits aspectRatio, LUT, shader, and gpuEffect layers, zoom, and the Darkroom Editorial UI. The LUT *benchmark* section (lines 137–166) is accurate and dated 2026-04-01. | `Package.swift` + `project.yml` for targets; `Sources/FramerCore/Presets/PresetStore.swift` and `YAMLConfig.swift` for paths; framer-config-and-flags for the layer catalog. |
| `docs/gpu-effects-parameter-matrix.md` | Line 15 lists `pixelSort` among variants "hidden from picker". Stale: sidebar-harmony pass 4 re-exposed it. `GPUEffectKind.userFacingCases` now hides only `.ascii`, `.halftone`, `.dithering` (with a long doc comment explaining why, including the "Dithering doesn't have the presets" user report). Common-adjustments wiring also changed after the doc's snapshot. | `Sources/FramerCore/Effects/Models/GPUEffectKind.swift` (the `userFacingCases` doc comment is the record). framer-config-and-flags owns the parameter catalog. |
| `docs/plans/2026-04-01-metal-dither-plan.md` | Header says "Status: Planned / Branch: feat/metal-dither (not yet created)" and lays out a `MetalDitherPipeline` under a Processing/Metal layout. **Superseded, never executed as written**: GPU dithering shipped via the Effects bucket (`Sources/FramerCore/Effects/Metal/Dither.metal` + DitherGPURenderer); `Sources/FramerCore/Processing/Metal/` does not exist. | `docs/gpu-migration-plan.md` and `docs/gpu-migration-mac-resume.md`; framer-metal-pipeline-reference. |
| `docs/superpowers/plans/2026-04-02-acerola-shader-layer-handoff.md` | Describes a live branch `feat/acerola-shader-layer` with "uncommitted work" in worktree `~/Github/framer-acerola-shader`. The branch is fully merged, the worktree is gone, and the "uncommitted" `ASCIIColorMode.dominantTwoTone` is on main. Its absolute-path file links are dead. | Main's code. Only the doc's "Recommended Next Steps" (visual tuning of ASCII / PixelSort / composite looks) remain open — tracked in framer-campaign-gpu-effects-quality. |
| `docs/index.html` + `docs/examples/` | Go-era GitHub Pages site, last touched 2026-01-23 (a month before the Swift rewrite). Says "Requires Go 1.22+"; example commands use `-s instagram` — the Swift CLI's `--border-style` has **no short flag**, so those commands fail as written (`framer -i … -o …` itself still works: ProcessCommand is the default subcommand and input/output are `.shortAndLong`). The `docs/examples/*.jpg` goldens were rendered by the deleted Go implementation — regenerating them with the Swift CLI would produce different pixels. | framer-run-and-operate for real CLI usage. |
| `docs/product-review/` (7 files) | A March 7, 2026 go-to-market snapshot (PMF interviews, freemium pricing, Lightroom-plugin roadmap, an April-30 "pivot or proceed" gate). **No validation outcome is recorded anywhere in the repo**, and its "iOS is the wrong platform" ranking was contradicted by building FramerMobile anyway. | Treat as historical strategy context only. Open question for maintainer: what was decided at the gate? |
| `assets/design/DESIGN_BRIEFING.md` (paths only) | Lines 5 and 320 reference the mockup at `docs/design/framer-final-concept.html` — `docs/design/` does not exist. Actual mockups: `assets/design/framer-final-concept.html` and `assets/design/ios/framer-ios-concept.html`. The design *content* is largely binding law — but its 280pt fixed inspector width is superseded by `SidebarLayoutPolicy`'s 300/350/520 band (min/ideal/max; the earlier 304/320/352 band was itself superseded by commit c83b509, 2026-04-15). | framer-ui-design-system owns the corrected design rules. |
| `CHANGELOG.md` `[Unreleased]` | Titled "GPU effects migration (PR #7)" — but PR #7 **merged 2026-04-14** (verified via `gh pr view 7`). The section was never rolled into a release, and nothing merged after 2026-04-14 (PR #8 sidebar harmony, PRs #9/#10 of 2026-05-25) is recorded at all. | Git history is the only complete change record past 2026-04-14. See §3. |

**Ledger maintenance rule:** this table is a living document. When you fix a
contradiction (e.g., README gets rewritten, a stale doc gets deleted), update or
remove its row in the same PR. When you *find* a new contradiction anywhere in
the repo, add a row here even if you don't fix the doc.

## 3. Release records: four sources, none agree

Verified state as of 2026-07-09, commit 48d85a5:

| Source | Says | Verify with |
|---|---|---|
| `CHANGELOG.md` | Keep-a-Changelog + SemVer; sections `[Unreleased]` (PR #7 work, already merged), `[2.0.0] - 2026-02-24`, `[1.0.0] - 2025`. Last commit touching it: 0debb71, 2026-04-14. | `grep -n '^## \[' CHANGELOG.md` |
| Git tags | `v1.0.0`, `v1.1.0`, `v1.2.0` — **v2.0.0 was never tagged** despite the CHANGELOG entry and a team-review action item to tag it. | `git tag` |
| `project.yml` macOS target | `MARKETING_VERSION: "2.0.0"` (line 40, Framer app target) | `grep -n MARKETING_VERSION project.yml` |
| `project.yml` iOS target | `MARKETING_VERSION: "1.0.0"` (line 90, FramerMobile) | same |

Any release work MUST reconcile all four: decide the next version, roll
`[Unreleased]` (and backfill the PR #8/#9/#10 gap from `git log`), tag, and align
both MARKETING_VERSIONs — and remember **merging/tagging is a human decision**
(house rule; see framer-change-control). Open question owned by the maintainer:
tag v2.0.0 retroactively at the 2026-02-24 rewrite, or start fresh from HEAD.

## 4. House plan style (plan-driven development)

Every substantial change in this repo's recent history was executed from a dated
markdown plan. The canonical exemplar is
`docs/superpowers/plans/2026-04-16-sidebar-harmony-pass-2.md` (1,547 lines,
executed as PR #8). The style, extracted from that file:

1. **Dated filename**: `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`
   (older plans live in `docs/plans/`; design specs in `docs/superpowers/specs/`).
2. **Agentic-worker header** on line 3, verbatim:
   `> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.`
3. **Preamble blocks**: `**Goal:**`, `**Architecture:**`, `**Tech Stack:**`,
   `**Reference:**` (pointer to a visual target spec when one exists, e.g.
   `docs/sidebar-harmony-target/index.html`).
4. **File Map** with `### Create` / `### Modify` lists — every file the plan
   touches, each with a one-line reason.
5. **Tasks in strict TDD step order**, each step a `- [ ]` checkbox:
   write failing test → **run it to verify it fails** → implement → **run it to
   verify it passes** → commit. Expected command output is stated inline
   ("Expected: PASS — …").
6. **One task per commit**, with the exact conventional-commit message written
   into the plan (e.g. `git commit -m "feat(sidebar): add SidebarTrailingReadoutCluster primitive"`).
7. **App functional throughout** — no task may leave the app broken.
8. **Learnings checkpoint**: the plan ends by committing an update to
   `.sisyphus/notepads/<topic>/learnings.md`
   (`git commit -m "docs(sidebar): capture pass 2 learnings checkpoint"`).
9. **Snapshot hashes refresh in the same commit as the change that shifted them**
   (1–4 hashes per commit for bisectability) — never blind-refresh; deep rules in
   framer-validation-and-qa.

## 5. Commit style

Conventional commits with scopes, consistently used. Real examples from
`git log` on main:

```
feat(gpu-effects): make PixelSort Streak resolution-relative
fix(sidebar): make layer reordering drag reliable on macOS Sequoia
fix(dither): make Custom palette selection actually stick
refactor(presets): extract PresetThumbnailCache as dedicated @Observable
docs(sidebar): refresh pass-2 target spec + pass-3 learnings
chore(app): refresh app icons from updated master
```

Types in active use: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
Scopes in active use: `sidebar`, `gpu-effects`, `dither`, `presets`, `app`,
`filmstrip`, `caption`, `slider`. Subject lines are imperative and specific;
em-dash sub-clauses are common (`fix(gpu-effects): pixel-sort parity — blend
semantics + hide dead common adjustments`). Merge policy, gating, and PR
conventions live in framer-change-control.

## 6. Templates

### 6a. Dated-plan skeleton

```markdown
# <Topic> Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** <one sentence: the user-visible outcome>

**Architecture:** <how, in 3-5 sentences; name every new type>

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, XcodeGen (`project.yml`), macOS 14+ <adjust>

**Reference:** <path to visual target spec, if any>

---

## File Map

### Create
- `Sources/...` — <why>

### Modify
- `Sources/...` — <why>

---

## Task 1: <name>

- [ ] **Step 1: Write the failing test**
  <test code / description>
- [ ] **Step 2: Run test to verify it fails**
  ```bash
  <exact command>
  ```
  Expected: FAIL — <why>
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run test to verify it passes**
  Expected: PASS
- [ ] **Step 5: Commit**
  ```bash
  git add <files>
  git commit -m "<type>(<scope>): <subject>"
  ```

<repeat tasks; final task commits the learnings-notepad checkpoint>
```

Reminder: any new file under `Sources/FramerApp/` or `Tests/FramerAppTests/`
requires `xcodegen generate` before `xcodebuild test` sees it — plans that create
files must include that step (details in framer-build-and-env).

### 6b. Cloud-handoff validation checklist

When a cloud/Linux session (no Swift toolchain, no Metal) hands work to a Mac,
it MUST ship a handoff doc. Model: `docs/gpu-migration-mac-resume.md`. Required
sections, in order:

```markdown
# <Work> — Mac-side resume context

**Authored on <environment>, <date>. Read this first when resuming on Mac.**

## TL;DR
<what landed, on which branch, in how many commits.
 State plainly: "Nothing has been compiled or executed." if true.>

## Mac-side resume checklist
```bash
# 1. Pick up the branch
git checkout <branch> && git pull
# 2. Build
swift build
# 3. Targeted tests
swift test --filter <Suite>
# 4. Visual/CLI smoke test
swift run framer process --input <img> ... --output /tmp/check.png
```

## Mac-side risk register
<numbered, in order of likelihood: Symptom / Fix for each unproven assumption>

## Validation status when leaving the cloud session
- ✅ <what WAS verified (syntax, imports, pushes)>
- ❌ `swift build` not run (no Swift toolchain in the container)
- ❌ `swift test` not run (no Metal device in the container)
- ❌ Visual smoke test not run
```

The ✅/❌ honesty block is the load-bearing part: the original doc's candor
("Nothing has been compiled or executed") is what made the Mac-side resume safe.

### 6c. Learnings-notepad entry format

Location: `.sisyphus/notepads/<topic>/learnings.md`, updated at plan checkpoints
and committed (`docs(<scope>): capture <topic> learnings checkpoint`). Format,
per the sidebar-harmony exemplar:

- One `##` section per pass/phase, dated (`## Pass 3 (2026-04-16) — …`), with
  `###` subsections by theme (fixes / architecture / tests / review process).
- Each lesson is ONE bullet: **symptom → root cause → fix → why it stays that
  way**, with `file.swift:line` citations for every claim.
- Record reverted experiments WITH the reason ("attempted the refactor, watched
  a snapshot fail … reverted, documented WHY") — negative results are the most
  valuable entries.
- Record process lessons too (e.g. "three parallel review agents with different
  prompts found real bugs the author missed").

### 6d. Skill provenance section (for maintaining THIS library)

Every skill in `.claude/skills/` must end with a `## Provenance and maintenance`
section:

```markdown
## Provenance and maintenance

All claims verified <date> against main @ <short-sha> unless marked otherwise.
Unverifiable claims are labeled "(unverified — re-check)".

Re-verification one-liners for facts that may drift:
- <fact>: `<read-only command>`
```

Rules: date-stamp volatile facts inline; label anything unproven as
open/candidate (never present aspiration as reality); when a sibling skill owns
a fact, link to it instead of duplicating (one home per fact).

## 7. Writing rules of the house

- **Code beats docs; measurements beat eyeballs.** Never assert a behavior a
  doc claims without checking the code (this ledger exists because docs lie).
  Measurement methods live in framer-diagnostics-and-proof.
- **Date everything volatile.** Filenames for plans, inline "(as of …)" for
  facts, "Measured on YYYY-MM-DD" for benchmarks (README's LUT section does
  this correctly — imitate it).
- **Absolute paths are forbidden in docs.** The acerola handoff's dead
  `/Users/arthur.soares/...` links are the cautionary tale. Repo-relative only.
- **Superseded ≠ deleted.** Dead plans stay in `docs/plans/` as history; mark
  them in this ledger rather than removing them.
- **Handoffs state what was NOT verified** as prominently as what was (§6b).

## Provenance and maintenance

All claims verified 2026-07-09 against main @ 48d85a5 by reading files and
running read-only git/gh commands. Nothing here is from memory or hearsay;
the docs/examples goldens' Go provenance is inferred from their last-touch date
(2026-01-23, pre-Swift-rewrite) and index.html's "Requires Go 1.22+".

Re-verification one-liners:
- Dead instruction chain: `ls .ai-assistant .ai-project` (expect: No such file or directory)
- Stale command files count: `grep -l 'ai-assistant' .claude/commands/*.md | wc -l` (was 21)
- npm-flavored settings: `grep -n 'npm' .claude/settings.json`
- README target table: `sed -n '56,63p' README.md` vs `grep -n 'name:' Package.swift`
- README preset path: `grep -n 'config/framer' README.md` vs `sed -n '1,15p' Sources/FramerCore/Presets/PresetStore.swift`
- Config priority: `sed -n '280,305p' Sources/FramerCore/Presets/YAMLConfig.swift`
- pixelSort exposure: `grep -n 'userFacingCases' -A 8 Sources/FramerCore/Effects/Models/GPUEffectKind.swift` vs `grep -n 'Hidden from picker' docs/gpu-effects-parameter-matrix.md`
- Metal dither plan superseded: `ls Sources/FramerCore/Processing/Metal` (expect: not found) and `ls Sources/FramerCore/Effects/Metal/Dither.metal`
- Acerola worktree gone: `ls ~/Github/framer-acerola-shader` (expect: not found); branch merged: `git branch --merged main | grep acerola`
- Go-era site: `grep -n 'Go 1.22' docs/index.html`; goldens date: `git log -1 --format='%ad' --date=short -- docs/examples/solid_black.jpg`
- CLI short flags: `grep -n 'customShort\|shortAndLong' Sources/FramerCLI/Commands/ProcessCommand.swift` (no `-s` for border style)
- Release state: `git tag`; `grep -n '^## \[' CHANGELOG.md`; `grep -n MARKETING_VERSION project.yml`; `gh pr view 7 --json state,mergedAt`
- CHANGELOG last touch: `git log -1 --format='%h %ad' --date=short -- CHANGELOG.md` (was 0debb71 2026-04-14)
- Plan style exemplar: `head -12 docs/superpowers/plans/2026-04-16-sidebar-harmony-pass-2.md`
- Design-briefing mockup path: `grep -n 'docs/design' assets/design/DESIGN_BRIEFING.md`; `ls assets/design/framer-final-concept.html`
- Learnings notepad: `wc -l .sisyphus/notepads/sidebar-harmony/learnings.md` (was 107)
- Commit style: `git log --format='%s' -20`
