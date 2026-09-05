# Honest operation feedback

Baseline: `9ab68a4`. Scope: preset operations on macOS and iOS, mobile photo
import feedback, and the mobile photo-picker presentation bridge.

## Behavior contract

- Preset names are trimmed before saving. Empty names and case-insensitive
  duplicates are explained in the naming prompt and cannot be submitted.
- Save, update, rename, and delete change the visible preset list or active
  preset only after the `PresetStore` operation succeeds. Failures keep the
  prior UI state and show a clear, user-facing message.
- Deleting a saved preset requires confirmation. This confirmation applies to
  persistent presets and does not change layer deletion behavior.
- Multi-file and multi-preset imports report complete failure and partial
  success. Array members are saved independently, so a later write failure
  cannot hide presets that were already saved. Imports do not activate a
  preset, so a failed file cannot leave a nonexistent preset selected.
- A failed security-scope request does not prevent an iOS read attempt. Every
  successful request is balanced after the file read.
- Mobile preset exports use valid JSON in a unique temporary directory. The
  display name is reduced to a safe filename component, and temporary files
  are removed after the share sheet finishes or presentation fails.
- Mobile photo imports count transfer and temporary-write failures. Only the
  current import generation may add photos, clear picker selection, or publish
  feedback. Partial and complete failures report successful and skipped counts.
- Partial batch-share feedback appears after the share sheet closes, once its
  temporary files have been removed, so two presentations never compete.
- `EditorView` presents the system photo picker from the shared
  `showingPhotosPicker` flag so empty-state and toolbar entry points use the
  same selection flow.

## Verification

Focused app tests cover final-store filesystem failures, invalid and duplicate
names, state preservation, partial/all-failed preset imports, safe export
filenames, photo-import counts, and stale-generation feedback suppression.
Run macOS and iOS test schemes with signing disabled and separate Derived Data
directories after regenerating the local Xcode project. Existing snapshot
baselines are not refreshed as part of this change.

Integrated result above preview UX: 332 Core/CLI, 74 macOS, and 20 iOS tests
passed with zero failures/skips. The committed Xcode project includes all new
test files. Independent review confirmed that per-preset partial imports,
share-completion sequencing, and the picker integration resolve the findings.
