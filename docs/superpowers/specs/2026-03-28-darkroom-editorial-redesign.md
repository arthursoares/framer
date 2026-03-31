# Darkroom Editorial — UI Redesign Spec

> **Source:** `assets/design/DESIGN_BRIEFING.md` (full token/component reference)
> **Mockup:** `assets/design/framer-final-concept.html` (interactive prototype)
> **Scope:** `Sources/FramerApp/` only. No changes to `FramerCore` or `FramerCLI`.

---

## Design Decisions (Resolved)

| Decision | Resolution |
|----------|------------|
| Export queue UI | Popover from ExportBar — keeps inspector clean |
| Font bundling | Bundle both Atkinson Hyperlegible Next + Source Code Pro |
| Multi-window | Keep `WindowGroup` as-is — redesign doesn't break it |
| Unused views (`PresetManagerView`, `ExportQueueView`) | Delete during migration — superseded by new components |

---

## Architecture Overview

### Layout: 3-column → 2-column

```
Current:                          New:
NavigationSplitView(.balanced)    HStack(spacing: 0)
├─ LibrarySidebar (200-300pt)     ├─ CanvasView (flexible)
├─ LivePreviewPanel               │   ├─ Viewport (preview + before/after)
└─ SettingsPanel (260-400pt)      │   ├─ FilmstripView (floating, bottom)
                                  │   └─ ExifBar (fixed, bottom)
                                  └─ InspectorView (280pt fixed)
                                      ├─ ActivePresetBanner
                                      ├─ PresetPreviewGrid
                                      ├─ LayerListSection (restyled)
                                      ├─ OutputSection
                                      └─ ExportBar (pinned bottom)
```

Min window: 900x650 (down from 1000x700).

### State Management — No Changes

- `AppState` (`@Observable`) stays as-is
- `PreviewViewModel` stays as-is
- Views continue using `@Environment(AppState.self)`
- All existing data models untouched

---

## New Components

### DesignTokens.swift
Color constants (5 surface levels, 4 text levels, amber accent variants, functional colors, borders) and font helpers (Atkinson body, Source Code Pro mono) as `Color`/`Font` extensions. Spacing constants. See briefing section 1-2 for exact values.

### CanvasView.swift
Replaces `LivePreviewPanel` as the main viewport. Contains:
- Dark `surface-0` background with subtle radial gradient (accent @ 2%)
- Centered preview image with shadow (black 35%, r16, y4)
- Before/After pill toggle (top-left, `.ultraThinMaterial`)
- Drop zone with dashed accent border on `isTargeted`
- Reuses `PreviewViewModel` rendering logic from `LivePreviewPanel`

### FilmstripView.swift + FilmstripThumbnail.swift
Floating horizontal strip at bottom of canvas (14pt inset, stops 294pt from right).
- Glass container: `black @ 60%` + `.ultraThinMaterial`, 12pt corner radius
- 48x34pt thumbnails in `HStack(spacing: 3)`, reusing `AsyncThumbnail` cache
- Selected: 1.5pt accent border + glow. Opacity states: default 0.55, hover 0.85, selected 1.0
- Count label + circular "+" add button at end
- Tap = select, Cmd-click = multi-select (existing behavior)

### PresetPreviewGrid.swift + PresetPreviewCard.swift
3-column `LazyVGrid` in inspector showing rendered thumbnails per preset.
- Each card: 4:3 ratio, `surface-3` background, 6pt corner radius
- Active state: accent border + glow + checkmark badge
- **Rendering strategy:** On photo selection change, debounce 200ms, then kick off background renders at max 200px using `FrameProcessor.previewImage()`. Store in `[UUID: NSImage]` dict. Cancel in-flight on photo change.
- Last card: "+ Save" with dashed border

### InspectorView.swift
Replaces `SettingsPanel`. Same structure but custom-styled:
- `surface-1` background, 1pt left border
- `ScrollView` with manual sections (no `Form/.formStyle(.grouped)`)
- Sections: ActivePresetBanner, PresetPreviewGrid, LayerListSection, OutputSection
- ExportBar pinned via `.safeAreaInset(edge: .bottom)`

### ExportBar.swift
Two buttons: "Selected (N)" secondary, "All (N)" primary (accent-dim bg).
- Click triggers export flow (existing sheet/folder-picker logic from SettingsPanel)
- Export queue: popover showing job list with progress, reveal, retry — adapted from existing `SidebarQueueSection` logic

### Custom Controls
| Control | File | Spec |
|---------|------|------|
| Slider + numeric input | `StyledSlider.swift` | 3pt track, 12pt thumb, surface-3 text field, mono font |
| Toggle | `StyledToggle.swift` | 32x18pt capsule, accent-dim when on |
| Format picker | `FormatPicker.swift` | Two-pill segmented, accent-subtle active state |

---

## Modified Files

### ContentView.swift
Replace `NavigationSplitView` with `HStack(spacing: 0)` containing `CanvasView()` + `InspectorView().frame(width: 280)`.

### FramerApp.swift
Adjust min window size to 900x650. Add font registration at launch (`CTFontManagerRegisterFontsForURL` for bundled fonts).

### LayerListSection.swift
Restyle only — no logic changes:
- Custom `DisclosureGroup`-style expand/collapse
- Dark theme colors from DesignTokens
- Layer rows: transparent → border on hover → surface-2 when expanded
- Badges in mono font, surface-4 pill
- All undo/redo, drag-reorder, layer controls logic preserved

### LivePreviewPanel.swift
Extract rendering/EXIF logic into CanvasView, then delete. `PreviewViewModel` stays as its own file.

### PhotoThumbnailView.swift
Keep `AsyncThumbnail` + cache. Remove sidebar-specific layout. Used by FilmstripThumbnail.

### Files to Delete
- `LibrarySidebar.swift` — replaced by FilmstripView + titlebar buttons
- `PresetManagerView.swift` — replaced by PresetPreviewGrid
- `ExportQueueView.swift` — replaced by ExportBar popover

---

## Resources

- Bundle: `AtkinsonHyperlegible-Regular.ttf`, `AtkinsonHyperlegible-Bold.ttf`, `SourceCodePro-Regular.ttf`, `SourceCodePro-Medium.ttf`
- Register via `ATSApplicationFontsPath` in Info.plist or `CTFontManagerRegisterFontsForURL` at app launch

---

## Migration Order

Each step = separate commit, app functional throughout:

1. **DesignTokens** — colors + font helpers, no UI changes
2. **ContentView stub** — swap to HStack, stub CanvasView/InspectorView wrapping existing views
3. **FilmstripView** — floating strip, wire selection, remove LibrarySidebar, move toolbar buttons
4. **CanvasView** — dark viewport, shadow, before/after, dot grid, replace LivePreviewPanel
5. **InspectorView** — replace Form with ScrollView + custom sections, restyle incrementally
6. **PresetPreviewGrid** — rendered thumbnail previews (most complex new feature)
7. **Custom controls** — StyledSlider, StyledToggle, FormatPicker one at a time
8. **Polish** — ExifBar restyle, ExportBar + queue popover, empty states, drop zone

---

## Constraints

- No animations on state changes (toggle, selection, values) — instant. Only animate structural changes (layer reorder, add/remove).
- Preserve all keyboard shortcuts from `FramerCommands.swift`
- Arrow keys navigate filmstrip, Space toggles before/after
- ExifBar stays below canvas (not overlaid)
