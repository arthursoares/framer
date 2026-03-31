# Framer UI Redesign — Design Briefing

> **Audience:** Claude Code (or any developer implementing this in SwiftUI)
> **Scope:** `Sources/FramerApp/` — the SwiftUI macOS application only. No changes to `FramerCore` or `FramerCLI`.
> **Reference mockup:** `docs/design/framer-final-concept.html` (open in a browser to interact)

---

## Design Direction

**Concept: "Darkroom Editorial"** — Dark surfaces with warm analog accents. The photo is always the hero. Precision typography for data, humanist type for UI. Inspired by the app's origin story: vintage prints from a grandfather's photo box.

### What changes

1. **Layout:** 3-column `NavigationSplitView` → 2-column (canvas + inspector). The sidebar is eliminated. Photos are browsed via a horizontal filmstrip floating over the canvas.
2. **Presets:** Text list → visual thumbnail grid showing each preset applied to the current photo.
3. **Typography:** System defaults → Atkinson Hyperlegible for UI text, Source Code Pro (monospaced) for data values only.
4. **Color system:** System chrome → custom dark palette with warm amber accents.
5. **Canvas:** Plain `windowBackgroundColor` → dark surface with subtle warmth, photo floats with shadow.

### What stays the same

- All data models (`AppState`, `ProcessingConfig`, `CompositionLayer`, `Preset`, `ExportJob`, `PhotoItem`)
- `FramerCore` processing pipeline, `PreviewViewModel` rendering logic
- Layer composition system, EXIF extraction, export flow
- Menu commands (`FramerCommands.swift`)

---

## 1. Color System

Define in a shared `DesignTokens.swift` (or `Theme.swift`) using `Color` extensions:

```
Surface hierarchy (backgrounds):
  surface-0:  #0E0E10  — canvas / deepest background
  surface-1:  #141416  — panels (inspector, exif bar, titlebar)
  surface-2:  #1A1A1E  — expanded layer rows, hover states
  surface-3:  #222226  — input backgrounds, chips
  surface-4:  #2A2A2F  — slider tracks, badges

Text hierarchy:
  text-0:  #F0EDE8  — primary (layer names, photo filenames)
  text-1:  #B8B4AD  — secondary (EXIF values, button text)
  text-2:  #7D7A74  — tertiary (labels, camera model, controls)
  text-3:  #4E4C48  — quaternary (section headers, counts, disabled)

Accent (warm amber / safelight):
  accent:       #D4956A  — active states, selected borders
  accent-dim:   #A06840  — primary button backgrounds, toggle on-state
  accent-glow:  #D4956A @ 8% opacity  — selected item backgrounds
  accent-subtle:#D4956A @ 15% opacity — active toggle/pill backgrounds

Functional:
  success: #5E9F6D  — export complete
  error:   #C75D5D  — failed, delete hover

Border:
  default: white @ 6% opacity
  active:  white @ 12% opacity
```

**Implementation note:** Use `Color(hex:)` extension or define as `Color` constants. These replace all usage of `.windowBackgroundColor`, `.secondary`, `.tertiary`, `.quaternary` semantic colors in the current views.

---

## 2. Typography

**Font loading:** Bundle "Atkinson Hyperlegible Next" (variable weight, OFL license — download from Google Fonts). Source Code Pro can be loaded from the system or bundled.

**Assignment rules:**

