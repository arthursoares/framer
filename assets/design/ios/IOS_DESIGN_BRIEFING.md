# Framer iOS App — Design & Implementation Briefing

> **Audience:** Claude Code (or any developer implementing this in SwiftUI for iOS)
> **Reference mockup:** `docs/design/framer-ios-concept.html` (open in a browser to interact with all three screens)
> **Relationship to macOS app:** Shares `FramerCore` library. Separate UI target, same processing engine.

---

## 1. Product Concept

Framer iOS brings the full layer-based photo framing workflow to iPhone. It is not a simplified mobile port — layers, presets, drag-to-reorder, and batch export are all present. The interaction model adapts to touch: presets are the fast path (swipe and tap), layers are one tap deeper (tap a row to drill into full-screen controls).

**Core loop:** Pick photos → swipe presets to preview → tap to apply → share. Power users tap "Layers" to build custom stacks with the same composition engine as the macOS app.

---

## 2. FramerCore Platform Compatibility

`FramerCore` is nearly cross-platform already. Only two files reference AppKit:

### Files requiring changes

| File | Issue | Fix |
|------|-------|-----|
| `Processing/FrameProcessor.swift` | `import AppKit`, returns `NSImage` from `previewImage()` | Change `previewImage()` to return `CGImage`. Move `NSImage`/`UIImage` conversion to the app layer. Use `#if canImport(AppKit)` / `#if canImport(UIKit)` if a convenience method is desired. |
| `Presets/YAMLConfig.swift` | `import AppKit` (unused — no AppKit types referenced) | Remove the import. |

### Files that are already cross-platform (no changes needed)

All processing: `BorderRenderer.swift`, `CaptionRenderer.swift`, `DitherRenderer.swift`, `ColorExtractor.swift`, `TextureFrameProvider.swift` — these use `CoreGraphics`, `CoreText`, `ImageIO`, and `Accelerate` only.

All models: `CompositionLayer.swift`, `ProcessingConfig.swift`, `ExifData.swift`, `Preset.swift` — `Foundation` and `CoreGraphics` only.

`PresetStore.swift` — `Foundation` and `CryptoKit` only.

`EXIFReader.swift`, `MetadataWriter.swift` — `ImageIO` only.

### Package.swift changes

```swift
platforms: [.macOS(.v14), .iOS(.v17)],
```

Add the iOS app target in `project.yml` or create a new Xcode project. The app target depends on the `FramerCore` library product.

### Texture assets

The `assets/textures/` folder (overlay images for dust, light leaks, etc.) needs to be bundled in the iOS target as well. Ensure the `TextureFrameProvider` can resolve bundle paths on iOS — it currently uses `Bundle.main` which works on both platforms.

---

## 3. Design System

Same darkroom palette as the macOS app. Defined in a shared `DesignTokens.swift`:

```
Surfaces: #0E0E10, #141416, #1A1A1E, #222226, #2A2A2F
Text:     #F0EDE8, #B8B4AD, #7D7A74, #4E4C48
Accent:   #D4956A (amber), #A06840 (dim), 8%/15% opacity variants
Success:  #5E9F6D   Error: #C75D5D
```

### Typography

- **Atkinson Hyperlegible Next** — all UI text (nav titles, labels, buttons, layer names)
- **Source Code Pro** — EXIF values, hex colors, template tokens, layer summaries, numeric readouts

Bundle both font families in the iOS app target. Register via `Info.plist` → `UIAppFonts`.

### Corner radii

iOS uses slightly larger radii than the macOS design: `r-sm: 4pt`, `r-md: 8pt`, `r-lg: 14pt`. Grouped controls (iOS settings-style rows) use 14pt corners.

---

## 4. Screen Architecture

