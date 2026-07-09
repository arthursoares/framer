# AI Assistant Instructions

**Source of truth for process and project knowledge: the skill library in [.claude/skills/](.claude/skills/).**

Skills load automatically by description. When in doubt about *how to work here*, start with `framer-change-control`; when in doubt about *what you're looking at*, start with `framer-architecture-contract`.

(Rewritten 2026-07-09. This file previously pointed at `.ai-assistant/` / `.ai-project/` — directories that never existed in git.)

## Project Overview

**framer** — Swift photo post-processing: frames, borders, EXIF captions, texture overlays, dithering, LUTs, and GPU effects. macOS app + CLI, iOS app in progress.

| Aspect | Value |
|--------|-------|
| Targets | FramerCore (library), FramerCLI (`framer` executable), FramerApp (macOS SwiftUI — module name is `Framer`), FramerMobile (iOS SwiftUI) |
| Platforms | macOS 14+, iOS 17+ |
| Build | Swift Package Manager + XcodeGen (`project.yml` → committed `Framer.xcodeproj`) |
| Test framework | XCTest, two tiers (SPM + Xcode) |
| Large assets | Texture overlays in `assets/textures/` via Git LFS |

## Setup

```bash
git lfs install && git lfs pull   # without this, overlays are 132-byte pointer files and render as garbage
swift build && swift test         # tier-1 gate; expect all tests green in seconds
xcodegen generate                 # regenerate Framer.xcodeproj — REQUIRED after adding any file under Sources/FramerApp/ or Tests/FramerAppTests/
```

## Quick Commands

| Task | Command |
|------|---------|
| Build | `swift build` |
| Test (tier 1: FramerCore + FramerCLI) | `swift test` |
| App tests (tier 2: FramerAppTests) | `xcodegen generate && xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'` — see `framer-campaign-restore-validation` for current blockers |
| Effect golden-reference check | `swift test --filter EffectGPUGoldenTests` (regeneration is env-gated — see the file header; never blind-refresh) |
| Run CLI | `swift run framer --help` |
| Environment health | `.claude/skills/framer-diagnostics-and-proof/scripts/env-doctor.sh` |

## House Rules

Details, rationale, and the incidents behind each: `framer-change-control` skill.

1. **No autonomous merges or pushes to main.** AI sessions branch, commit, and open PRs when asked; a human decides every merge.
2. **Never blind-refresh snapshot SHA-256 hashes.** Read the rendered pixels and explain the shift; land the refresh in the same commit as its cause.
3. **Schema/preset changes must keep legacy decoding.** `PresetStore` deletes undecodable preset files — a decode regression silently destroys user data.
4. **Shader changes keep `EffectGPUGoldenTests` green.** The CPU effect path was retired 2026-07-09 (docs/adr/2026-07-09-retire-cpu-effect-path.md); a deliberate look change regenerates the golden PNGs in the same commit with an explanation of the pixel shift — same discipline as rule 2. Riemersma dither and the hidden legacy bucket variants stay CPU by design.
5. **Conventional commits with scopes**: `fix(sidebar): …`, `feat(gpu-effects): …`, one task per commit, buildable at every commit.

## Skill Library Map

- **Process & gates** — framer-change-control · framer-validation-and-qa · framer-docs-and-writing
- **Understanding the system** — framer-architecture-contract · framer-metal-pipeline-reference · framer-image-processing-reference · framer-config-and-flags
- **Doing the work** — framer-build-and-env · framer-run-and-operate · framer-ui-design-system · framer-debugging-playbook · framer-diagnostics-and-proof
- **History & direction** — framer-failure-archaeology · framer-campaign-restore-validation · framer-campaign-gpu-effects-quality · framer-research-frontier

## Design Briefs

- [assets/design/DESIGN_BRIEFING.md](assets/design/DESIGN_BRIEFING.md) — macOS "Darkroom Editorial" (inspector width is now governed by `SidebarLayoutPolicy`, not the briefing's 280pt — see `framer-ui-design-system`)
- [assets/design/ios/IOS_DESIGN_BRIEFING.md](assets/design/ios/IOS_DESIGN_BRIEFING.md) — iOS
