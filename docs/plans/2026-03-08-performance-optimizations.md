# Performance Optimizations Plan

> Compiled from 3 specialist agent reviews: Image Pipeline, SwiftUI Views, Concurrency.
> Date: 2026-03-08

---

## Fix 1: NSFont -> CoreText (Correctness + Crash Prevention)

**File:** `Sources/FramerCore/Processing/CaptionRenderer.swift`

**Problem:** `NSFont`, `NSFontManager.shared` are AppKit APIs called from `FrameProcessor` actor (background thread). AppKit is not thread-safe. Latent crash risk on any macOS update.

**Fix:** Replace with CoreText equivalents:
- `NSFont(name:size:)` -> `CTFontCreateWithName(name, size, nil)`
- `NSFontManager.shared.convert(_:toHaveTrait:.boldFontMask)` -> `CTFontCreateCopyWithSymbolicTraits(font, size, nil, .boldTrait, .boldTrait)`
- Same for italic
- `NSColor(cgColor:)` -> use `CGColor` directly with CoreText attributed string keys
- Keep `CTLineDraw` (already CoreText)

**Impact:** Eliminates crash risk. Thread-safe font handling.

---

## Fix 2: Parallel GUI Export with TaskGroup

**File:** `Sources/FramerApp/App/AppState.swift`

**Problem:** `exportItems` processes photos sequentially in a `for` loop. On a 10-core machine processing 30 photos, 90% of cores are idle. The CLI already uses `withThrowingTaskGroup` correctly.

**Fix:** Replace the sequential loop with `withThrowingTaskGroup`:
- Cap concurrency to `ProcessInfo.processInfo.processorCount`
- Each child task creates its own `FrameProcessor` instance
- Progress updates via `await MainActor.run { }` after each task completes
- Mirror the CLI's `ProcessCommand.batchProcess` pattern

**Impact:** Near-linear speedup with core count for batch exports.

---

## Fix 3: Vectorize `.normal` Blend + Reuse Buffers

**File:** `Sources/FramerCore/Processing/BorderRenderer.swift`

**Problem A:** `.normal` blend mode (lines ~602-613) uses a scalar `Double` loop over 12M pixels. Other blend modes use vDSP. This is the most common blend mode (frames, dust overlays).

**Problem B:** `blendWithAccelerate` allocates 15 `[Float]` arrays (~300-400MB for 12MP) on every call with no buffer reuse.

**Fix A:** Vectorize `.normal` with vDSP:
- `vDSP_vfltu8` to convert UInt8 -> Float
- `vDSP_vsadd` + `vDSP_vabs` + `vDSP_vsmul` for luminance-based alpha
- `vDSP_vclip` for clamping

**Fix B:** Pre-allocate reusable Float buffers:
- Use `UnsafeMutableBufferPointer` backed by a reusable pool
- Or use vImage's `vImageConvert_ARGB8888toPlanarF` to deinterleave without separate arrays
- Clear/reuse between calls instead of allocating fresh arrays

**Fix C:** Replace scalar re-interleave write-back (lines ~778-784) with `vDSP_vfixu8` + scatter.

**Impact:** 4-8x speedup on overlay blending. ~300MB less heap pressure per overlay.

---

## Fix 4: Split AppState into Library vs Editor

**File:** `Sources/FramerApp/App/AppState.swift` + all view files

**Problem:** One flat `@Observable` class with 7 properties. Slider drag on a border thickness invalidates `LibrarySidebar`, `LivePreviewPanel`, and `SettingsPanel` simultaneously. Export progress ticks also re-render the sidebar.

**Fix:** Split into two `@Observable` classes:
- `LibraryState`: `library`, `selectedItems`, `exportQueue`
- `EditorState`: `currentConfig`, `activePresetName`, `presets`, `presetStore`
- Views only observe the state they need
- Pass both via `.environment()`

**Impact:** Dramatically reduces unnecessary view re-renders during editing.

---

## Fix 5: ImageIO Thumbnail API + Cache

**File:** `Sources/FramerApp/Library/PhotoThumbnailView.swift`