```
App
  └─ NavigationStack
       ├─ EditorView (root)
       │    ├─ preview area (framed photo, full width)
       │    ├─ bottom panel
       │    │    ├─ mode tabs: [Presets] [Layers]
       │    │    ├─ PresetStrip (horizontal scroll, live thumbnails)
       │    │    ├─ LayerStrip (vertical list, drag-to-reorder)
       │    │    └─ action bar: [Photos] [Share]
       │    └─ SavePresetSheet (presented as .sheet)
       ├─ LayerDetailView (pushed via NavigationLink)
       │    ├─ mini live preview
       │    ├─ grouped controls (style, sliders, color, toggles)
       │    └─ delete button
       └─ PhotoPickerView (presented via PHPickerViewController or .sheet)
```

### Navigation model

- `NavigationStack` with path-based navigation
- Editor is the root view — always visible
- Layer detail pushes onto the stack (back button = "‹ Layers")
- Photo picker is presented modally (`.sheet` or `.fullScreenCover`)
- Save preset is a bottom sheet (`.sheet(presentationDetents: [.medium])`)

---

## 5. Screen Specifications

### 5.1 EditorView (main screen)

**Nav bar:** Leading "‹ Photos" (opens picker), center title (current filename, e.g., "DSC_0234"), trailing "Done" (dismisses to a potential parent or does nothing if root).

**Preview area:** Fills all available space above the bottom panel.
- Background: `surface-0` with subtle radial gradient (accent at 2% opacity, centered at 50%/40%)
- The rendered preview from `FrameProcessor` is displayed with `Image(uiImage:).resizable().aspectRatio(contentMode: .fit)` with 20pt horizontal padding
- Shadow: `color: black 40%, radius: 10, y: 4`
- Photo counter badge in top-right: "1 / 8" in a capsule (`surface-0 @ 60%` with blur, mono 11pt, `text-2`)

**Long-press for original:** `onLongPressGesture` shows `originalImage` (without frame) while held, reverts to `previewImage` on release. No animation — instant swap.

**Swipe to navigate:** `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` wrapping the preview, or a `DragGesture` that changes `selectedIndex`. Swiping left/right moves through the selected photos. Update the counter badge.

**Bottom panel:** Fixed at the bottom. Contains:

#### Mode tabs

`HStack` of two buttons: "Presets" and "Layers". Active tab has `accent` text and a 2pt bottom border in `accent`. Switching tabs shows/hides the preset strip or layer strip.

#### PresetStrip (visible when Presets tab active)

Horizontal `ScrollView(.horizontal, showsIndicators: false)` containing preset cards.

Each card:
- 72pt wide
- 4:3 aspect ratio image area showing a rendered thumbnail of the current photo with that preset applied
- 2pt border: transparent default, `accent` when selected (with glow shadow)
- Checkmark badge (14pt circle, `accent` background) on active preset
- Name below: 10pt, `text-3` (default), `accent` (active)
- Last card: "+" save card with dashed border, `surface-3` background, "+" icon in `text-3`

**Preset thumbnail rendering:** Same approach as macOS — background renders at ~200px max dimension using `FrameProcessor`. Cache in a `[UUID: UIImage]` dictionary. Debounce 200ms after photo change. Cancel on photo change.

**Tapping "+" card:** Presents `SavePresetSheet` as a `.sheet(presentationDetents: [.medium])`.

#### LayerStrip (visible when Layers tab active)

Vertical list of layer rows. Each row:
- Grip handle (☰) for drag-to-reorder — use `List` with `.onMove` modifier or `ForEach` with `.onDrag/.onDrop`
- Layer icon (↔, ☐, T, ✦, ◌)
- Name (Atkinson 13pt, 500 weight, `text-0`)
- Summary line (mono 10pt, `text-3`) showing current values: `solid · #F5F0E8 · 5%`, `overlay · 30%`, `— {{mon}} '{{year2}} —`
- Toggle switch (on/off for layer enable/disable)
- Chevron (›) indicating tap to drill down
- Tap → push `LayerDetailView` onto the NavigationStack

**"+ Add Layer" row** at the bottom: opens an action sheet or menu listing available layer types (Padding, Border, Canvas, Resize, Orientation, Caption, Dither, Frame Overlay, Dust & Scratches, Light Leak, Wet Plate).

