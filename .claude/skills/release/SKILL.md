---
name: release
description: Framer release ceremony: prepare metadata on develop, validate, merge develop to main with explicit maintainer authorization, tag, verify the CLI package, and publish GitHub release notes and checksums.
---

# framer release ceremony

Updated 2026-09-05 for the maintained `develop` → `main` release flow.
The old main-only branch model is superseded.

## Authorization and branch flow

```
develop → release/vX.Y.Z → preparation PR to develop
        → release PR from develop to main → tag vX.Y.Z → GitHub release
```

A maintainer's explicit instruction to release `develop` into `main` authorizes
these required merges, tagging, and publication. Without that instruction,
prepare the release PR and stop before merging/publishing. Do not force-push,
retag an existing release, or bypass required checks. Prefer merge commits so
branch ancestry and the release decision record remain intact.

For explicitly commissioned releases only, this authorization rule is the scoped
exception to the general no-autonomous-main-merge guidance in `CLAUDE.md` and
`framer-change-control`. Ordinary coding tasks do not gain release authorization.

Complete the changelog, notes, artifacts, and verification before the merge.
Put the exact intended GitHub notes in the release PR body and keep them in
`docs/release-notes/vX.Y.Z.md` so the result is reviewable before publication.

## Version locations

Update all of these together:

- `CHANGELOG.md`: an empty `[Unreleased]` section followed by `[X.Y.Z] - date`.
- `project.yml`: both macOS and iOS `MARKETING_VERSION` values.
- `Sources/FramerCLI/Framer.swift`: `CommandConfiguration.version`.
- Regenerate and commit `Framer.xcodeproj/project.pbxproj` with `xcodegen generate`.
- Refresh README release highlights/install filenames and the saved release notes.

Choose the version from the actual changes since the last tag: features usually
mean a minor release, fixes/docs a patch, and incompatible contracts a major.
State the proposed version early and honor a maintainer-specified number.

## Preflight and preparation

1. Fetch origin; inspect `origin/develop`, `origin/main`, open PRs, tags, and
   published releases. Do not infer scope from the current worktree alone.
2. Identify anything intended for the release that is not yet on develop.
3. Create `release/vX.Y.Z` from current `origin/develop`. Preserve unrelated
   working-tree files; use an isolated worktree if necessary.
4. Draft a human-readable changelog from landed behavior, including CLI behavior
   changes and install limitations. Do not copy raw commit subjects as notes.
5. Bump versions, regenerate the project, prepare release notes, and review the diff.

## Validation gate

The local Mac gate is authoritative. Record exact executed/failed/skipped counts:

- `swift build` and `swift test`; expect zero skips on the development Mac.
- `swift run framer --version` must equal the proposed version.
- Run both applicable Xcode app test targets for releases containing app changes.
  Local unsigned validation uses `CODE_SIGNING_ALLOWED=NO`; it does not prove
  distribution signing. Never blind-refresh UI or effect baselines.
- Build the optimized CLI and verify the extracted distribution package with a
  real shader/ASCII render, not only `--version`.
- Check CI and obtain an independent review of consequential release changes.

## Artifact contract

The macOS arm64 CLI archive must include BOTH `framer` and
`framer_FramerCore.bundle` beside it. SwiftPM resources are not embedded in the
executable. The generated accessor also has an absolute build-path fallback,
so a smoke test must make that fallback unavailable to prove relocation works.

Publish the tarball and `SHA256SUMS`. Verify checksums and archive contents;
keep the executable and bundle together when documenting installation.
Overlay textures remain source/LFS assets and are not part of this CLI package.

Use the same helper locally and in CI:

```bash
tools/release/package-cli.sh vX.Y.Z /tmp/framer-release-build /tmp/framer-release-artifacts
```

`.github/workflows/release.yml` runs on version-tag pushes and builds/uploads
the package. It creates a draft release if needed. Watch every release run and
inspect the actual uploaded assets; use the same packaging/verification helpers
locally if the runner fails. Never label an unverified archive as ready.

App distributions require separately verified signing/notarization. As checked
2026-09-05, this Mac has no valid signing identity; the established distribution
is the unsigned CLI plus source builds of the apps.

## Merge, tag, and publish

1. Push the preparation branch, open its PR to develop, and wait for checks.
2. With the maintainer's release authorization, merge that reviewed PR using
   an exact head-commit match. Create the release PR from develop to main with
   the changelog and saved release notes in its body.
3. Wait for release PR checks, verify the intended head, and merge. Do not use
   admin bypasses. Use the user's Lore commit-message protocol for new commits
   and merge messages.
4. Fetch and fast-forward local main. Verify its source tree matches the tested
   release tree and the CLI/app versions before creating the annotated tag.
5. Push `vX.Y.Z`, watch the release-artifact workflow, download its archive and
   checksums, and verify the published candidate independently of the build tree.
6. Publish the draft with the saved notes, title, and latest-release flag. Confirm
   the tag commit, publication state, asset names/digests, and printed CLI version.
7. Fast-forward develop to the release merge when possible. If develop advanced
   meanwhile, use a reviewed merge-back PR; never overwrite newer development.

## Provenance

The original ceremony shipped v2.0.0 in July 2026. The September 2026 release
commission explicitly uses develop → main and authorizes release merges. Branch
state, signing identities, test counts, and workflow behavior must be rechecked
for each release rather than inferred from old incident notes.
