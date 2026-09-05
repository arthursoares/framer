# Layer editor file split

## Goal

Reduce the macOS and iOS layer editor entry files to coordinators while preserving every existing control body, binding, result builder, parameter range, and platform-specific behavior.

## Invariants

- Move declarations without redesigning or normalizing them.
- Keep each layer editor with its existing private helpers.
- Keep the large GPU effect and shader editors intact as one file each.
- Keep macOS and iOS implementations separate.
- Change access only where a coordinator or another extracted control must reference a formerly file-private declaration.
- Preserve the sidebar result-builder and metric behavior covered by the macOS snapshot suite.
- Add no dependencies or build-setting changes; regenerate project file references.

## Mechanical split

1. Leave `LayerListSection` and `LayerDetailView` as dispatch coordinators.
2. Move each platform's layer-specific editors into `LayerControls/` or `Controls/` files named for the owned layer.
3. Move controls used by several extracted editors into a platform-local shared-controls file.
4. Move each platform's `Color` hex helper into its own platform-local file because several editors use it.
5. Regenerate and commit the integrated Xcode project, retaining the mobile test target from the parent PR.

## Verification

1. Compare normalized declarations before and after the move, allowing only imports and access-level changes.
2. Run the full macOS app test suite with signing disabled, including exact snapshot hashes.
3. Run the full mobile test target on the installed simulator with signing disabled.

## Integrated result

- `LayerListSection.swift`: 5,272 to 222 lines, with 15 extracted macOS files.
- `LayerDetailView.swift`: reduced from 3,891 lines to a navigation coordinator,
  with 14 extracted iOS files.
- Independent review compared every extracted source chunk against the parent,
  allowing only imports, access levels, and section-marker placement. Control
  bodies, bindings, parameter ranges, and result builders remain unchanged.
- Integrated macOS suite: **65 tests, zero failures/skips**, including all exact
  sidebar snapshots. The standalone extraction baseline passed 63 tests; the
  parent lifecycle PR adds two more.
- Integrated iOS suite: **7 tests, zero failures/skips**, using the complete app
  target and asset catalog on iPhone 17 Pro / iOS 26.5.
- Both commands used temporary derived data and `CODE_SIGNING_ALLOWED=NO`.
  No snapshots were refreshed. Existing deprecation/AppIntents notices remain.
- Normal `swift build` and `swift test` also pass: **330 tests, zero failures
  or skips**, after clearing stale generated artifacts from the old repo path.
- Updated the architecture file map and current validation status to reflect
  the extracted controls and the restored Xcode test tiers.
