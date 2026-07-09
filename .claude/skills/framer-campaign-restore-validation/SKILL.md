---
name: framer-campaign-restore-validation
description: >
  EXECUTABLE campaign to repair framer's broken second test tier (xcodebuild-only
  FramerAppTests, currently blocked by a revoked Apple Development signing certificate
  and a missing Xcode Metal Toolchain component) and to revive the abandoned E2E test
  scaffolding (salvage/e2e-test-scaffolding branch, dead PR #6). Load this when you see
  "Signing certificate ... is not valid for code signing", "cannot execute tool metal" /
  "Metal Toolchain was not installed", xcodebuild test failures on the Framer scheme,
  mass snapshot-hash failures, or any request to run/restore FramerAppTests or to
  add/revive E2E, UI, or CLI end-to-end tests.
---

# Campaign: restore the app-test tier and revive E2E

This is an **executable, decision-gated campaign**, not a reference. Work the phases in order. Every gate states what you should observe and what to do if you observe something else. Several gates require the human maintainer (GUI actions, network installs, merge decisions) — those are marked **USER-ACTION** or **DECISION**. Per house rule (owned by `framer-change-control`): **no autonomous merges or pushes** — every behavior-changing phase ends in a locally-committed branch and, when asked, a PR; a human merges.

## Status board (as of 2026-07-09, commit 48d85a5)

| Tier | What | Command | Status |
|---|---|---|---|
| 1 | 268 SPM tests (FramerCoreTests + FramerCLITests) | `swift test` | **GREEN** — 0 failures, ~4 s |
| 2 | 63 test methods / 12 files in `Tests/FramerAppTests` (incl. all SwiftUI snapshot tests) | `xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'` | **BROKEN** — two independent blockers (P1: revoked signing cert; P2: missing Metal Toolchain) |
| 3 | E2E (CLI process-spawn tests, macOS/iOS UI tests) | none | **DOES NOT EXIST on main** — scaffolding parked on `origin/salvage/e2e-test-scaffolding` (aa60b94); full original attempt preserved on `origin/pr6-check` (PR #6, CLOSED unmerged) |

Update this table when a phase lands.

## Glossary (first use)

- **Tier 1 / tier 2**: this repo's test estate is split. `Package.swift` declares only `FramerCoreTests` and `FramerCLITests` (tier 1, runs via `swift test`). `Tests/FramerAppTests` is declared only in `project.yml` (the XcodeGen spec) and runs only through the generated `Framer.xcodeproj` (tier 2). Tier-1 green says NOTHING about tier 2.
- **XcodeGen**: tool that generates `Framer.xcodeproj` from `project.yml`. The generated project is committed but goes stale; rerun `xcodegen generate` after adding any file under `Sources/FramerApp/` or `Tests/FramerAppTests/`.
- **Metal Toolchain**: since Xcode 26, the offline Metal shader compiler is a separately-downloaded Xcode component. `xcodebuild` needs it to compile `.metal` files; plain `swift build`/`swift test` do not (see P2 for why).
- **Snapshot tests**: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` renders SwiftUI views offscreen and compares the PNG's SHA-256 against hex literals inlined in the test source (10 baseline hashes; no golden image files exist). Single-machine baselines — fragile across machines/OS versions by design. Protocol details owned by `framer-validation-and-qa`.
- **E2E**: end-to-end tests that spawn the real CLI binary (`Process` + `.build/debug/framer`) or launch the real app (XCUITest) and assert on produced files — exit codes, pixel dimensions, EXIF payloads. Numbers, not eyeballs.

## When NOT to use this skill

| You actually want | Go to |
|---|---|
| Tier-1 (`swift test`) failures, any functional bug triage | `framer-debugging-playbook` |
| Snapshot-hash discipline, test-writing conventions, what counts as evidence | `framer-validation-and-qa` |
| Setting up the machine from scratch, toolchain versions, LFS | `framer-build-and-env` |
| Running the CLI/app normally | `framer-run-and-operate` |
| Commit/branch/PR conventions used in P5 | `framer-change-control` |
| Why the E2E attempts died (full PR #6 story) | `framer-failure-archaeology` |
| Metal shader mechanics | `framer-metal-pipeline-reference` |

## Campaign map

| Phase | Goal | Gate type | Depends on |
|---|---|---|---|
| P0 | Confirm tier 1 is green | Automated | — |
| P1 | Valid code-signing identity | **USER-ACTION** (Xcode GUI / Keychain) | P0 |
| P2 | Metal Toolchain installed | **USER-ACTION** (network download) | P0 (independent of P1) |
| P3 | Tier 2 green: 63 tests pass via xcodebuild | Automated + baseline-policy **DECISION** | P1 + P2 |
| P4 | E2E revived (CLI first, UI second, iOS deferred) | **DECISION** first, then automated | P3 (UI part); P0 only (CLI part) |
| P5 | Promotion: PRs, estate-map update | **DECISION** (human merges) | each phase |

---

## P0 — Baseline gate: tier 1 must be green

This campaign assumes tier 1 works. Verify before touching anything:

```bash
cd /path/to/framer
swift test 2>&1 | grep -E "Executed .* tests"
```

**Expect** (verified 2026-07-09, commit 48d85a5, Xcode 26.6 / Swift 6.3.3, Apple-silicon Mac):

```
Executed 268 tests, with 0 failures (0 unexpected) in 3.676 (3.691) seconds
```

The test count drifts as tests are added — record the actual number you see; what matters is `0 failures`. Wall clock is ~9 s warm. The tail of the raw output also shows a Swift Testing pass of "`0 tests in 0 suites`" — that is normal; everything in this repo is XCTest.

**If you see failures instead** → STOP. This campaign is the wrong tool; branch to `framer-debugging-playbook` and fix tier 1 first.

**If you see skips** (`XCTSkip`) → you are on a machine without a Metal device or without LFS-hydrated fixtures; 25 of the 27 `EffectGPUParityTests` self-skip (2 fallback-routing tests still run without Metal — skip arithmetic is owned by `framer-validation-and-qa`). The campaign's later phases require a real Mac with a GPU, so relocate before continuing (see `framer-build-and-env`).

---

## P1 — Signing repair (USER-ACTION gate)

### Current failure (verified 2026-07-09)

Running tier 2 today fails before compiling anything:

```
Signing certificate "Apple Development: arthur@arthursoares.com.br (P7K6Z5BCV4)"
... is not valid for code signing. It may have been revoked or expired.
```

(reported for both the `Framer` and `FramerAppTests` targets). Confirm the cert state cheaply without a build:

```bash
security find-identity -v -p codesigning
```

**Expect today**: the P7K6Z5BCV4 identity annotated `(CSSMERR_TP_CERT_REVOKED)` — the certificate is **revoked**, not merely expired, so waiting won't help.

### Constraint you must respect

`.sisyphus/notepads/sidebar-harmony/learnings.md` (line 20, a repo-committed engineering diary) records a hard-won lesson: **`FramerAppTests` must carry the same `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE` as the `Framer` app target**, or `xcodebuild test` builds the bundle but macOS refuses to load it into `Framer.app` (Team ID mismatch). Today both targets set `DEVELOPMENT_TEAM: QLW5M4WG7H` / `CODE_SIGN_STYLE: Automatic` (`project.yml:38-39` and `project.yml:65-66`). Whatever remediation you pick, keep the two targets identical.

### Options, ranked

1. **Renew the certificate (preferred; GUI, human only).** Xcode → Settings → Accounts → select the Apple ID owning team QLW5M4WG7H → Manage Certificates → "+" → Apple Development. Optionally delete the revoked cert in Keychain Access afterwards. No repo change needed.
2. **Switch teams.** If QLW5M4WG7H is dead, edit `project.yml` `DEVELOPMENT_TEAM` in **both** places (lines 38 and 65 as of 48d85a5), run `xcodegen generate`, and treat it as a behavior-affecting config change: branch + PR per `framer-change-control`.

### Gate

```bash
security find-identity -v -p codesigning
```

**Expect**: at least one Apple Development identity with **no** parenthesized error annotation. If still `CSSMERR_TP_CERT_REVOKED` → the renewal didn't take (wrong Apple ID / keychain); retry option 1 or escalate to option 2.

### FENCED WRONG PATH: permanently disabling signing

`CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-` is useful for exactly one thing: as a **diagnostic** to peek past the signing error and confirm the next blocker (that is how the P2 error below was surfaced). It is not a fix:

- The app target sets `ENABLE_HARDENED_RUNTIME: YES` (`project.yml:48`) and sandbox entitlements — an unsigned host app breaks the test-bundle loading contract that learnings.md:20 documents.
- It does not fix P2; the build still dies on the Metal compile.
- It normalizes shipping an unsigned app, which nobody decided.

Do not commit any signing-disabling settings.

---

## P2 — Install the Metal Toolchain (USER-ACTION gate: network download)

### Current failure (verified 2026-07-09)

With signing bypassed diagnostically, `xcodebuild` fails at the first shader:

```
error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
```

Check status without building:

```bash
xcodebuild -showComponent metalToolchain
```

**Expect today**: `Build Version: 17F109` / `Status: uninstalled`.

### Fix (network install — human should approve; multi-GB download)

```bash
xcodebuild -downloadComponent MetalToolchain
```

(Flag verified against `xcodebuild -help` on Xcode 26.6: "Supported component: MetalToolchain".)

### Gate

```bash
xcodebuild -showComponent metalToolchain
```

**Expect**: `Status:` no longer `uninstalled` (exact success wording unverified here — the component could not be installed on the authoring machine; record what you see).

### Why `swift test` never needed this (so you don't "fix" the wrong tier)

`Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift:54-120` documents and implements the split:

- **Under `swift build` / `swift test`** SwiftPM 5.10 treats `.metal` files as opaque resources and copies them as text into `Bundle.module`; `MetalEffectLibrary` then **compiles shaders at runtime** via `device.makeLibrary(source:)` (concatenating `ShaderCommon.h` + all `.metal` sources). No offline Metal compiler involved → tier 1 passes on a machine with no Metal Toolchain.
- **Under `xcodebuild`** the same `.process(...)` rules invoke the offline Metal compiler to produce `default.metallib` → requires the Toolchain component.

So a green `swift test` is genuinely deceptive here: the environment can be broken for every Xcode-built target while tier 1 stays perfect. (Deep Metal mechanics: `framer-metal-pipeline-reference`.)

---

## P3 — App-test tier green

Preconditions: P1 gate passed, P2 gate passed.

```bash
xcodegen generate
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
```

**Expect**: `Framer` and `FramerAppTests` build; 63 test methods across the 12 files in `Tests/FramerAppTests/` run; output ends `** TEST SUCCEEDED **`. (63/12 verified 2026-07-09 by `grep -c 'func test' Tests/FramerAppTests/*.swift`; count drifts — record actual.)

Targeted runs (the de facto convention throughout `docs/superpowers/plans/`):

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
  -only-testing:FramerAppTests/SidebarMetricsTests
```

Operational notes:

- `xcodegen generate` rewrites `Framer.xcodeproj/project.pbxproj`; newer XcodeGen/Xcode versions emit boilerplate churn (e.g. dropping `compatibilityVersion`, adding `productRefGroup`). Commit the regenerated pbxproj with your change, not as drive-by noise.
- Tests missing / stale discovery after adding files → `xcodegen generate` then `xcodebuild clean test ...` (learnings.md:41, 51, 107 — three separate recurrences).

### BRANCH: mass snapshot failures

If many/all of the 10 `SidebarHarmonySnapshotTests` baselines fail at once on a new machine or after a macOS update, that is **EXPECTED**, not a regression: the SHA-256 hashes are single-machine baselines sensitive to font rasterisation and GPU compositing (learnings.md:100). Apply the read-the-pixels protocol (house rule, owned by `framer-validation-and-qa`):

1. **Never blind-refresh a hash.** For each failure, render/inspect the actual pixels and explain the shift. The failure message prints `Snapshot <name> changed. Actual SHA256: <hex>` (`Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`, `assertSnapshot` at lines 270-307) — the hash alone tells you nothing; the harness writes no PNGs, so temporarily dump the bitmap to disk in the harness (do not commit that) or re-render the surface to eyeball it.
2. If renders are visually correct and the shift is purely environmental → STOP at the **DECISION gate below first**: per the house rule in `framer-validation-and-qa`, do **not** refresh hashes from a second machine without a maintainer decision. With the ruling in hand, re-baseline **all** shifted hashes in **one dedicated commit** whose message names the machine + macOS version (e.g. "re-baseline snapshots: M4 Pro, macOS 26.x"); the commit stays on an unmerged branch until it lands as P5 PR B (whose precondition is that the policy decision is recorded).
3. If a hash shifted because of a code change → the refresh lands in the **same commit** as the change, 1-4 hashes per commit for bisectability (learnings.md:64).

### GATE (DECISION): record the standing baseline policy

The single-machine-baseline question is an **open maintainer question**: which machine+OS is canonical, and what happens on the next OS update? Get a ruling **before** any environmental re-baseline (step 2 above) and before closing P3. This campaign drives the decision; the resulting rule is recorded in `framer-validation-and-qa` (the owner of snapshot-hash mechanics). Do not invent a policy silently.

---

## P4 — E2E revival

### DECISION GATE first

Confirm with the maintainer that E2E revival is wanted **now** (it has died twice; see `framer-failure-archaeology` for the PR #6 saga). Do not start this phase on your own initiative.

### Source of truth — do NOT rewrite from scratch (fenced wrong path)

The design already exists and was partially proven. Read it; don't re-derive it:

```bash
git show origin/salvage/e2e-test-scaffolding --stat          # aa60b94, 11 files, +265 lines
git show origin/salvage/e2e-test-scaffolding:Tests/FramerCLIE2ETests/E2ETestSupport.swift
git log --oneline origin/main..origin/pr6-check              # the full original 8 commits of PR #6
```

What the salvage commit (aa60b94, 2026-04-17) **contains** (verified by reading the branch):

| Piece | Content |
|---|---|
| `Tests/FramerCLIE2ETests/` | 3 XCTest methods that `Process`-spawn the CLI and assert exit status 0, output filename/existence, pixel dimensions vs a JSON manifest (via ImageIO `CGImageSourceCopyPropertiesAtIndex`), and EXIF `DateTimeOriginal` removal after `--no-metadata` |
| `Tests/E2EFixtures/` | `input/sample-1.jpg` (3240x2227), `input/sample-2.jpg`, `manifests/single-export.json` (expects 3580x2567 jpeg), `manifests/batch-export.json` |
| `Sources/Framer{App,Mobile}/App/E2ETestConfiguration.swift` | env-var contract: activates when `FRAMER_E2E_MODE=1`, reads `FRAMER_E2E_FIXTURE_DIR`, `FRAMER_E2E_EXPORT_DIR`, optional `FRAMER_E2E_PRESET_NAME` |
| `Tests/FramerAppUITests/`, `Tests/FramerMobileUITests/` | XCUITest stubs that launch the app with those env vars and assert an exported file appears |

What is **MISSING** — and is the actual work (the commit message says so verbatim): zero `Package.swift` / `project.yml` target wiring, none of the app-side hooks (AppState, ExportBar, PresetPreviewCard, LayerDetailView) that `E2ETestConfiguration` drives, no UI-test scheme entries. "Compiles but the new test code is not runnable until the wiring is restored."

The wiring **reference** is on `origin/pr6-check` (PR #6's original commits). Its diff shows exactly what to reapply:

- `Package.swift`: `.testTarget(name: "FramerCLIE2ETests", dependencies: ["FramerCore"], resources: [.copy("../E2EFixtures")])` — note the `../` resource path; re-check current SwiftPM accepts it, else move the fixtures under the test target.
- `project.yml`: `FramerUITests` (macOS `bundle.ui-testing`) + `FramerMobileUITests` (iOS) targets, wired into the `Framer` / `FramerMobile` scheme test actions.

### P4.1 — CLI E2E first (low risk; needs only P0, not P1/P2)

This slice ran green in PR #6 ("CLI E2E tests execute successfully in-package", 225 tests at the time) and is pure SPM — no signing, no Metal Toolchain.

1. Branch. Cherry-pick or copy `Tests/FramerCLIE2ETests/` + `Tests/E2EFixtures/` from `origin/salvage/e2e-test-scaffolding`.
2. Add the `Package.swift` test target per the pr6-check diff above.
3. Known assumption to note in code review: `E2ETestSupport.builtCLI` hardcodes `.build/debug/framer` (repo root located via `#filePath`). Plain `swift test` builds the whole package so the debug binary exists, but `swift test -c release` will not find it. Acceptable for now; document it in the test file header.
4. Run: `swift build && swift test --filter FramerCLIE2ETests`.

**Expect**: 3 tests pass — `test_process_singleImage_writesExpectedJPEG`, `test_process_directory_writesExpectedBatchOutputs`, `test_process_singleImage_noMetadataRemovesExifPayload`.

**Fixtures are still valid** (verified 2026-07-09 at 48d85a5): the current CLI, given the branch's `sample-1.jpg` with `process --input ... --output-file ... --border-style solid`, produced exactly the manifest's 3580x2567 — and every flag the tests use (`--input`, `--output-file`, `--border-style`, `--workers`, `--no-metadata`) still exists in `Sources/FramerCLI/Commands/ProcessCommand.swift:11-35`. **If dimensions mismatch instead** → the CLI's default border math changed since April 2026; investigate the render change first (`framer-debugging-playbook`), and only update the manifest with the explanation in the commit message — same discipline as snapshot hashes.

**Success metric** for the whole of P4: `FramerCLIE2ETests` runs N tests asserting exit status, dimensions, and EXIF stripping — numbers, not eyeballs.

### P4.2 — macOS UI E2E second (needs P1 + P3 green)

Reapply, against today's code, the app-side hooks from `origin/pr6-check` commits `bdee309` ("macOS e2e launch bootstrap") and `8b1454e` ("macOS export controls e2e-friendly"), plus the `FramerUITests` target/scheme wiring. Expect drift: main has moved ~10+ commits of app refactoring since; the hooks are a design spec, not a clean cherry-pick.

**Known blocker to expect** (verbatim from the CLOSED PR #6 body): the macOS UI test runner was blocked by `Authentication canceled. System authentication is running.` This is signing/automation-permission-related and *should* be resolved by P1 plus granting Xcode Helper automation permission in System Settings → Privacy & Security — **unverified**; if it persists after P1, record findings in `framer-failure-archaeology` and gate on maintainer input rather than fighting it silently.

### P4.3 — iOS UI E2E: DEFER

Separate blocker class, unrelated to P1/P2: PR #6 hit simulator preflight/launch failures for `FramerMobileUITests.xctrunner`, and as of 2026-07-09 this machine has only the iOS 26.4 simulator runtime while Xcode 26.6 asks for 26.5 (plus CoreSimulator version-mismatch churn). Park iOS E2E as an explicit non-goal of this campaign; note it in the P5 PR description.

---

## P5 — Promotion through change control

One PR per phase-cluster, each independently green and revertible:

| PR | Contents | Merge precondition |
|---|---|---|
| A (only if P1 option 2) | `project.yml` team change + regenerated pbxproj | P1 gate output pasted in PR body |
| B (if P3 re-baselined) | one dedicated snapshot re-baseline commit, machine+OS named | pixels reviewed, policy decision recorded |
| C | P4.1 CLI E2E target + tests + fixtures | `swift test --filter FramerCLIE2ETests` output in PR body |
| D | P4.2 UI-test wiring + app hooks | full tier-2 run output in PR body |

Conventions (commit style, branch naming, PR template): `framer-change-control`. After each merge, update (1) the estate map in `framer-validation-and-qa`, (2) the **Status board** at the top of this skill. **A human merges every PR** — never merge or push to main yourself.

## Solution menu, ranked (with obligations)

| Rank | Move | Obligation |
|---|---|---|
| 1 | Renew cert in Xcode GUI (P1 opt 1) | none in-repo; paste `security find-identity` output as evidence |
| 2 | `xcodebuild -downloadComponent MetalToolchain` (P2) | human approves network install; re-run `-showComponent` gate |
| 3 | Switch `DEVELOPMENT_TEAM` (P1 opt 2) | change BOTH targets (learnings.md:20); PR |
| 4 | Re-baseline snapshots on new machine (P3 branch) | read pixels first; one dedicated commit naming machine+OS; record policy |
| 5 | Revive CLI E2E from salvage branch (P4.1) | DECISION gate first; keep manifest assertions; note `.build/debug` assumption |
| 6 | Revive macOS UI E2E (P4.2) | P1+P3 green first; expect "Authentication canceled"; escalate if it persists |

## FENCED WRONG PATHS (do none of these)

- **Permanently disabling code signing** — diagnostic only; hardened-runtime app, breaks bundle loading, doesn't fix P2 (see P1 fence).
- **Deleting or `XCTSkip`-ing snapshot tests because they fail cross-machine** — they "caught EVERY layout drift" locally (learnings.md:100); the fix is the baseline protocol + a recorded policy, not deletion.
- **Blind-refreshing snapshot hashes** — house rule; read the pixels, explain the shift, refresh in the causing commit.
- **Rewriting E2E from scratch** — the env-var contract, manifests, and assertions already exist on `origin/salvage/e2e-test-scaffolding` and the wiring on `origin/pr6-check`; re-deriving them re-loses two rounds of prior work.
- **Treating tier-1 green as app-tier evidence** — `swift test` compiles zero FramerAppTests code and no offline Metal; only the P3 command validates tier 2.
- **Merging or pushing anything to main yourself** — human-merge house rule, no exceptions.

## Provenance and maintenance

All facts verified 2026-07-09 on main @ 48d85a5, Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen 2.45.4, Apple-silicon Mac, unless marked unverified. The two failure strings in P1/P2 were observed by running `xcodebuild test` on that date; the cert state and toolchain state were independently re-confirmed with the cheap commands below. The P2 "Status: installed" success wording and the P4.2 "Authentication canceled is fixed by P1" hypothesis are **unverified**.

Re-verification one-liners:

```bash
swift test 2>&1 | grep -E "Executed .* tests"                      # tier-1 count + green
security find-identity -v -p codesigning                            # cert still revoked?
xcodebuild -showComponent metalToolchain                            # toolchain still uninstalled?
grep -c 'func test' Tests/FramerAppTests/*.swift                    # tier-2 method count (63)
ls Tests/FramerAppTests/ | wc -l                                    # tier-2 file count (12)
grep -c 'expectedSHA256: "' Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift   # baseline hash count (10)
grep -n 'DEVELOPMENT_TEAM' project.yml                              # both targets same team (lines 38, 65, 88)
git log --oneline -1 origin/salvage/e2e-test-scaffolding            # still aa60b94?
git rev-list --count origin/main..origin/pr6-check                  # still 8 commits?
gh pr view 6 --json state -q .state                                 # still CLOSED?
grep -n 'makeLibrary(source' Sources/FramerCore/Effects/GPU/MetalEffectLibrary.swift # runtime-compile fallback intact
grep -n 'output-file\|no-metadata' Sources/FramerCLI/Commands/ProcessCommand.swift   # E2E-used flags still exist
sed -n '20p;64p;100p' .sisyphus/notepads/sidebar-harmony/learnings.md                # cited lessons at cited lines
```
