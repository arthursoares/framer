# Retire the CPU Effect Path — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute ADR `docs/adr/2026-07-09-retire-cpu-effect-path.md` — delete the redundant CPU effect implementations (~2,700 lines), make Metal a hard requirement for `.shader`/`.dither` effect rendering, keep Riemersma and the legacy bucket CPU loops as explicit capabilities, and re-anchor the parity test suite to frozen golden references.

**Architecture:** `ShaderRenderer.apply` becomes a direct GPU dispatcher (no `gpuOrCPU`). `DitherRenderer.apply` dispatches by algorithm: `.riemersma` → kept CPU implementation, all else → `DitherGPURenderer` with errors propagating. `EffectGPUParityTests` becomes `EffectGPUGoldenTests`: GPU renders compared against PNGs in `Tests/FramerCoreTests/Resources/GoldenReferences/` (regenerable via `FRAMER_REGENERATE_GOLDENS=1`), same per-effect tolerances. LUT stack and legacy bucket variants untouched.

**Tech Stack:** Swift 5.10, XCTest, SPM (FramerCore tier only — no xcodegen needed; FramerCore is a local package and test resources already `.copy` the Resources dir).

**Reference:** ADR at `docs/adr/2026-07-09-retire-cpu-effect-path.md`; inventory classifications therein.

---

## File Map

### Create
- `docs/adr/2026-07-09-retire-cpu-effect-path.md` — the decision record
- `Tests/FramerCoreTests/Resources/GoldenReferences/*.png` — 13 frozen GPU references

### Delete
- `Sources/FramerCore/Processing/ShaderASCIIRenderer.swift` — CPU ASCII (redundant with `TextCellRenderer.renderASCII`)
- `Sources/FramerCore/Processing/ShaderPixelSortRenderer.swift` — CPU pixel sort (unreachable on Metal hosts)

### Modify
- `Sources/FramerCore/Processing/ShaderRenderer.swift` — direct GPU dispatch; delete `gpuOrCPU` + 7 CPU styles + helpers
- `Sources/FramerCore/Processing/DitherRenderer.swift` — riemersma-only CPU body; algorithm-dispatched entry; delete 15 CPU algorithms + matrices
- `Sources/FramerCore/Effects/Renderers/DitherGPURenderer.swift` — riemersma guard becomes a precondition of the caller, comment updated
- `Tests/FramerCoreTests/EffectGPUParityTests.swift` → `EffectGPUGoldenTests.swift` — golden anchoring; drop CPU symbols
- `Tests/FramerCoreTests/DitherRendererTests.swift`, `ShaderRendererTests.swift` — Metal-skip guards (they now throw on Metal-less hosts)
- `Sources/FramerCore/Processing/FrameProcessor.swift`, `Sources/FramerCore/Effects/GPU/GPUEffectsPlatform.swift` — stale "falls back to CPU" comments from PR #12
- `CLAUDE.md` rule 4, `.claude/skills/framer-architecture-contract`, `framer-change-control`, `framer-validation-and-qa`, `framer-research-frontier`, `CHANGELOG.md` — sync to the new contract

---

## Task 1: Record the decision
- [x] ADR + this plan committed.
  `git commit -m "docs(adr): record the CPU-effect-path retirement decision"`

## Task 2: Freeze golden references (before deleting anything)
- [ ] Add `EffectGPUGoldenTests.swift` with: golden loader, env-gated regenerator (records its command in the header), and 13 golden tests mirroring the CPU-vs-GPU parity list (ascii ×2, crimewave ×2, narc, shiba ×2, distantPast ×2, crt, halftone-mono, kuwahara, pixelSort-default-span) using the existing per-effect tolerances.
- [ ] Generate goldens on this machine: `FRAMER_REGENERATE_GOLDENS=1 swift test --filter EffectGPUGoldenTests`
- [ ] `swift test` — old parity tests AND new golden tests both green (predicted golden deltas: mean 0.0, max 0).
  `git commit -m "test(gpu-effects): anchor effect verification to frozen golden references"`

## Task 3: Retire ShaderRenderer CPU path
- [ ] `ShaderRenderer.apply` → direct GPU calls; delete `gpuOrCPU`, 7 CPU implementations, `mixStylizedContext`/`smoothstep`; delete the two CPU renderer files; fix the stale pixel-sort span comment.
- [ ] Remove/convert the 13 CPU-referencing tests in `EffectGPUParityTests.swift`; keep GPU-only smoke tests; add Metal-skip guards to `ShaderRendererTests`.
- [ ] `swift build && swift test` green.
  `git commit -m "refactor(gpu-effects): retire ShaderRenderer CPU implementations — GPU is the only path"`

## Task 4: Retire DitherRenderer CPU algorithms
- [ ] `apply` dispatches `.riemersma` → CPU, else GPU (errors propagate); prune CPU body to riemersma + required plumbing; delete matrices/tables and cmykHalftone mono fallback; update `testDitherRiemersmaRoutesToCPU` (explicit dispatch), delete `testDitherCMYKHalftoneFallsBackOnEmptyMetal`; Metal-skip guards in `DitherRendererTests` (except riemersma tests).
- [ ] `swift build && swift test` green; `git mv` parity file to `EffectGPUGoldenTests.swift` home if not already done.
  `git commit -m "refactor(dither): retire CPU dither algorithms — Riemersma stays as the sole serial implementation"`

## Task 5: CLI visual gate
- [ ] Render a real image through dither + shader + lut layers via `swift run framer` before/at HEAD and eyeball vs Task-2 output (render-path gate from framer-change-control).

## Task 6: Sync the record
- [ ] Fix stale comments (`FrameProcessor.swift:168-171`, `GPUEffectsPlatform.swift:38-42`); update CLAUDE.md rule 4, the four skills, CHANGELOG `[Unreleased]`.
  `git commit -m "docs: sync skills, CLAUDE.md, CHANGELOG to the GPU-only effect contract"`

## Task 7: Adversarial review
- [ ] Three parallel reviewers (bug-hunter / Swift-idiom / architecture), different prompts; verify findings before applying (house pattern).
- [ ] Push branch, open PR (body: symptom → mechanism → fix → why safe; PR #11 as model). Human merges.
