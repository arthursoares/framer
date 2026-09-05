# App lifecycle race fixes

## Scope

Fix the audited mobile layer identity, preset-preview invalidation, photo-import cancellation, and mobile/macOS preview lifecycle races. Keep rendering behavior and the existing utility QoS choice unchanged.

## Regression-first sequence

1. Add a `FramerMobileTests` Xcode target and deterministic tests for:
   - editor fallback layers retaining UUID identity without changing a `layers == nil` render config;
   - preset render keys changing for photo, rotation, and full preset configuration changes;
   - cancelled preset batches being unable to write after a replacement batch starts;
   - cancelled photo imports cleaning temporary files without clearing newer loading or picker state;
   - cancelled mobile preview work being unable to clear or overwrite newer preview state.
2. Add macOS preview tests proving that nil selection invalidates an in-flight render and that an older completion cannot clear loading or write an error while a newer render is active.
3. Run those tests against the current implementation and record the expected failures before changing production behavior.
4. Implement the smallest state and generation changes needed for the tests:
   - keep stable editor fallback layers in `AppState` and publish them into the config only when edited;
   - observe a complete preset-preview render key and guard cache writes with a generation;
   - route picker imports through a generation-aware coordinator that owns cancellation cleanup;
   - increment preview generations for every request, including nil, and guard success, error, and deferred cleanup writes.
5. Regenerate the Xcode project, rerun focused test targets, then run the relevant app builds/tests with signing disabled and isolated derived-data paths.

## Constraints

- Do not change render algorithms, preset serialization, signing settings, or dependencies.
- Do not refresh visual snapshot hashes.
- Ignore existing Git LFS working-tree noise under `assets/textures`.
- Preserve concurrent extraction work outside the assigned files.

## Review and validation

- Keep `ProcessingConfig.layers == nil` intact: it selects the legacy renderer.
  Review caught and removed an initial materialization that changed fresh-photo
  and legacy-preset output. Stable editor-only fallback IDs now solve navigation
  without changing config values or sorted JSON bytes until a layer is edited.
- Preset renders stay in the structured task group. Removing the detached
  boundary lets cancellation reach the shared processor instead of queuing
  obsolete work ahead of replacement batches.
- Controlled requests are queued by request order, so tests cover overlapping
  requests for the same photo URL and preset ID. The cancellation probe uses an
  explicitly released continuation and fails promptly if propagation regresses.
- Photo IDs cover source URL changes because `PhotoItem.url` is immutable and
  each item receives a newly generated ID. Rotation and complete preset values
  are included in the preview key.
- `xcodegen generate` regenerated the committed project and mobile scheme.
- Full integrated macOS target: **65 tests, zero failures/skips**, including
  both new lifecycle tests and existing exact sidebar snapshots.
- Full integrated mobile target on iPhone 17 Pro / iOS 26.5: **7 tests, zero
  failures/skips**. Tests built with the complete asset catalog and no source
  exclusions. Both Xcode commands used `CODE_SIGNING_ALLOWED=NO` and temporary
  derived-data directories.
- Mobile validation required installing both the matching simulator runtime and
  Xcode's separate iOS 26.5.1 Platform Support component. The runtime alone was
  insufficient; Xcode's Components settings showed the missing support package.
- Existing iOS deprecation warnings and AppIntents metadata notices remain;
  no warning was introduced in the changed lifecycle source. Independent review
  found no remaining production issue after the corrections above.
