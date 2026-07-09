---
name: framer-build-and-env
description: >
  Load when setting up the framer repo from scratch, when a build or test command fails
  with environment-flavored errors, or before adding files to the app/mobile targets.
  Triggers: fresh clone, "git lfs", 132-byte pointer files, overlays render as garbage,
  "xcodegen generate", xcodebuild can't find a new file or test, "Signing certificate ...
  is not valid for code signing", "Metal Toolchain was not installed", "iOS 26.5 is not
  installed", CoreSimulator version mismatch, "@testable import Framer" vs FramerApp
  module confusion, Package.resolved drift, unexplained pbxproj diffs, or the stale
  ./framer binary behaving like a Go program. Owns setup/build commands and environment
  failure modes for FramerCore/FramerCLI (SPM) and FramerApp/FramerMobile (xcodebuild).
---

# framer: build & environment runbook

All facts verified 2026-07-09 on the maintainer's machine at commit `48d85a5`
(main). Volatile numbers (test counts, versions, file counts) WILL drift — every
one has a re-verification command in "Provenance and maintenance" at the bottom.

**Jargon, defined once:**

- **SPM** — Swift Package Manager, driven by `Package.swift`; runs via `swift build` / `swift test`.
- **XcodeGen** — a tool that generates `Framer.xcodeproj` from the declarative `project.yml`. The generated project IS committed to git.
- **Git LFS** — Git Large File Storage; big binaries live on a separate server, the repo holds tiny pointer files until you `git lfs pull`.
- **Metal Toolchain** — the offline Metal shader compiler. In Xcode 26 it is a separately downloaded component, NOT installed by default.
- **metallib** — a precompiled Metal shader library (`default.metallib`) produced by the Metal Toolchain at build time.

## When NOT to use this skill

| You actually want to... | Go to sibling |
|---|---|
| Run the CLI or the app, find output files | framer-run-and-operate |
| Know what counts as passing evidence, snapshot-hash discipline, test estate map | framer-validation-and-qa |
| Fix the broken xcodebuild-test tier for real (cert + Metal Toolchain + iOS platform) | framer-campaign-restore-validation |
| Understand Metal shader loading/uniforms internals | framer-metal-pipeline-reference |
| Diagnose a rendering bug (not a build failure) | framer-debugging-playbook |
| Commit/branch/PR rules | framer-change-control |
| Which docs are stale (CLAUDE.md, README, .claude/commands) | framer-docs-and-writing |

---

## THE XCODEGEN RITUAL (read this before anything else)

The single most common environment trap in this repo:

**After adding, deleting, or renaming ANY file under `Sources/FramerApp/`,
`Sources/FramerMobile/`, or `Tests/FramerAppTests/`, you MUST run:**

```bash
xcodegen generate
```

Why: `Framer.xcodeproj` is a committed **snapshot** generated from `project.yml`.
XcodeGen resolves folder globs at generate time, so the checked-in project does
not know about files created after the last generation. `swift build` is
unaffected (SPM globs live); only the Xcode targets go stale.

Symptoms without the ritual:
- `xcodebuild test` fails to compile the target even though `project.yml` points at the whole directory.
- New test methods/classes are silently not discovered.

If tests are still stale after regenerating (known recurring issue, recorded in
`.sisyphus/notepads/sidebar-harmony/learnings.md`):

```bash
xcodegen generate && xcodebuild clean test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
```

Two follow-on facts about the committed project file:

1. **Regeneration churn in `git diff` is normal.** Newer xcodegen/Xcode pairs emit
   slightly different pbxproj boilerplate. As of 2026-07-09 the working tree
   carries exactly this churn: `compatibilityVersion = "Xcode 14.0"` removed,
   `productRefGroup` line added — 1–2 cosmetic lines, harmless.
2. **Commit the regenerated pbxproj alongside the file change** that forced
   regeneration, so a fresh checkout builds without rerunning xcodegen.
   (Whether to pin the xcodegen version to stop the churn is an open question —
   `project.yml:9` only sets `minimumXcodeGenVersion: "2.38"`.)

---

## From-scratch setup (the happy path)

Prerequisites: macOS with Xcode 26.x, `git-lfs` and `xcodegen` installed
(Homebrew: `brew install git-lfs xcodegen` — standard, unverified here).

```bash
# 1. Clone
git clone git@github.com:arthursoares/framer.git
cd framer

# 2. Hydrate LFS textures — REQUIRED before overlays render correctly
git lfs install
git lfs pull

# 3. Build the SPM tier (FramerCore library + framer CLI)
swift build
# Expect: "Build complete!" in ~15s clean, <1s warm. No Metal Toolchain needed.

# 4. Run the SPM test tier
swift test
# Expect (2026-07-09): "Executed 268 tests, with 0 failures (0 unexpected) in ~3.9 seconds"
# The count WILL drift — see provenance section. All tests are XCTest;
# a "0 tests in 0 suites" Swift Testing line also prints and is normal.

# 5. Generate the Xcode project for app work
xcodegen generate

# 6. Open in Xcode
open Framer.xcodeproj
```