**Drag-to-reorder:** The grip handle initiates drag. Use `onMove(perform:)` on the `ForEach` inside a `List`, or implement with `DragGesture` for custom styling. The layer order directly maps to `appState.currentConfig.layers` array order.

#### Action bar

Two buttons side by side:
- "Photos" — secondary style (`surface-3` background, `text-1` text, 14pt corner radius). Opens the photo picker.
- "Share" — primary style (`accent` background, `surface-0` text, 14pt corner radius). Triggers `UIActivityViewController` / `ShareLink` with the processed image.

### 5.2 LayerDetailView (pushed from layer tap)

**Nav bar:** "‹ Layers" back button, trailing "Done" (pops back).

**Mini preview:** 180pt tall rounded rectangle at the top showing the current rendered preview. Updates live as the user adjusts controls. Use the existing `PreviewViewModel` approach — debounce 150ms.

**Layer header:** Icon (in a 36pt rounded square, `surface-3` background) + layer name (22pt, 700 weight).

**Controls:** iOS grouped-style rows with `surface-2` background and 14pt corner radius:

| Control type | Implementation |
|-------------|----------------|
| Segmented picker (e.g., Style: Solid / Instagram) | Custom `HStack` of buttons in a `surface-3` container. Active button gets `surface-4` background + shadow. |
| Slider (e.g., Border Width: 5%) | Header row with label + mono value, followed by a `Slider` with iOS-style large thumb (28pt). Style the track as 4pt tall, `surface-4` color. |
| Color picker | Row with swatch (32pt rounded square) + hex value + chevron. Tap opens `ColorPicker` sheet. |
| Text input (e.g., Caption template) | Standard `TextField` with `surface-2` background, 14pt radius, mono font for template tokens. |
| Toggle (e.g., Bold, Italic, Enabled) | Native `Toggle` restyled, or custom capsule toggle: 36×20pt, `surface-4` off / `accent-dim` on. |
| Dropdown (e.g., Algorithm, Blend mode) | `Picker` with `.menu` style — native iOS menu presentation. |

**Delete button:** Full-width, `surface-2` background, `error` text color, 14pt radius. Confirmation alert before deletion.

### 5.3 SavePresetSheet

Presented as `.sheet(presentationDetents: [.medium])` from the editor.

**Structure:**
- Drag handle (36 × 5pt pill, `surface-4`, centered, 8pt from top)
- Header: "Cancel" (left, `text-2`) / "Save Preset" (center, 600 weight) / "Save" (right, `accent`, 600 weight)
- Preview: rounded container (`surface-2`, 14pt radius) showing a mini framed thumbnail + "Current settings" label
- Name input: text field with `surface-2` background, 14pt radius, 16pt font, placeholder "My Preset"
- Layer summary: chips showing included layers (`Padding 4%`, `Border 5%`, `Caption`, `Dust 30%`) in a flow layout

**Save action:** Creates a new `Preset` with the current `ProcessingConfig`, saves via `PresetStore`, dismisses the sheet, selects the new preset in the strip, scrolls it into view.

### 5.4 PhotoPickerView

Use `PHPickerViewController` wrapped in `UIViewControllerRepresentable`, or PhotosUI's `PhotosPicker` (iOS 16+).

**Configuration:**
- `filter: .images`
- `selectionLimit: 0` (unlimited)
- `selection: .ordered` (preserves selection order)

**After selection:** Convert `PHPickerResult` items to URLs or `CGImage`s. Store as `PhotoItem` objects in `appState.library`. Navigate back to editor with first photo selected.

**Alternative approach:** If you want the custom dark-themed grid shown in the mockup, implement a custom picker using `PHFetchResult` from the Photos framework. This gives full control over styling but requires `NSPhotoLibraryUsageDescription` permission. The mockup shows a 4-column grid with selection checkmarks.

---

## 6. Data Flow

### AppState (shared with macOS, adapted for iOS)

