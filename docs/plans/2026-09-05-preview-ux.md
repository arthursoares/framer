# Preview and onboarding UX

Baseline: `9ab68a4`. Scope is limited to the macOS and iOS preview models and
preview surfaces, plus focused lifecycle regressions.

## Behavior

- Treat photo identity and rotation as the preview request identity. A new
  identity immediately clears the old rendered image, original, dimensions,
  and desktop EXIF data. A config-only rerender retains the current edited
  image and shows a compact progress indicator.
- Enter loading state when a request is submitted, before the debounce. Keep
  preview and original errors separate so an original failure cannot masquerade
  as a render failure or an empty selection.
- Render the original through `FrameProcessor.previewCGImage` with an empty
  layer stack, the current rotation, and a 1200-pixel bound. Key original work
  by photo ID, rotation, and generation to reject stale A-B-A completions.
- Give empty libraries a direct photo-import action. When a library has content
  but no selection, explain that the user should choose a filmstrip item.
- Keep the edited image visible during adjustment renders. Failed previews and
  originals expose Retry; an original failure also exposes Show Edited.
- Add a visible 44-point Before/After control on iOS. Keep press-to-compare on
  the image itself so its gesture does not intercept the control or other
  buttons.

## Verification

- Cover request-time loading, different-photo clearing, same-photo retention,
  render retry, current-rotation original loading, and stale A-B-A rejection.
- Run the focused macOS preview lifecycle suite and the iOS preview UX suite,
  followed by the existing macOS and iOS test targets when integration permits.
- Do not refresh sidebar snapshot hashes; these canvas changes do not alter the
  inspector grammar.

## Results

- Integrated macOS suite: 69 tests passed, zero failures/skips.
- Integrated iOS suite: 12 tests passed, zero failures/skips after the gesture
  review fixes. The new test file is included in the regenerated Xcode project.
- The first PR also includes EditorView's picker-presentation bridge so the
  mobile empty-state action works independently of the later feedback PR.
- Live walkthrough verified the desktop import flow and mobile Choose Photos
  flow with the repository sample. Before the fix, rotating the sample and
  selecting Before visibly reverted its orientation; rotation-aware original
  loading is covered by the new regressions.
- Independent review's gesture findings were fixed: the recognizer remains
  mounted during original loading, always handles release during pan, and
  restores the pre-press mode without overriding explicit comparison selection.
- Before/After expose separate descriptive accessibility labels.
