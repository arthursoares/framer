# Framer App - Team Review & Action Plan

> Compiled from 5 specialist agent reviews: Engineering, Design, DevOps, QA, Product Management.
> Date: 2026-03-07

---

## Executive Summary

Framer is a well-architected macOS photo framing app with a clean three-target split, 99 passing tests, and a solid layer-based composition model. The app solves a real problem for photographers (EXIF-based captions + batch framing), but has critical gaps in distribution, error handling, and polish that need addressing before public release.

**The app has a go-to-market problem, not a product problem.** The core processing pipeline works well. The priority should be: harden what exists, polish the UX, set up distribution, then validate demand.

---

## Priority Matrix

### P0 - Critical (Fix Before Any Release)

| # | Issue | Source | Effort |
|---|-------|--------|--------|
| 1 | **App Sandbox entitlements are empty** - blocks notarization and distribution | DevOps | Low |
| 2 | **`try!` in 14+ production initializers** - will crash on invalid hex | Engineer | Low |
| 3 | **`@unchecked Sendable` on PhotoItem** - papers over real data race with `NSImage` | Engineer | Low |
| 4 | **Silent error swallowing** - preset save/delete/export failures invisible to user | Engineer, Designer | Medium |
| 5 | **No last-export-directory memory** - user picks folder every time | Designer | Low |
| 6 | **Export flow has 3 modals in sequence** - too much friction for terminal action | Designer | Medium |

### P1 - Important (Before Public Beta)

| # | Issue | Source | Effort |
|---|-------|--------|--------|
| 7 | **Set up CI/CD** - no automated build/test; GitHub Actions with macOS runner | DevOps | Medium |
| 8 | **Add keyboard shortcuts** - only 3 exist; missing Cmd+A, Delete, Space for before/after | Designer | Low |
| 9 | **Version alignment** - `MARKETING_VERSION` says 1.0.0, HEAD is 53 commits past v1.2.0 | DevOps | Low |
| 10 | **Test coverage gaps** - 0 tests for TextureFrameProvider, AppState export, CaptionRenderer positioning | QA | High |
| 11 | **`deterministicUUID` truncation** - preset names >16 bytes collide silently | Engineer | Low |
| 12 | **Dead code cleanup** - `FrameProcessor.encode()`, `ExportQueueView`, `PreferencesView` unwired, `PlaceholderTests` | Engineer | Low |
| 13 | **Remove `PhotoItem.thumbnail`** - field never populated, causes `@unchecked Sendable` | Engineer | Low |
| 14 | **Accessibility labels** - zero `accessibilityLabel` on custom controls | Designer | Low |
| 15 | **Preview background** - checkerboard is distracting; use neutral dark gray | Designer | Low |
| 16 | **Split view proportions** - preview panel should dominate (~60% width) | Designer | Low |
| 17 | **TOCTOU race in TextureFrameProvider** - concurrent overlay cache access | Engineer | Low |

### P2 - Should Have (Polish & Quality)

| # | Issue | Source | Effort |
|---|-------|--------|--------|
| 18 | **Dual representation in ProcessingConfig** - old flat fields + new layers coexist | Engineer | High |
| 19 | **Move presets out of sidebar** - sidebar should be photos only | Designer | Medium |
| 20 | **Remove orphaned views** - `PresetManagerView`, `ExportQueueView` unused | Designer, Engineer | Low |
| 21 | **Add undo for photo removal** - accidental delete has no recovery | Designer | Low |
| 22 | **Crossfade between preview images** - currently instant swap | Designer | Low |
| 23 | **Layer color-coding by type** - all layers look identical | Designer | Low |
| 24 | **Normal blend mode unvectorized** - 1.4M iterations unaccelerated | Engineer | Medium |
| 25 | **blendWithAccelerate allocates 15 arrays** - ~720MB transient for 12MP | Engineer | Medium |
| 26 | **Makefile/bootstrap script** - new developer onboarding | DevOps | Low |
| 27 | **Stop tracking project.pbxproj** - rely on project.yml + XcodeGen | DevOps | Low |
| 28 | **Remove Package.resolved from .gitignore** - should be committed | DevOps | Low |
| 29 | **CodableColor RGB re-parses hex every access** - hot path inefficiency | Engineer | Low |
| 30 | **DateFormatter allocated per parseDate call** - should be static | Engineer | Low |

### P3 - Nice to Have (Delight & Growth)