Steps 5–6 currently get you an app that **builds in Xcode only after** the
Metal Toolchain is installed and signing is sorted — see "Currently-broken
tier" below. Steps 1–4 are fully green today.

### Git LFS details (what breaks without step 2)

- `.gitattributes` routes exactly `assets/textures/*.jpg`, `*.tif`, `*.png`
  through LFS — nothing else in the repo is LFS-tracked.
- As of 2026-07-09: **168 LFS files, ~338 MB checked out** under
  `assets/textures/`. (CLAUDE.md says "~150" — stale.)
- **Symptom without `git lfs pull`:** every texture is a 132-byte ASCII pointer
  file. The app/CLI still build and most tests pass, but overlay layers render
  garbage or nothing. (Pointer-state symptom is from CLAUDE.md's setup note —
  not reproducible on this hydrated machine, so treat the exact behavior as
  unverified; the pointer files themselves are how LFS works.)
- **Deliberate exception:** the two ASCII atlas PNGs
  `Sources/FramerCore/Resources/textures/edgesASCII.png` and `fillASCII.png`
  (80×8 RGBA) are duplicated OUTSIDE LFS on purpose, so `Bundle.module`
  resolves them for the CLI and tests even on a clone without LFS content.
  Do not "clean up" this duplication and do not move them under the LFS glob.
  (Rationale is in the `Package.swift` comment above `.copy("Resources/textures")`.)

---

## Toolchain reality vs. what the docs say (as of 2026-07-09)

| Axis | Actually in use | What docs/config claim | Verdict |
|---|---|---|---|
| Swift compiler | 6.3.3 (arm64-apple-macosx26.0) | CLAUDE.md: "Swift 5.10" | Docs stale. `Package.swift` pins `swift-tools-version: 5.10` — that is the *manifest language version*, fine to keep; the compiler is 6.3.3. |
| Xcode | 26.6 (build 17F113) | `project.yml:12` `xcodeVersion: "16.0"` (generation hint only) | Works, but explains pbxproj churn. |
| xcodegen | 2.45.4 | `project.yml:9` minimum 2.38 | Fine; version skew causes cosmetic pbxproj diffs. |
| git-lfs | 3.7.1 | not pinned anywhere | Fine. |
| Metal Toolchain | **uninstalled** (`xcodebuild -showComponent metalToolchain` → `Status: uninstalled`) | assumed present by any xcodebuild flow | BROKEN — see below. |
| CI | none (`.github/` does not exist) | — | Local `swift build && swift test` is the only gate. See framer-change-control. |

CLAUDE.md's instruction chain (`.ai-assistant/`, `.ai-project/`) is **dead** —
those directories do not exist, and 21 files under `.claude/commands/` point
into them. Also, `.claude/settings.json` allowlists `npm run ...` commands that
have no meaning in this Swift repo. Do not follow those; this skill library is
the source of truth. Full staleness ledger: framer-docs-and-writing.

---

## The two build systems — what each can and cannot do

This is a **two-tier build reality**. Internalize this table before debugging
anything.

| | Tier 1: SPM (`swift build` / `swift test`) | Tier 2: xcodebuild (Xcode project) |
|---|---|---|
| Builds | FramerCore (library), `framer` CLI executable | Framer.app (macOS), FramerMobile (iOS), FramerAppTests bundle |
| Tests | FramerCoreTests (20 files) + FramerCLITests (2 files) = 268 tests today | FramerAppTests (12 files, incl. all SwiftUI snapshot tests) |
| .metal shader handling | Files copied as **text resources**; `MetalEffectLibrary` compiles them **at runtime** via `makeLibrary(source:)` | Compiled **offline** to `default.metallib` by the Metal Toolchain |
| Needs Metal Toolchain? | **No** | **Yes** (hard requirement) |
| Needs code signing? | No | Yes (or `CODE_SIGNING_ALLOWED=NO`) |
| Status today | GREEN | **BROKEN on this machine** (see next section) |

The dual .metal path is implemented in
`Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift` (~lines 54–119): try
`makeDefaultLibrary(bundle:)` first (metallib present under Xcode builds), else
concatenate `ShaderCommon.h` + all `.metal` text resources and runtime-compile.
Details of the pipeline itself: framer-metal-pipeline-reference.

**The deceptive consequence:** a machine can pass `swift build && swift test`
perfectly and still be unable to build the app at all. Green tier 1 says
nothing about tier 2. Canonical tier-2 test invocation (from
`docs/superpowers/plans/2026-04-15-sidebar-layout-consistency.md`):

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
  -only-testing:FramerAppTests/SidebarMetricsTests
