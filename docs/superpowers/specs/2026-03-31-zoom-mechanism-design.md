# Zoom Mechanism — Design Spec

> **Scope:** macOS (`CanvasView`) and iOS (`PreviewArea`) preview image zoom
> **Platforms:** macOS 14+, iOS 17+

---

## Interaction Model

Gesture-first zoom with a non-intrusive indicator badge. No toolbar zoom controls.

### macOS

| Input | Action |
|-------|--------|
| Scroll wheel / Trackpad pinch | Zoom in/out anchored at cursor position |
| Click + drag | Pan when zoomed in |
| Double-click | Cycle: Fit → 100% → Fit |
| ⌘+ | Zoom in (1.25× step) |
| ⌘− | Zoom out (0.8× step) |
| ⌘0 | Fit to window |
| ⌘1 | Actual pixels (100%) |

### iOS

| Input | Action |
|-------|--------|
| Pinch | Zoom in/out anchored at gesture midpoint |
| Drag (one finger) | Pan when zoomed in |
| Double-tap | Cycle: Fit → 100% → Fit |
| Tap percentage badge | Same as double-tap |

---

## Zoom Range

- **Minimum:** Fit level (image fits viewport — can be < 100% for large images)
- **Maximum:** 400% (4.0× scale)
- **Snap points on double-click/tap:** Fit → 100% → Fit

---

## Zoom Indicator

**Position:** Bottom-right corner of the viewport, 12pt from edges.

**Style:** Dark glass pill (`black @ 70%` with `ultraThinMaterial`, `border` stroke, 6pt corner radius).

### States

**While zoomed (scale ≠ fit):**
- Badge stays visible permanently
- Shows: `[142%] [Fit]`
- Percentage text: Source Code Pro 12pt, `text-1`
- "Fit" button: 11pt, `text-2`, `surface-3` background, 4pt corner radius
- Clicking "Fit" resets to fit level
- Clicking percentage cycles Fit → 100%

**At fit level:**
- Badge shows `[Fit]` briefly (1.5s), then fades out
- No "Fit" button shown (already at fit)
- Reappears on any zoom gesture

**Fade animation:** 0.3s ease-out opacity transition.

---

## Technical Design

### ZoomState (shared model)

```swift
@Observable
final class ZoomState {
    var scale: CGFloat = 1.0        // 1.0 = fit level
    var offset: CGSize = .zero      // pan translation
    var fitScale: CGFloat = 1.0     // computed: image size / viewport size
    
    var displayPercent: Int          // computed: Int(scale * fitScale * 100)
    var isAtFit: Bool               // computed: scale ≈ 1.0
    
    func zoomIn()                   // scale *= 1.25, clamped
    func zoomOut()                  // scale *= 0.8, clamped
    func fitToWindow()              // scale = 1.0, offset = .zero
    func actualPixels()             // scale = 1.0 / fitScale
    func toggleFitActual()          // cycle Fit → 100% → Fit
}
```

`scale` is relative to the fit level (1.0 = image fits viewport). Actual pixel zoom is `1.0 / fitScale`. Max zoom is `4.0 / fitScale`.

### Zoom anchor logic

When zooming via scroll/pinch, the zoom anchors at the cursor/gesture point so the content under the pointer stays fixed. The offset is adjusted as:

```
newOffset = gesturePoint - (gesturePoint - oldOffset) * (newScale / oldScale)
```

### Pan clamping

When panned, the image edges are clamped so the image center cannot leave the viewport. At fit level, offset is forced to `.zero`.

### Auto-reset

Zoom resets to fit (`scale = 1.0, offset = .zero`) when:
- Selected photo changes
- Processing config changes (preview re-renders)

### Platform-specific gestures

**macOS (`CanvasView`):**
- `MagnifyGesture` for trackpad pinch
- `.onScrollWheel` (or `NSEvent.addLocalMonitorForEvents`) for scroll wheel zoom
- `DragGesture` for pan (only active when zoomed)
- `onKeyPress` for ⌘+, ⌘−, ⌘0, ⌘1
- `onTapGesture(count: 2)` for double-click

**iOS (`PreviewArea`):**
- `MagnifyGesture` for pinch zoom
- `DragGesture` for pan (simultaneous with magnify)
- `onTapGesture(count: 2)` for double-tap
- Long-press for original photo (existing) takes priority — resolved via gesture ordering

### ZoomIndicator view

Shared SwiftUI view used on both platforms:

```swift
struct ZoomIndicator: View {
    let zoomState: ZoomState
    let onFit: () -> Void
    let onToggle: () -> Void
}
```

- Positioned via `.overlay(alignment: .bottomTrailing)` on the viewport
- Fade controlled by `zoomState.isAtFit` with 1.5s delay before hiding

---

## Files to Create / Modify

### New files
| File | Purpose |
|------|---------|
| `Sources/FramerApp/Canvas/ZoomState.swift` | Shared zoom state model |
| `Sources/FramerApp/Canvas/ZoomIndicator.swift` | Zoom badge view (macOS) |
| `Sources/FramerMobile/Editor/ZoomIndicator.swift` | Zoom badge view (iOS, same logic) |

### Modified files
| File | Changes |
|------|---------|
| `Sources/FramerApp/Canvas/CanvasView.swift` | Wrap image in zoomable container, add gestures, keyboard shortcuts |
| `Sources/FramerMobile/Editor/PreviewArea.swift` | Add pinch/pan/double-tap gestures, zoom indicator |