**Problem:** `AsyncThumbnail` decodes the full-resolution image via `CGImageSourceCreateImageAtIndex`, then manually crops and downscales to 80x80. For 100+ photos, 100+ detached tasks fire simultaneously with no concurrency cap. Each decodes a full 24MP image just to make an 80px thumbnail.

**Fix:**
- Use `CGImageSourceCreateThumbnailAtIndex` with options:
  - `kCGImageSourceCreateThumbnailFromImageAlways: true`
  - `kCGImageSourceThumbnailMaxPixelSize: 80`
  - `kCGImageSourceCreateThumbnailWithTransform: true`
- Add a process-wide `NSCache<NSURL, NSImage>` for decoded thumbnails
- Cap concurrent decode tasks (actor-based semaphore or similar)

**Impact:** Orders of magnitude less memory per thumbnail. Faster scroll performance.

---

## Fix 6: Share Decoded CGImage Between Original + Preview

**File:** `Sources/FramerApp/Editor/PreviewViewModel.swift`, `Sources/FramerCore/Processing/FrameProcessor.swift`

**Problem:** `PreviewViewModel.updatePreview` calls `loadOriginal` (decodes full JPEG from disk) AND `processor.previewImage` (which calls `loadImage` internally, decoding the same JPEG again). Double decode = 100-200ms wasted per preview update.

**Fix:**
- Add an optional `preDecodedImage: CGImage?` parameter to `FrameProcessor.previewImage`
- In `PreviewViewModel`, decode once and pass to both `loadOriginal` (downscale for before/after) and `previewImage`
- Or cache the decoded CGImage keyed by URL

**Impact:** Eliminates ~100-200ms redundant decode per preview refresh.

---

## Fix 7: Add Cancellation Checkpoints in Pipeline

**Files:** `Sources/FramerCore/Processing/FrameProcessor.swift`, `Sources/FramerCore/Processing/BorderRenderer.swift`

**Problem:** When the user changes settings rapidly, previous preview renders are cancelled but continue running to completion inside FrameProcessor. No cooperative cancellation points exist in the pipeline. Wasted CPU on discarded results.

**Fix:** Add `try Task.checkCancellation()` at natural boundaries:
- After `loadImage` in `FrameProcessor.previewImage`
- After `downscale`
- Inside `BorderRenderer.applyLayers` between each layer iteration
- The method is already `throws` so no API change needed

**Impact:** Rapid settings changes waste far less CPU. More responsive preview.

---

## Fix 8: Move `loadOriginal` Off MainActor

**File:** `Sources/FramerApp/Editor/PreviewViewModel.swift`

**Problem:** `loadOriginal` is a synchronous static function that decodes a full-resolution image. It's called inside `Task { }` which inherits `@MainActor` isolation from `PreviewViewModel`. This blocks the main thread during image decode (100-200ms for large files).

**Fix:** Wrap `loadOriginal` in `Task.detached { }` or use `async let` to run it concurrently with `processor.previewImage`:
```swift
async let original = Task.detached { Self.loadOriginal(from: item.url, maxDimension: 1200) }.value
async let preview = processor.previewImage(for: item.url, config: config, rotation: item.rotation)
```

**Impact:** Unblocks main thread during preview loading. Both loads run concurrently.

---

## Additional Improvements (Lower Priority)

| # | Issue | File |
|---|-------|------|
| 9 | Preview scales to canvas size (up to 3000px) not display size | `FrameProcessor.swift` |
| 10 | Two simultaneous full-res CGContexts in overlay (192MB) | `BorderRenderer.swift` |
| 11 | `bitmapInfo` copied from source causes silent format conversions | `BorderRenderer.swift` |
| 12 | `layersBinding` computed var allocates new Binding every render | `SettingsPanel.swift` |
| 13 | LayerRow @Binding chain re-renders full subtree on slider drag | `LayerListSection.swift` |
| 14 | `monospacedFontList` sorted on every body eval at 60fps | `LayerListSection.swift` |
| 15 | Export progress ticks trigger full queue section re-render | `AppState.swift` |
| 16 | TextureFrameProvider TOCTOU locking pattern | `TextureFrameProvider.swift` |
| 17 | FrameProcessor actor adds unnecessary hop (no stored state) | `FrameProcessor.swift` |
| 18 | `canCoalesce` only scans 2 layers ahead | `BorderRenderer.swift` |