```swift
@MainActor
@Observable
final class AppState {
    var library: [PhotoItem] = []
    var selectedIndex: Int = 0                // replaces selectedItems Set
    var currentConfig: ProcessingConfig = .default
    var activePresetName: String?
    var presets: [Preset] = []
    var presetStore = PresetStore()
    
    var selectedPhoto: PhotoItem? {
        guard library.indices.contains(selectedIndex) else { return nil }
        return library[selectedIndex]
    }
    
    // Navigation / UI state
    var activeTab: BottomTab = .presets       // .presets or .layers
    var showingSavePresetSheet = false
    var showingPhotosPicker = false
}
```

**Key difference from macOS:** `selectedIndex` (single Int) replaces `selectedItems` (Set of UUIDs). Mobile workflow is single-photo-at-a-time — swipe left/right to navigate. Batch export works on the entire library.

### PreviewViewModel (reuse from macOS)

Same `PreviewViewModel` with one change: return `UIImage` instead of `NSImage`, or work with `CGImage` and let the view convert:

```swift
var previewImage: UIImage?   // was NSImage?
var originalImage: UIImage?  // was NSImage?
```

### Preset preview rendering

```swift
@MainActor
@Observable
final class PresetPreviewCache {
    var previews: [UUID: UIImage] = [:]
    private var renderTask: Task<Void, Never>?
    private let processor = FrameProcessor()
    
    func regenerate(for photo: PhotoItem, presets: [Preset]) {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            for preset in presets {
                guard !Task.isCancelled else { return }
                if let cgImage = try? await processor.previewCGImage(
                    for: photo.url, config: preset.config, maxDimension: 200
                ) {
                    previews[preset.id] = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}
```

---

## 7. Project Structure

### New Xcode target

Create an iOS app target `FramerMobile` (or `FramerApp-iOS`) in the Xcode project. It depends on the `FramerCore` library product from the Swift package.

### File structure

```
Sources/
  FramerCore/          (shared — already exists)
  FramerCLI/           (macOS only — already exists)
  FramerApp/           (macOS app — already exists)
  FramerMobile/        (new iOS app)
    App/
      FramerMobileApp.swift
      AppState+iOS.swift       (iOS-specific AppState extensions)
    Theme/
      DesignTokens.swift       (shared with macOS or duplicated)
    Editor/
      EditorView.swift         (main screen)
      PreviewArea.swift        (photo display + gestures)
      BottomPanel.swift        (tabs + preset strip + layer strip)
    Presets/
      PresetStrip.swift        (horizontal scroll)
      PresetCard.swift         (individual thumbnail)
      SavePresetSheet.swift    (bottom sheet)
    Layers/
      LayerStrip.swift         (compact list with drag reorder)
      LayerRow.swift           (single layer row)
      LayerDetailView.swift    (full-screen editing)
    Picker/
      PhotoPickerView.swift    (PHPicker wrapper)
    Controls/
      StyledSlider.swift       (iOS-style slider)
      StyledToggle.swift       (custom toggle)
      SegmentedControl.swift   (custom segmented picker)
      GroupedControlRow.swift   (iOS settings-style row)
    Preview/
      PreviewViewModel+iOS.swift  (UIImage conversion)
      PresetPreviewCache.swift    (background thumbnail rendering)
    Export/
      ShareManager.swift       (UIActivityViewController integration)
```

### Info.plist additions

```xml
<key>UIAppFonts</key>
<array>
    <string>AtkinsonHyperlegibleNext-Regular.ttf</string>
    <string>AtkinsonHyperlegibleNext-Medium.ttf</string>
    <string>AtkinsonHyperlegibleNext-SemiBold.ttf</string>
    <string>AtkinsonHyperlegibleNext-Bold.ttf</string>
    <string>AtkinsonHyperlegibleNext-Italic.ttf</string>
    <string>SourceCodePro-Regular.ttf</string>
    <string>SourceCodePro-Medium.ttf</string>
    <string>SourceCodePro-SemiBold.ttf</string>
</array>
<key>NSPhotoLibraryUsageDescription</key>
<string>Framer needs access to your photo library to select and process photos.</string>
```

