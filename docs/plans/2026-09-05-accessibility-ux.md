# Legibility and desktop interaction

Plan before implementation:

1. Add runtime color-contrast regressions for normal text tokens across all
   five app surfaces; capture the existing sidebar snapshot renders.
2. Brighten secondary text using the existing warm palette. Keep surfaces,
   accent colors, layout metrics, and rendered photo output unchanged.
3. Make filmstrip selection a real labeled button while retaining command-click
   selection. Label export actions and allow all finished jobs to be cleared.
4. Capture/read the intentional before/after pixel differences, then refresh
   only snapshot hashes explained by the text change. Run app suites and review.

The contrast target is 4.5:1 for normal text, per
[WCAG contrast minimum](https://www.w3.org/TR/WCAG22/#contrast-minimum).
This is a readability regression guard, not a claim of complete conformance.

## Results

- Runtime tests reproduced nine failing text/surface combinations before the
  color change. `text2` is now `#A6A198`; `text3` is `#96928B`, with a worst
  normal-text contrast of 4.61:1 across the five surfaces.
- Captured all ten sidebar surfaces before/after using the opt-in
  `FRAMER_SNAPSHOT_ARTIFACT_DIR` test variable. Inspected the after renders,
  checked representative pairs, and verified every old PNG hash matched its
  baseline and every image retained its dimensions before replacing hashes.
  Pixel changes are brighter text/icons and the queue's failure text/Clear
  Finished action. No effect-render goldens changed.
- Filmstrip items are real buttons with names, selection state, and an
  accessible multi-selection action. The queue clears finished failures while
  retaining queued/running jobs, labels actions, and announces waiting jobs
  correctly. These behaviors have focused regression coverage.
- The sidebar primitive itself was left unchanged: a corrected traversal of
  SwiftUI's informal accessibility nodes confirms its child buttons exist.
- All four new test files are included in the regenerated root project.
- Final stack passes 332 Core/CLI, 78 macOS, and 25 iOS tests, zero failures/skips.
  Live simulator inspection confirmed selected tab semantics and direct layer
  visibility toggling without opening the detail view.