| Context | Font | Weight | Size |
|---------|------|--------|------|
| Section headers (LIBRARY, LAYERS, OUTPUT, PRESETS) | Atkinson Hyperlegible | 600 (semibold) | 10pt, uppercase, 1.5pt letter-spacing |
| Layer names, photo filenames | Atkinson Hyperlegible | 450 (medium) | 12pt |
| Control labels (Amount, Style, Color) | Atkinson Hyperlegible | 400 | 11pt |
| Button text (Export Selected, Add layer) | Atkinson Hyperlegible | 600 | 11pt |
| Before/After toggle | Atkinson Hyperlegible | 600 | 10pt, uppercase |
| EXIF chips (ISO 400, f/2.8) | Source Code Pro | 400 | 10pt |
| Hex values (#F5F0E8) | Source Code Pro | 400 | 10pt |
| Template tokens ({{mon}} '{{year2}}) | Source Code Pro | 400 | 9pt |
| Layer badge summaries (solid · 5%) | Source Code Pro | 400 | 9pt |
| Numeric inputs | Source Code Pro | 400 | 10pt |
| Photo count, filmstrip count | Source Code Pro | 400 | 10pt |
| Titlebar "framer" brand | Source Code Pro | 400 | 12pt, lowercase |
| Frame caption (on rendered output) | Source Code Pro | 500 | 11pt, 3pt tracking |

**Rule of thumb:** If the text is a value, measurement, code token, or filename extension → mono. Everything else → Atkinson.

---

## 3. Layout Architecture

### Current
```
WindowGroup
  └─ NavigationSplitView(.balanced)
       ├─ sidebar:  LibrarySidebar  (200–300pt)
       ├─ content:  LivePreviewPanel
       └─ detail:   SettingsPanel   (260–400pt)
```

### New
```
WindowGroup
  └─ HStack(spacing: 0)
       ├─ CanvasView  (flexible, fills remaining)
       │    ├─ ZStack (viewport)
       │    │    ├─ preview image (centered, shadowed)
       │    │    ├─ BeforeAfterToggle (top-left, overlay)
       │    │    └─ FilmstripView (bottom, floating glass)
       │    └─ ExifBar (bottom, fixed)
       └─ InspectorView  (280pt fixed)
            ├─ ScrollView
            │    ├─ ActivePresetBanner
            │    ├─ PresetPreviewGrid
            │    ├─ LayerListSection (existing, restyled)
            │    └─ OutputSection
            └─ ExportBar (bottom, fixed)
```

**Minimum window size:** 900 × 650 (down from 1000 × 700 — we gained space by removing the sidebar column).

### ContentView.swift — rewrite

Replace `NavigationSplitView` with a simple `HStack`:

```swift
struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 0) {
            CanvasView()
            InspectorView()
                .frame(width: 280)
        }
        .frame(minWidth: 900, minHeight: 650)
    }
}
```

---

## 4. Component Specifications

### 4.1 CanvasView (replaces LivePreviewPanel)

**Structure:** `VStack(spacing: 0)` containing the viewport `ZStack`, the `ExifBar`, with the filmstrip overlaid.

**Viewport background:** `surface-0` with a subtle radial gradient — use a `RadialGradient` with `accent` at 2% opacity centered at (50%, 40%), fading to transparent. Optionally add a subtle dot grid pattern at 2.5% opacity (a tiled `Canvas` or `Image` view).

**Photo rendering:** The `previewImage` / `originalImage` from `PreviewViewModel` is displayed centered with:
- `aspectRatio(contentMode: .fit)`
- Padding: 32pt on all sides
- Shadow: `color: black @ 35%, radius: 16, y: 4` (outer), plus `color: black @ 25%, radius: 4, y: 1` (tight)

**Before/After toggle:** Overlay in the top-left corner (16pt inset). Two-segment pill with glass background (`.ultraThinMaterial`). "Before" shows `originalImage`, "After" shows `previewImage`. Use `@State private var showOriginal = false` — no animation on toggle (instant state change).

**Drop target:** Keep the existing `onDrop` handler. On `isTargeted`, show a dashed `accent-dim` border with `accent-glow` fill (2pt dashed `RoundedRectangle`, 10pt corner radius, 12pt inset from edges).

### 4.2 FilmstripView (new — replaces LibrarySidebar photo list)

**Position:** Overlaid at the bottom of the canvas viewport, 14pt from bottom edge, 14pt from left, stopping 294pt from right (to not overlap the inspector).

**Appearance:** Horizontal `ScrollView(.horizontal, showsIndicators: false)` inside a capsule-ish container with:
- Background: `black @ 60%` with `.ultraThinMaterial` (or `backdrop-filter` equivalent — use `.background(.ultraThinMaterial)` with overlay tint)
- Border: `white @ 7%`, 1pt
- Corner radius: 12pt
- Padding: 6pt vertical, 10pt horizontal

**Thumbnails:** Each is 48 × 34pt, corner radius 3pt, showing `AsyncThumbnail` (reuse existing thumbnail cache logic). Default `opacity: 0.55`, hover `0.85`, selected `1.0` with a 1.5pt `accent` border and `accent` glow shadow (8pt radius, 25% opacity).

**Layout:** `HStack(spacing: 3)` of film frames, followed by a divider (1pt wide, 20pt tall, `white @ 8%`), a count label (mono, 10pt, `text-3`), and a circular "+" add button (26pt diameter, dashed border).

**Selection:** Tap a frame → `appState.selectedItems = [item.id]`. Support multi-select via ⌘-click if desired (matches existing behavior).

**Toolbar:** Move the "Add Photos" (+) and "Remove Selected" (−) buttons to the titlebar area (right side), since the sidebar toolbar is gone.

### 4.3 PresetPreviewGrid (new — replaces SidebarPresetsSection)

**Position:** Inside the inspector, below the active preset banner.

**Layout:** `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6)` — 3 columns.

**Each preset card:**
- Container: `surface-3` background, `r-md` (6pt) corner radius, 2pt border (transparent default, `accent` when active)
- Image area: 4:3 aspect ratio showing a **rendered thumbnail** of the currently selected photo with that preset's `ProcessingConfig` applied
- Label: 9pt, `text-2`, centered, `surface-2` background strip at the bottom
- Active state: `accent` border, amber glow shadow, checkmark badge (14pt circle, top-right), label becomes `accent` on `accent-glow` background

**Rendering thumbnails:** This is the expensive part. Approach:
1. When `selectedPhoto` changes, kick off background renders for each preset using `FrameProcessor.previewImage()` at a reduced resolution (e.g., max 200px dimension).
2. Store results in a `@State private var presetPreviews: [UUID: NSImage]` dictionary keyed by preset ID.
3. Cancel in-flight renders when photo selection changes.
4. Show a placeholder (the photo's gradient/thumbnail from the filmstrip) while rendering.
5. Debounce: 200ms after photo selection change before starting renders.

**Last card:** "+ Save" card with dashed border, same dimensions as preset cards.

### 4.4 InspectorView (replaces SettingsPanel)

**Structure:** Same as current `SettingsPanel` but with custom styling instead of `.formStyle(.grouped)`.

**Background:** `surface-1`. Left border: 1pt, `white @ 6%`.

Replace the `Form { ... } .formStyle(.grouped)` with a plain `ScrollView` containing manually styled sections. The current `Form` applies system-styled grouped insets, separators, and backgrounds — all of that needs to go in favor of the custom dark theme.

**Sections:**
1. **ActivePresetBanner** — keep current logic, restyle: `accent-glow` background, `accent @ 12%` border, 7pt vertical / 10pt horizontal padding, 6pt corner radius. Icon + name (Atkinson 600, 11pt, accent color) + dismiss button.
2. **PresetPreviewGrid** (new, described above)
3. **LayerListSection** — keep existing layer composition logic and all layer parameter controls. Restyle:
   - Section header: Atkinson 600, 10pt, uppercase, `text-3`
   - Layer rows: custom `DisclosureGroup`-style with manual expand/collapse. Border goes from transparent → `border` on hover → `border` + `surface-2` background when expanded.
   - Layer header: reorder arrows + icon + name + badge (mono, `surface-4` pill) + delete button (hidden until hover) + chevron
   - Layer controls: indented 36pt from left, same control widgets as current but restyled
4. **OutputSection** — Format picker as two-pill segmented control (not native `Picker`), quality slider, strip EXIF toggle
5. **ExportBar** — pinned at bottom via `.safeAreaInset(edge: .bottom)`. Two buttons: "↑ Selected (N)" secondary, "↑ All (N)" primary (`accent-dim` background, `accent` border)

### 4.5 ExifBar (restyled)

Keep below the canvas viewport. `HStack` with:
- Camera model (Atkinson 11pt, `text-2`)
- EXIF chips in `Capsule` shapes (mono 10pt, `text-2`, `surface-3` background, 2pt vertical / 8pt horizontal padding)
- Spacer
- Caption label + value (label: Atkinson 9pt uppercase `text-3`, value: mono 11pt `text-1`)
- Info button (22pt circle, `border` stroke)

Background: `surface-1`, top border: 1pt `border`.

---

## 5. Custom Controls

The current implementation relies heavily on SwiftUI's native `Form`, `Picker`, `Toggle`, `Slider` styling. The redesign replaces these with custom-styled equivalents:

### Slider + Numeric Input
Current: `Slider(value:in:) + TextField` in an `HStack`
New: Same structure, but style the slider track as 3pt tall `surface-4` bar with a 12pt circular thumb (`text-1` fill, `surface-1` 2pt border). The `TextField` gets `surface-3` background, `border` stroke, mono font, right-aligned. Unit label (%, ×, mm) in mono 9pt `text-3`.

### Toggle
Current: Native `Toggle`
New: 32 × 18pt capsule. Off: `surface-4` background, 12pt `text-2` circle at left. On: `accent-dim` background, 12pt `text-0` circle at right.

### Color Picker + Hex Input
Keep the existing `ColorPickerWithHex` component structure. Restyle the hex input field with `surface-3` background and mono font.

### Segmented Picker (Format pills)
Replace native `Picker(.segmented)` with a custom `HStack` of buttons in a `surface-3` container. Active pill gets `accent-subtle` background and `accent` text color.

### Select / Dropdown
Use native `Picker` with `.menu` style — this is hard to custom-style on macOS. Alternatively, keep it as-is and let the system handle it (acceptable compromise since dropdowns are infrequent).

---

## 6. Files to Create / Modify

### New files
| File | Purpose |
|------|---------|
| `Sources/FramerApp/Theme/DesignTokens.swift` | Color constants, font helpers, spacing constants |
| `Sources/FramerApp/Canvas/CanvasView.swift` | Main canvas viewport (replaces LivePreviewPanel's role in layout) |
| `Sources/FramerApp/Canvas/FilmstripView.swift` | Horizontal floating photo browser |
| `Sources/FramerApp/Canvas/FilmstripThumbnail.swift` | Individual filmstrip frame (wraps AsyncThumbnail) |
| `Sources/FramerApp/Presets/PresetPreviewGrid.swift` | Visual preset picker with rendered thumbnails |
| `Sources/FramerApp/Presets/PresetPreviewCard.swift` | Individual preset thumbnail card |
| `Sources/FramerApp/Inspector/InspectorView.swift` | Right panel (replaces SettingsPanel) |
| `Sources/FramerApp/Inspector/ExportBar.swift` | Bottom export buttons |
| `Sources/FramerApp/Controls/StyledSlider.swift` | Custom slider + numeric input |
| `Sources/FramerApp/Controls/StyledToggle.swift` | Custom toggle switch |
| `Sources/FramerApp/Controls/FormatPicker.swift` | JPEG/PNG pill selector |

### Modified files
| File | Changes |
|------|---------|
| `ContentView.swift` | Replace `NavigationSplitView` with `HStack` layout |
| `App/FramerApp.swift` | Possibly adjust window sizing |
| `Editor/LayerListSection.swift` | Restyle only — replace `.formStyle` appearance with custom dark styling. Keep all layer logic intact. |
| `Editor/LivePreviewPanel.swift` | Extract rendering logic into `CanvasView`, possibly delete or fold into new file |
| `Library/PhotoThumbnailView.swift` | Keep `AsyncThumbnail` + thumbnail cache, remove sidebar-specific layout |
| `Library/LibrarySidebar.swift` | Delete (functionality moves to FilmstripView + titlebar) |
| `Presets/PresetManagerView.swift` | May delete or heavily refactor — replaced by PresetPreviewGrid |
| `Queue/ExportQueueView.swift` | Fold into InspectorView or keep as a sheet/popover |

### Resources
- Bundle `AtkinsonHyperlegible-Regular.ttf`, `AtkinsonHyperlegible-Bold.ttf` (and italic variants if desired)
- Register in Info.plist: `ATSApplicationFontsPath` or use `CTFontManagerRegisterFontsForURL` at app launch

---

## 7. Migration Strategy

Recommended order to minimize breakage:

1. **DesignTokens.swift** — define all colors and font helpers. No UI changes yet.
2. **ContentView.swift** — swap to `HStack` layout. Create stub `CanvasView` and `InspectorView` that just embed the existing `LivePreviewPanel` and `SettingsPanel`. App should still build and work identically.
3. **FilmstripView** — implement the floating horizontal strip. Wire up photo selection. Remove `LibrarySidebar` from the layout. Move add/remove toolbar buttons to the titlebar.
4. **CanvasView** — restyle the viewport (dark background, shadow, before/after toggle, dot grid). Replace `LivePreviewPanel` internals.
5. **InspectorView** — replace `Form/.formStyle(.grouped)` with custom `ScrollView` + manually styled sections. Start with existing controls, restyle incrementally.
6. **PresetPreviewGrid** — add rendered thumbnail previews. This is the most complex new feature due to background rendering.
7. **Custom controls** — swap native `Slider`, `Toggle`, `Picker` for styled versions one at a time.
8. **Polish** — ExifBar restyle, export bar, empty states, drop zone styling.

Each step should be a separate commit and the app should remain functional throughout.

---

## 8. Interaction Notes

- **No animations on state changes.** Use `withAnimation` only for structural changes (layer reorder, add/remove). All toggle, selection, and value changes should be instant. This is a deliberate design choice — the app should feel responsive and direct.
- **Filmstrip scrolling:** Use `ScrollViewReader` to scroll the selected thumbnail into view when selection changes programmatically (e.g., keyboard navigation).
- **Keyboard shortcuts:** Preserve all existing shortcuts from `FramerCommands.swift`. Arrow keys should navigate the filmstrip. Space bar could toggle before/after.
- **Export queue:** The sidebar had a dedicated queue section. In the new layout, show export progress as a small indicator in the ExportBar (inline progress bar or count), with a popover or sheet for full queue details on click.

---

## 9. Reference

The interactive HTML mockup (`docs/design/framer-final-concept.html`) demonstrates:
- Filmstrip thumbnail selection (click frames at bottom)
- Preset preview grid with live thumbnail sync (click a filmstrip frame → presets update)
- Layer expand/collapse
- Before/After toggle
- Format pill switching
- All color tokens and typography in context

Open it in a browser and inspect elements to see exact spacing, sizing, and color values.