```

---

## Currently-broken tier: xcodebuild (as of 2026-07-09)

Three independent blockers, in the order you will hit them. Fixing them for
good is the framer-campaign-restore-validation campaign; this section is the
symptom map. Error strings captured 2026-07-09 on the maintainer's machine.

### Blocker 1 — revoked signing certificate

`xcodebuild test -scheme Framer -destination 'platform=macOS'` fails with:

```
Signing certificate "Apple Development: arthur@arthursoares.com.br (P7K6Z5BCV4)" ... is not valid for code signing
```

for both the Framer and FramerAppTests targets. Workaround to get past
signing (exposes Blocker 2):

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-
```

The certificate is **revoked** (`security find-identity -v -p codesigning`
shows `CSSMERR_TP_CERT_REVOKED`), not merely expired — waiting won't help.
Cert state and remediation are owned by framer-campaign-restore-validation P1.
Real fix: renew the Apple Development certificate in Xcode → Settings →
Accounts (needs the maintainer's Apple ID). Open question whether
signing-disabled is the accepted long-term mode — see the campaign skill.

### Blocker 2 — Metal Toolchain not installed

With signing disabled, the build fails at the first shader:

```
cannot execute tool 'metal' due to missing Metal Toolchain
```

(long form: "The Metal Toolchain was not installed and could not compile the
Metal source files", failing on `CompileMetalFile Sources/FramerCore/Effects/Metal/CRT.metal`).

Diagnose (re-verified live 2026-07-09):

```bash
xcodebuild -showComponent metalToolchain
# Status: uninstalled   ← the problem
```

Fix, per Apple's own error text (network download, several GB):

```bash
xcodebuild -downloadComponent MetalToolchain
```

Remember: `swift build` succeeding does NOT mean this component exists — the
SPM tier never invokes the offline Metal compiler.

### Blocker 3 — iOS platform missing (FramerMobile only)

The CLAUDE.md-documented iOS command
`xcodebuild build -scheme FramerMobile -destination 'generic/platform=iOS Simulator'`
fails with:

```
iOS 26.5 is not installed
CoreSimulator is out of date. Current version (1051.50.0) is older than build version (1051.55.0)
```

Fix: download the iOS platform in Xcode → Settings → Components; the
CoreSimulator mismatch typically clears after relaunching Xcode (possibly a
reboot). Unresolved on this machine as of 2026-07-09.

---

## Gotchas that are not build failures (yet)

### Module naming: the app module is `Framer`, not `FramerApp`

Sources live in `Sources/FramerApp/`, but the XcodeGen target — and therefore
the Swift module — is named `Framer` (`project.yml:20`). Tests use:

```swift
@testable import Framer   // correct
@testable import FramerApp // does not exist — will not compile
```

### FramerAppTests must share signing identity with the app

`project.yml` gives FramerAppTests the same `DEVELOPMENT_TEAM: QLW5M4WG7H` and
`CODE_SIGN_STYLE: Automatic` as the Framer app target (`project.yml:64-66`).
This is load-bearing: with a Team ID mismatch the test bundle **builds fine
but macOS refuses to load it into Framer.app** at test-run time. Recorded the
hard way in `.sisyphus/notepads/sidebar-harmony/learnings.md` ("Task 1 harness
gotcha"). If you edit test-target settings, keep these two keys in lockstep
with the app target.

### Package.resolved drift (two lockfiles)

There are two dependency lockfiles and they already disagree
(as of 2026-07-09):

| File | swift-argument-parser |
|---|---|
| `Package.resolved` (root, used by `swift build`) | 1.7.0 |
| `Framer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (used by Xcode) | 1.7.1 |

Low severity today (both satisfy `from: "1.3.0"`), but it means the CLI and
the app can link different dependency versions. If you see a dependency-flavored
discrepancy between `swift` and Xcode builds, check these two files first.

### Snapshot tests are machine-sensitive

FramerAppTests snapshot tests compare SHA-256 hashes of rendered PNGs inlined
in test source — no golden image files. They are known-fragile across machines
and macOS versions (font rasterization, GPU compositing). **Never blind-refresh
a hash** — read the pixels and explain the shift first. Full discipline and
update workflow: framer-validation-and-qa.

---

## Stale-artifact map (things in the tree that will mislead you)

| Artifact | What it is | Action |
|---|---|---|
| `./framer` (repo root, 14 MB Mach-O) | The **old v1.x Go-era CLI** (running it yields Go `flag` package errors). Gitignored (`.gitignore` line `framer`), untracked. | Ignore it. The real CLI is `swift run framer ...` — see framer-run-and-operate. |
| `Binary/Framer 2026-04-10 .../Framer.app` | One-off exported app from April, untracked (matched by `Framer.app/` ignore rule). | Ignore; not a release channel. |
| `build/` | Old xcodebuild output, gitignored. | Safe to delete. |
| `Framer-iOS/` | Empty legacy directory (only a `.DS_Store`); the legacy iOS companion app was removed in 2.0.0 (`CHANGELOG.md:81`). Git tracks nothing under it. | Ignore; FramerMobile in `Sources/FramerMobile/` is the live iOS target. |
| `.claude/settings.json` allowlist | npm-flavored legacy (`npm run typecheck/lint/test/build`) — inapplicable to this Swift repo. | Don't take it as guidance. `settings.local.json` has the real swift/xcodegen entries. |
| `.ai-assistant/`, `.ai-project/` references | Dead directories referenced by CLAUDE.md and 21 `.claude/commands/*.md` files. | Dead ends — see framer-docs-and-writing. |

---

## Quick triage: "my build/test is failing"

| Symptom | Cause | Fix |
|---|---|---|
| Overlay textures blank/garbage; texture files are 132 bytes | LFS not hydrated | `git lfs install && git lfs pull` |
| `xcodebuild` can't find a file you just added / new tests not discovered | Committed pbxproj is a stale snapshot | `xcodegen generate` (then `xcodebuild clean test` if discovery is still stale) |
| `Signing certificate ... is not valid for code signing` | Revoked dev cert (`CSSMERR_TP_CERT_REVOKED`) | Renew cert (framer-campaign-restore-validation P1), or `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-` to unblock locally |
| `cannot execute tool 'metal' due to missing Metal Toolchain` | Xcode 26 ships it as a separate component | `xcodebuild -downloadComponent MetalToolchain` |
| `iOS 26.5 is not installed` / CoreSimulator out of date | iOS platform not downloaded | Xcode → Settings → Components; relaunch Xcode |
| Test bundle builds but won't load into Framer.app | Team ID mismatch on FramerAppTests | Restore `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE` parity in `project.yml` |
| `@testable import FramerApp` won't compile | Module is named `Framer` | `@testable import Framer` |
| `./framer` prints Go flag errors | That's the dead v1 Go binary | Use `swift run framer ...` |
| `swift test` green but app broken | Tier 1 ≠ tier 2 | Run the xcodebuild tier (once unblocked) |
| Unexplained 1–2-line pbxproj diff after `xcodegen generate` | Tool-version cosmetic churn | Normal; commit it with your change |

---

## Provenance and maintenance

Everything above verified 2026-07-09 against commit `48d85a5` on the
maintainer's arm64 Mac (Xcode 26.6 / Swift 6.3.3), except: the three xcodebuild
error strings (Blockers 1–3) were captured on 2026-07-09 but not re-run for
this document (full xcodebuild is expensive and known-broken); the
Metal-Toolchain-uninstalled status WAS re-verified live via `-showComponent`.
The LFS-pointer symptom description comes from CLAUDE.md's setup note and could
not be reproduced on this hydrated checkout.

Re-verification one-liners for every drift-prone fact:

```bash
# Toolchain versions
swift --version && xcodebuild -version && xcodegen --version && git lfs version

# Test count and pass state (was: 268 tests, 0 failures, ~3.9s)
swift test 2>&1 | grep -E 'Executed [0-9]+ tests' | tail -1

# Clean-build timing claim (~15s): use a fresh scratch path
swift build --scratch-path /tmp/framer-clean-build 2>&1 | tail -1

# LFS scope (was: 168 files, 338M, all under assets/textures/)
git lfs ls-files | wc -l && du -sh assets/textures && cat .gitattributes

# ASCII atlases still real PNGs outside LFS (was: 80x8 RGBA)
file Sources/FramerCore/Resources/textures/*.png

# Metal Toolchain status (was: Status: uninstalled)
xcodebuild -showComponent metalToolchain

# Runtime-vs-offline .metal strategy still in place
grep -n 'makeLibrary(source:\|makeDefaultLibrary' Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift

# Module name + signing parity (was: Framer target, team QLW5M4WG7H on both)
grep -n 'DEVELOPMENT_TEAM\|CODE_SIGN_STYLE\|minimumXcodeGenVersion\|xcodeVersion' project.yml
grep -rn '@testable import' Tests/FramerAppTests/ | head -3

# Package.resolved drift (was: 1.7.0 vs 1.7.1 for swift-argument-parser)
grep -A5 'argument-parser' Package.resolved Framer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | grep '"version"'

# Stale artifacts still present / still ignored
ls -la framer Binary build Framer-iOS 2>/dev/null; grep -n 'framer\|^build/\|Framer.app' .gitignore

# Dead docs chain (was: dirs missing, 21 command files referencing them)
ls .ai-assistant .ai-project 2>&1; grep -l 'ai-assistant' .claude/commands/*.md | wc -l

# CI still absent
ls .github 2>&1
```