| # | Issue | Source | Effort |
|---|-------|--------|--------|
| 31 | **Drag-out from preview** - drag processed image to Finder/apps | Designer | Medium |
| 32 | **Quick Look support** - Space to preview source photo | Designer | Medium |
| 33 | **System notification on export complete** | Designer | Low |
| 34 | **Layer menu in menu bar** - add/delete/reorder via menu | Designer | Medium |
| 35 | **Dark mode audit** - hardcoded colors in checkerboard | Designer | Low |
| 36 | **Distribution pipeline** - DMG/notarization or Homebrew tap for CLI | DevOps | High |
| 37 | **Lightroom plugin** - biggest growth channel for photographers | Product | Very High |
| 38 | **Onboarding / first-run experience** | Designer, Product | Medium |

---

## Recommended Execution Phases

### Phase 1: Harden (1-2 weeks)
> Goal: Make the app safe, correct, and shippable.

- [ ] Fill `Framer.entitlements` with App Sandbox + file access permissions (#1)
- [ ] Replace all `try!` with safe static constants on `CodableColor` (#2)
- [ ] Remove `PhotoItem.thumbnail`, drop `@unchecked Sendable` (#3, #13)
- [ ] Surface errors to users - toast/banner for preset and export failures (#4)
- [ ] Remember last export directory via `@AppStorage` (#5)
- [ ] Fix `deterministicUUID` to use proper hash (#11)
- [ ] Fix TOCTOU race in `TextureFrameProvider` cache (#17)
- [ ] Delete dead code: `FrameProcessor.encode()`, `PlaceholderTests`, orphaned views (#12, #20)
- [ ] Tag HEAD as v2.0.0, update `MARKETING_VERSION` (#9)
- [ ] Remove `Package.resolved` from `.gitignore` (#28)

### Phase 2: Polish (1-2 weeks)
> Goal: Make the app feel like a premium macOS tool.

- [ ] Simplify export flow - direct folder picker for single-preset, sheet only for multi (#6)
- [ ] Add keyboard shortcuts: Cmd+A, Delete, Space (before/after), Cmd+Z exposed in Edit menu (#8)
- [ ] Add accessibility labels to all interactive controls (#14)
- [ ] Replace checkerboard with neutral preview background (#15)
- [ ] Fix split view proportions for preview dominance (#16)
- [ ] Add crossfade animation between preview images (#22)
- [ ] Add undo support for photo removal (#21)
- [ ] Add layer type color-coding (#23)
- [ ] Cache `CodableColor` RGB components, static `DateFormatter` (#29, #30)

### Phase 3: Quality (2-3 weeks)
> Goal: Confidence in correctness through testing and CI.

- [ ] Set up GitHub Actions CI: build + test on every push (#7)
- [ ] Add CaptionRenderer positioning/font tests (10+ tests) (#10)
- [ ] Add TextureFrameProvider overlay tests (#10)
- [ ] Add AppState export pipeline integration tests (#10)
- [ ] Add FrameProcessor rotation tests (#10)
- [ ] Add export format/quality variation tests (#10)
- [ ] Add error path tests (corrupted images, disk full, missing fonts) (#10)
- [ ] Vectorize `.normal` blend mode with vDSP (#24)
- [ ] Reduce transient allocations in `blendWithAccelerate` (#25)
- [ ] Add Makefile with bootstrap/build/test targets (#26)
- [ ] Stop tracking `project.pbxproj` (#27)

### Phase 4: Ship & Validate (2-4 weeks)
> Goal: Get the app into photographers' hands and measure.

- [ ] Set up distribution: notarized DMG or Homebrew tap (#36)
- [ ] Create release automation (changelog from conventional commits)
- [ ] Create 2-3 YouTube demo videos showing workflows
- [ ] Conduct 10-20 photographer interviews for validation
- [ ] Add basic analytics (opt-in usage telemetry)
- [ ] Add first-run onboarding (#38)
- [ ] Remove legacy `ProcessingConfig` flat fields (#18)

### Phase 5: Grow (Quarter+)
> Goal: Build distribution channels and sustainable usage.

- [ ] Lightroom export plugin (#37)
- [ ] Drag-out from preview panel (#31)
- [ ] Quick Look integration (#32)
- [ ] Layer menu in menu bar (#34)
- [ ] Consider freemium model ($9.99/month for advanced features)
- [ ] B2B outreach to photo labs and studios

---

## Key Metrics to Track

| Metric | Target | Why |
|--------|--------|-----|
| Test count | 150+ (from 99) | Cover critical gaps identified by QA |
| Build time | < 10s incremental | Developer productivity |
| Export success rate | 99.9% | User trust |
| Preview render time | < 500ms | Perceived responsiveness |
| Crash rate | 0 (eliminate `try!`) | App stability |

---

## Agent Reports

Full reports from each specialist are available:
- **Engineer**: Architecture, code quality, performance, error handling
- **Designer**: UX/UI, interaction design, accessibility, polish
- **DevOps**: Build system, CI/CD, distribution, security
- **QA**: Test coverage, regression risks, manual test scenarios
- **Product Manager**: `docs/product-review/` (7 documents)
