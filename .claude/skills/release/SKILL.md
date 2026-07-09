---
name: release
description: Project release config and ceremony for framer — load when cutting a release, bumping versions, updating CHANGELOG for a release, tagging, or publishing a GitHub release. Encodes the trunk-based flow (release branch → PR → human merges → tag → gh release), all four version locations, artifact build commands, and the no-CI validation gate. Extends the generic release-manager skill; this file wins on conflicts.
---

# framer — release ceremony

Project extension for the generic `release-manager` skill. Where this file and
the generic skill disagree, **this file wins**. First executed for v2.0.0
(2026-07-09); the ceremony below is that release, generalized.

## Branch model (overrides release-manager defaults)

Trunk-based: `main` is the only long-lived branch — there is **no `develop`**.
Releases cut from `main` via a release branch:

```
main ──► release/vX.Y.Z ──► PR ──► human merges ──► tag vX.Y.Z on main ──► gh release
```

House rule 1 (framer-change-control) applies: the agent never merges the
release PR — the maintainer's merge IS the changelog/notes approval gate.
After the maintainer merges, tagging `main` and publishing the GitHub release
are part of the commissioned ceremony (a tag push is not a commit push).

## Version locations — ALL FOUR move together

| Location | What | Verify |
|---|---|---|
| `CHANGELOG.md` | `## [X.Y.Z] - YYYY-MM-DD` section (Keep a Changelog; keep an empty `## [Unreleased]` above it) | `grep -n '^## \[' CHANGELOG.md` |
| `project.yml` — Framer (macOS) target | `MARKETING_VERSION: "X.Y.Z"` | `grep -n MARKETING_VERSION project.yml` (2 hits, both = X.Y.Z) |
| `project.yml` — FramerMobile (iOS) target | `MARKETING_VERSION: "X.Y.Z"` | same |
| `Sources/FramerCLI/Framer.swift` | `CommandConfiguration(version: "X.Y.Z")` | `swift run framer --version` |

**After editing project.yml, run `xcodegen generate`** and commit the
regenerated `Framer.xcodeproj/project.pbxproj` in the same commit — the
committed pbxproj is a snapshot (framer-build-and-env).

## The ceremony, step by step

1. **Preflight** — `git switch main && git pull`; `gh pr list --state open`
   (surface anything that should land first); `git tag --sort=-v:refname | head -3`
   and `gh release list | head -3` (last release);
   `git rev-list --count <last-tag>..main` (scope).
2. **Version proposal** — semver over the commits/PRs since the last tag:
   breaking behavior (e.g. the v2.0.0 Metal-required change) → major;
   features → minor; fixes/docs only → patch. **The maintainer picks the final
   number** — version questions in this repo have history (v2.0.0 sat untagged
   in the CHANGELOG for five months; see framer-docs-and-writing §3).
3. **Branch** — `git switch -c release/vX.Y.Z main`.
4. **CHANGELOG** — roll `[Unreleased]` into `## [X.Y.Z] - date`; synthesize
   human-quality entries from merged PRs (`gh pr list --state merged`), not raw
   commit subjects; mark breaking changes with **BREAKING**. Backfill any gap
   since the last entry — this file has drifted before.
5. **Bump the other three version locations** (+ `xcodegen generate`).
6. **Validate (no CI — local gate is the only gate)** —
   `swift build && swift test` and quote the executed/failed/skipped counts
   (expect 0 skips on the dev Mac; framer-validation-and-qa);
   `swift run framer --version` must print X.Y.Z; a CLI smoke render
   (framer-run-and-operate) for release sanity.
7. **Release PR** — title `Release vX.Y.Z`; body = the new CHANGELOG section
   + the draft GitHub release notes, so the maintainer reviews both in one
   pass. Conventional commit for the bump:
   `chore(release): vX.Y.Z — changelog, version bumps`.
8. **Maintainer merges.** (Never `gh pr merge` yourself.)
9. **Tag + publish** — on updated main:
   ```bash
   git switch main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```
10. **Artifact** — release-built CLI binary (unsigned; arm64 on the dev Mac):
    ```bash
    swift build -c release
    BIN=.build/release/framer
    "$BIN" --version                       # must print X.Y.Z
    tar -czf framer-vX.Y.Z-macos-arm64.tar.gz -C .build/release framer
    ```
    The macOS **app** is NOT released while the signing cert is revoked
    (framer-campaign-restore-validation P1); revisit when repaired.
11. **GitHub release** —
    ```bash
    gh release create vX.Y.Z framer-vX.Y.Z-macos-arm64.tar.gz \
      --title "vX.Y.Z" --notes-file <notes>
    ```
    Notes = CHANGELOG section + install snippet (`xattr -d
    com.apple.quarantine`, `git lfs pull` for source builds) + full-changelog
    compare link. Publish only notes the maintainer saw in the PR body.
12. **Verify done** — `gh release view vX.Y.Z` shows the asset;
    `git ls-remote --tags origin vX.Y.Z` resolves; CHANGELOG `[Unreleased]`
    is empty and at the top.

## What does NOT apply here (generic-skill deltas)

- No `develop` → no merge-back phase.
- No CI → skip CI monitoring; the local test gate replaces it.
- Release notes strategy: `agent-creates`, reviewed via the PR body (step 7),
  not via a separate approval round-trip.
- Squash-vs-merge: the maintainer merges however they like; true merge commits
  are the house preference (framer-change-control rule 6).

## Provenance and maintenance

Written 2026-07-09 while executing the v2.0.0 release (first Swift-era
release; v1.x releases are Go-era). Re-verify the version-location table with
the commands in it; if a fifth version location appears (e.g. a Homebrew
formula, an appcast), add it to the table in the same PR that introduces it.
