# Mobile controls accessibility pass

Baseline: `9ab68a4`. This slice keeps the existing Darkroom styling and the
`AppState.editorLayers` read/write contract.

## Plan before changes

1. Give each bottom mode tab its full half-width hit region with at least 44
   points of height, expose the selected tab to assistive technologies, and
   switch modes without selection animation.
2. Split layer navigation and visibility into sibling controls so every layer
   can be shown or hidden directly from the strip without intercepting row
   navigation.
3. Apply visibility, drag reorder, accessibility reorder, and deletion by the
   layer UUID against the latest `editorLayers` value. Keep deletion immediate
   because the editor already registers configuration changes with undo.
4. Preserve text wrapping at large Dynamic Type sizes and suppress structural
   drag animations when Reduce Motion is enabled.
5. Add focused tests for ID-safe visibility and ordering plus hosted SwiftUI
   measurements of the tab and visibility hit targets.

## Validation

- `swiftc -parse` passed for all three changed views and the new test file.
- `xcodebuild test` passed for the complete `FramerMobile` scheme on the iOS
  26.5 iPhone 17 Pro simulator (`FAAE195F-B31D-444F-A8F9-AED33ADEB951`),
  using `/private/tmp/framer-ux-controls-derived`.
- Existing warnings remain in `PresetStrip`, `ShaderControls`, and
  `GPUEffectControls`; this slice introduced no compiler errors or test
  failures.