---

## 8. Export / Share

### Primary: Share sheet

```swift
func shareProcessedImage() async {
    guard let photo = appState.selectedPhoto else { return }
    let processor = FrameProcessor()
    // Render at full resolution
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jpg")
    try? await processor.process(
        input: photo.url,
        output: tempURL,
        config: appState.currentConfig
    )
    let activityVC = UIActivityViewController(
        activityItems: [tempURL],
        applicationActivities: nil
    )
    // Present activityVC
}
```

### Batch export

"Export All" could be a secondary action (long-press Share, or a menu option). Processes all photos in `library` and either:
- Saves all to Photos library via `PHPhotoLibrary`
- Exports to Files via `UIDocumentPickerViewController`

Show progress via a sheet with a `ProgressView`.

---

## 9. Gestures & Interactions

| Gesture | Action |
|---------|--------|
| Tap preset card | Apply preset, update preview |
| Tap layer row | Push LayerDetailView |
| Drag layer grip handle | Reorder layers |
| Tap layer toggle | Enable/disable layer |
| Swipe left/right on preview | Navigate photos |
| Long-press preview | Show original (un-framed) photo |
| Tap "+" preset card | Present SavePresetSheet |
| Tap "+" Add Layer row | Present layer type menu |
| Tap Share | Present UIActivityViewController |
| Tap Photos | Present photo picker |

**No animations on value changes.** Sliders, toggles, and preset selection update instantly. Only use animation for structural changes: sheet presentation, navigation push/pop, layer reorder.

---

## 10. Implementation Order

1. **FramerCore cross-platform fix** — change `previewImage()` to return `CGImage`, remove unused `import AppKit` from `YAMLConfig.swift`, add `.iOS(.v17)` to `Package.swift` platforms. Verify `swift build` still passes for macOS. (~30 min)

2. **Create iOS target** — new Xcode target, add FramerCore dependency, register fonts, add photo library permission. Stub `FramerMobileApp.swift` with a basic `WindowGroup`. (~30 min)

3. **DesignTokens + theme** — port the color/font constants. Can share with macOS target or duplicate. (~15 min)

4. **EditorView scaffold** — nav bar + placeholder preview area + bottom panel with tabs. Wire up `AppState`. Get the basic structure rendering. (~1 hr)

5. **Photo picker** — integrate `PHPickerViewController`. Load selected photos into `appState.library`. (~30 min)

6. **Preview rendering** — connect `PreviewViewModel` to display the framed photo. Wire up photo navigation (swipe or index change). Long-press for original. (~1 hr)

7. **PresetStrip** — horizontal scroll with cards. Tap to apply. Wire up to `appState.currentConfig` and `appState.presets`. (~1 hr)

8. **Preset preview thumbnails** — background rendering with `PresetPreviewCache`. This is the most complex piece — get the cancellation and caching right. (~2 hr)

9. **LayerStrip** — vertical list with summaries, toggles, and drag-to-reorder. (~1 hr)

10. **LayerDetailView** — full-screen controls for each layer type. Port the control layout from `LayerListSection.swift` (the logic is the same, just restyled for iOS grouped controls). (~3 hr — largest task due to the number of layer types)

11. **SavePresetSheet** — bottom sheet with name input and save action. (~30 min)

12. **Share/export** — `UIActivityViewController` integration, batch export option. (~1 hr)

13. **Polish** — empty states, drop shadows, loading indicators, error handling, keyboard avoidance on text inputs. (~2 hr)

Each step should be a separate commit and the app should remain buildable throughout.

---

## 11. Reference

The interactive HTML mockup (`docs/design/framer-ios-concept.html`) demonstrates all three screens:

- **Editor:** tap "Presets" / "Layers" tabs to switch, tap preset cards, tap the "+" save card, long-press the preview
- **Layer Detail:** tap any layer row → pushes detail view with slider controls
- **Photo Picker:** tap "Photos" button → shows grid with multi-select

Open it in a browser and resize to ~393px wide to see the iPhone proportions.
