# CLI safety cleanup plan

## Goal

Keep loaded layer stacks intact unless a caption-related CLI flag explicitly requests a change, and reject batch output collisions before rendering or creating the output directory.

## Existing behavior to lock and defects to expose

- Keep worker validation, output-format overrides, padding precedence, shell quoting, output naming, bounded task-group scheduling, post-processing, and thrown render errors behaving as they do today.
- Add regression coverage showing that a loaded explicit layer stack currently loses caption identity, ordering, and parameters even when no caption or font flag is supplied.
- Add coverage for explicit caption removal/replacement, field-only font overrides, default-caption insertion when an explicit caption/font flag targets a stack without a caption, and the legacy default caption when `layers` is absent.
- Add batch preflight coverage for two inputs that resolve to one destination, including case-only collisions when the destination filesystem is case-insensitive, and prove validation runs before output-directory creation or rendering.

## Cleanup sequence

1. Extend `ProcessCommandTests` with regression cases against command-owned seams used by `run()`; run them before production edits and record the expected failures.
2. Extract the existing CLI-to-config mutation from `run()` into a command helper, preserving the existing border/output/padding/aspect behavior while making caption changes conditional on explicit flags.
3. Precompute batch input/output pairs and validate destination uniqueness before creating the output directory or adding task-group work. Reuse one task body for both initial and replacement workers.
4. Run the focused CLI tests, then the full SwiftPM test gate if the focused suite passes. Review only the assigned diff and leave Git LFS asset noise untouched.

## Caption override semantics

- `--caption-template` takes precedence over `--caption`, matching the current command ordering.
- A text flag replaces all existing caption layers with one default-based caption appended to the stack, matching the command's current minimal replacement behavior; explicit font flags also apply to that replacement.
- Font flags update only fields explicitly supplied. Bold and italic flags add those traits to each existing caption layer; absent style flags preserve existing traits.
- `--no-caption` takes precedence over all caption/font flags and removes every caption layer.
- If explicit caption/font flags are supplied and the stack contains no caption, append one default caption layer with only the supplied values changed.
- If `layers` is absent, materialize legacy defaults and retain the default caption even when no caption flag is supplied.

## Scope

`Sources/FramerCLI/Commands/ProcessCommand.swift`, `Tests/FramerCLITests/ProcessCommandTests.swift`, the updated caption/batch guidance in `.claude/skills/framer-run-and-operate/SKILL.md`, and this plan. No dependencies or shared model/schema changes.

## Verification and review

- Baseline: 8 existing CLI tests passed. Added the new command/config regressions
  before implementation; they initially failed to compile against the missing
  test seams. After implementation, the worker's focused 18 and full 325 tests
  passed against the cleanup baseline.
- Integration also covers an empty explicit stack and valid case-distinct outputs
  on case-sensitive volumes. A real two-worker CLI batch rendered both images;
  a colliding batch failed before its output directory existed.
- Independent review found that unknown volume capability was assumed
  case-sensitive. Added a controlled resource-reader regression: both nil and
  throwing lookups allowed a collision before the fix. Unknown volumes now use
  conservative case-insensitive matching; known case-sensitive volumes keep
  distinct names.
- Final integrated gate: `swift build --scratch-path /tmp/framer-cleanup-build`
  and `swift test --scratch-path /tmp/framer-cleanup-build` passed **330 tests,
  zero failures, zero skips, zero warnings**. `git diff --check` passed.
