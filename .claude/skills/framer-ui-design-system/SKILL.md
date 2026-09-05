---
name: framer-ui-design-system
description: >
  Load when touching ANY macOS SwiftUI surface in Sources/FramerApp/ — the inspector/sidebar,
  LayerListSection.swift, Sidebar/ primitives, Theme/DesignTokens.swift, Controls/ — or when
  choosing colors, fonts, spacing, picker styles, or adding a new layer-editor control. Also load
  when a SidebarHarmonySnapshotTests SHA-256 baseline shifts, a slider overlaps a text field, a
  picker "snaps back", a color picker shows a stray label chip, or someone proposes "simplifying"
  the sidebar result-builders. Owns the Darkroom Editorial design tokens and the sidebar component
  grammar with its non-negotiables.
---

# Framer UI Design System — Darkroom Editorial + the Sidebar Grammar

This skill is the binding UI law for the macOS app (`Sources/FramerApp/`). It has two halves:
the **Darkroom Editorial** token system (colors, type, interaction rules) and the **sidebar
component grammar** (the primitives every inspector control must be built from, plus nine
non-negotiable rules, each paid for with a real incident).

All facts verified 2026-07-09 against main @ 48d85a5 unless noted otherwise.

## When NOT to use this skill

| You are doing... | Go to |
|---|---|
| Refreshing/diagnosing snapshot-test hashes, test-writing conventions | **framer-validation-and-qa** |
| Building/running the app, xcodegen traps, why `xcodebuild test` fails | **framer-build-and-env** |
| GPU effect shaders, Metal, uniforms | **framer-metal-pipeline-reference** |
| Which parameters/capability flags an effect exposes | **framer-config-and-flags** |
| Full incident histories referenced here by name | **framer-failure-archaeology** |
| Why the architecture is shaped this way (e.g. CPU/GPU parity question) | **framer-architecture-contract** |
| Measuring rendered output instead of eyeballing | **framer-diagnostics-and-proof** |

---

## Part 1 — Darkroom Editorial tokens

Concept: dark surfaces, warm analog amber, the photo is the hero. Spec of record:
`assets/design/DESIGN_BRIEFING.md`. Implementation of record:
`Sources/FramerApp/Theme/DesignTokens.swift` — always use these named constants, never raw hex
or system semantic colors (`.secondary`, `.windowBackgroundColor`, etc.).

### Surfaces (5 levels) — `Color.surface0...surface4`

| Token | Hex | Use |
|---|---|---|
| `surface0` | `#0E0E10` | canvas / deepest background |
| `surface1` | `#141416` | panels (inspector, exif bar, titlebar) |
| `surface2` | `#1A1A1E` | expanded layer rows, hover states |
| `surface3` | `#222226` | input backgrounds, chips |
| `surface4` | `#2A2A2F` | slider tracks, badges |

### Text (4 levels) — `Color.text0...text3`

| Token | Hex | Use |
|---|---|---|
| `text0` | `#F0EDE8` | primary (layer names, filenames) |
| `text1` | `#B8B4AD` | secondary (EXIF values, button text) |
| `text2` | `#A6A198` | secondary control labels (contrast update 2026-09-05) |
| `text3` | `#96928B` | quiet section headers, counts, and readouts (contrast update 2026-09-05) |

The 2026-09-05 UI/UX pass brightened these two warm text tokens on both
platforms. Their normal-text contrast is at least 4.61:1 across the five app
surfaces. The old briefing values are historical; runtime contrast tests guard
the current tokens. This does not imply every opacity-modified or disabled
control has the same contrast, or that the entire interface is certified.

### Accent + functional + border

- `accent` `#D4956A` (warm amber "safelight") — active states, selected borders
- `accentDim` `#A06840` — primary buttons, toggle on-state; `accentGlow` = accent @ 8%;
  `accentSubtle` = accent @ 15%
- `success` `#5E9F6D`, `error` `#C75D5D`
- `borderDefault` = white @ 6%, `borderActive` = white @ 12%

### Typography — the one rule

> **If the text is a value, measurement, code token, or filename → Source Code Pro (mono).
> Everything else → Atkinson Hyperlegible.**

Use the `AppFont` helpers in `DesignTokens.swift`, never `.custom(...)` inline:
`AppFont.body(size, weight:)` (Atkinson Hyperlegible Next) and `AppFont.mono(size, weight:)`
(Source Code Pro), plus named presets: `sectionHeader` (body 10 semibold, uppercase + 1.5
tracking applied at call site), `layerName` (body 12 medium), `controlLabel` (body 11),
`buttonText` (body 11 semibold), `exifChip`/`hexValue`/`numericInput`/`photoCount` (mono 10),
`templateToken`/`badgeSummary` (mono 9), `brandTitle` (mono 12).

Spacing tokens: `Spacing.xs/sm/md/lg/xl` = 4/6/10/14/16. Corner radii:
`CornerRadius.sm/md/lg` = 4/6/10. Inside the sidebar, prefer `SidebarMetrics` tokens (Part 2)
over `Spacing` — the sidebar has its own rhythm.

### Interaction law: no animations on state changes

`assets/design/DESIGN_BRIEFING.md` §8: **use `withAnimation` only for structural changes**
(layer reorder, add/remove, section collapse). Toggles, selection, and value changes are
instant. This is deliberate — the app should feel direct.

### Corrections to the briefing (the briefing is NOT updated; trust these)

1. **Inspector width is NOT 280pt fixed.** The briefing (§3) and its code sample say
   `.frame(width: 280)`. Reality: the inspector is user-resizable inside an `NSSplitView`
   (`InspectorSplitView` in `Sources/FramerApp/ContentView.swift`), clamped by
   `SidebarLayoutPolicy.default` = **min 300 / ideal 350 / max 520** —
   `Sources/FramerApp/Sidebar/SidebarLayoutPolicy.swift:9-13`. Note: the sidebar-harmony
   notepad and older plan docs say "304/320/352"; that band was superseded on 2026-04-15 by
   commit c83b509 ("refactor(sidebar): tighten parameter spacing and width defaults").
2. **The mockup path in the briefing is wrong.** It says `docs/design/framer-final-concept.html`;
   the actual file is `assets/design/framer-final-concept.html` (the iOS one is
   `assets/design/ios/framer-ios-concept.html`). `docs/design/` does not exist.

Staleness of docs generally is tracked in **framer-docs-and-writing**.

---

## Part 2 — The sidebar grammar

Everything in the inspector is composed from a small set of primitives in
`Sources/FramerApp/Sidebar/` (plus `Sources/FramerApp/Controls/`). Never hand-roll an
HStack-label-plus-control row; pick the primitive that matches the shape.

### The primitive catalog

| Primitive (file in `Sources/FramerApp/Sidebar/`) | What it is FOR |
|---|---|
| `SidebarShell` | The whole inspector chassis: ScrollView, `surface1` background, leading 1pt border, bottom `safeAreaInset` footer, min/ideal/max width frame. Injects metrics into the environment. One per sidebar. |
| `SidebarSection` | Header (uppercase eyebrow, `AppFont.sectionHeader`, `text3`) + content stack. Header-less convenience init exists for sections that own their own header (Layers). |
| `CollapsibleSidebarSection` | `SidebarSection` with a chevron and collapse persistence (used by Presets, persisted via `@AppStorage("sidebarPresetsSectionExpanded")` in `InspectorView.swift:28`). Content is clipped during the collapse transition. |
| `SidebarControlRow` | THE canonical 3-column row: 104pt label / flexible content / trailing value block. Content gets `.clipShape(Rectangle())` (see non-negotiable 3). Trailing slot is a result-builder (see non-negotiable 2). |
| `SidebarCompoundControlBlock` | Two tightly-coupled rows (mode/value, width/height, offset X/Y) stacked at zero gap with a 1pt divider that renders ONLY when the secondary has runtime content. |
| `SidebarTrailingUnitCluster` | Editable trailing block: `[55pt field][24pt unit suffix]`. Lives in a `SidebarControlRow`'s `trailingValue` slot. |
| `SidebarTrailingReadoutCluster` | Read-only counterpart; same widths so editable and readout rows align (non-negotiable 5). |
| `SidebarFullWidthRow` | Title above content that can't fit the 3-column grid (previews, strips, flows); constrains content to `metrics.containedPreviewMaxWidth`. |
| `SidebarPreviewStrip` | Horizontally scrolling tile strip (Overlay library, LUT library). Optional `tileWidth`/`tileHeight` for tall tiles. |
| `SidebarPaletteEditor` | Swatch + hex + delete rows for editable palettes (Dither). Maintains stable per-swatch UUID identities so deleting index N doesn't retarget the other pickers' bindings. |
| `SidebarChipFlow` (+ `SidebarFlowLayout`) | Wrapping chip grid (caption template tokens, ASCII ramp). Requires `Data.Element: Hashable` and keys by `\.self` so only changed chips rebuild. |
| `LayerPanelRow` | The layer-list row chassis. Its state comes from the pure `LayerPanelRowStateResolver` returning separate chassis (`hover/expanded/dragging/dropTarget`) and availability (`default/disabled`) states. |
| `SidebarStateStyle` / `SidebarState` (in `SidebarStateStyle.swift` / `SidebarLayoutPolicy.swift`) | The state vocabulary (`default, hover, expanded, selectedCurrent, disabled, dragging, dropTarget, focus`) and its background/border/foreground styling. Preset cards and export footer reuse it — no parallel button dialects. |

Controls (in `Sources/FramerApp/Controls/`): `StyledSlider` (slider + numeric field, both routes
snap through `StyledSliderValueResolver.constrain` so typed entry can't bypass range/step),
`StyledUnitSlider` (convenience wrapper adding the 24pt unit column), `StyledToggle` (backed by a
real `Toggle` with hidden text label so VoiceOver announces the name), `ColorPickerWithHex`,
`FormatPicker`. The canonical slider ROW shape is `DenseSliderControlRow` (defined in
`Sources/FramerApp/Editor/LayerListSection.swift:3194`): `Slider` in the content slot,
`SidebarTrailingUnitCluster { TextField }` in the trailing slot, sharing one snapped binding.

### SidebarMetrics — the single token vocabulary

`Sources/FramerApp/Sidebar/SidebarMetrics.swift`. Every sidebar dimension comes from here; do not
introduce parallel spacing namespaces (pass 2 of the sidebar-harmony effort existed largely to
delete one, `SimpleLayerEditorLayout`). Defaults as of 2026-07-09:

| Token | Value | Meaning |
|---|---|---|
| `outerInset` | 12 | shell padding; also the label-column left edge and divider inset |
| `rowGap` | 16 | gap between sections in the shell |
| `expandedBodyInset` | 6 | header-to-content gap inside a section |
| `controlRowMinHeight` | 30 | min height of a `SidebarControlRow` |
| `controlLabelWidth` | 104 | the label column |
| `controlColumnSpacing` | 10 | gap between label / content / trailing |
| `controlTrailingValueWidth` | 48 | min width of the trailing block |
| `controlValueFieldWidth` | 55 | numeric field width |
| `controlReadoutWidth` | 55 | read-only value width — must equal the above |
| `controlUnitSuffixWidth` | 24 | the unit column ("px", "%", "mm") |
| `controlTrailingClusterSpacing` | 6 | gap inside a trailing cluster |
| `controlSegmentedModeWidth` | 80 | fixed width for short 2-option segmented pickers |
| `controlUnitPickerWidth` | 100 | fixed width for unit segmented pickers |
| `controlStackSpacing` | 0 | compound-block stacking |
| `fullWidthRowHorizontalInset` | 12 | full-width row inset; feeds `containedPreviewMaxWidth` = idealWidth − 2×12 |

Width clamping delegates to `SidebarLayoutPolicy` (300/350/520) so the width band lives in
exactly one place. Locked by `Tests/FramerAppTests/SidebarMetricsTests.swift` and
`SidebarLayoutPolicyTests.swift`.

### The segmented-vs-menu picker budget rule

At the 300pt minimum sidebar width, a control row's content region is
300 − 2×12 (outerInset) − 104 (label) − 10 (column spacing) = **162pt**. If a segmented
picker's options can't fit 162pt, use `.pickerStyle(.menu)` instead. This is why Orientation
Target (Portrait/Landscape/Square) and Overlay Category (Frames/Dust/Light Leaks/Wet Plate)
are `.menu` pickers, while short fixed-width segmented pickers survive: Thickness Mode px/%
(80pt `controlSegmentedModeWidth`), Size Mode, and physical Unit (100pt
`controlUnitPickerWidth`) — see `LayerListSection.swift:1686/1842/1921`.

---

## Part 3 — Non-negotiables (each one has a scar)

### 1. Environment threading: `envMetrics` + optional `overrideMetrics`

Every sidebar primitive MUST follow this exact pattern (see `SidebarControlRow.swift:84-106`):

```swift
@Environment(\.sidebarMetrics) private var envMetrics
private let overrideMetrics: SidebarMetrics?
private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }
// initializer takes: metrics: SidebarMetrics? = nil
```

The environment key is `\.sidebarMetrics` (`SidebarMetricsEnvironment.swift`). **Incident:**
pass-1 primitives each constructed their own `SidebarMetrics()`, so shell-level overrides
"fell on the floor" silently — environment threading in SwiftUI is invisible unless the
primitive explicitly reads it. Guarded by `Tests/FramerAppTests/SidebarEnvironmentTests.swift`
(`test_shellMetricsReachDescendants`). A new primitive that hardcodes `SidebarMetrics()`
reintroduces the bug without any compile error.

### 2. The result-builders MUST NOT be replaced with generic `View` params

`SidebarControlRowTrailingValueContent` and `SidebarCompoundControlBlockSecondaryContent`
(hand-rolled result-builders with a runtime `.absent` case) look like over-engineering. They
are not. **Incident:** a swift-expert reviewer flagged them as "solving a non-problem" and
suggested plain `TrailingValue: View` generics. The refactor was attempted; a snapshot test
failed; it was reverted. Why: `trailingValue: { if flag { field } }` resolves to
`_ConditionalContent<Field, EmptyView>` — a type that a compile-time `== EmptyView` check never
matches — so the row reserved trailing space / the block drew a divider above nothing whenever
the conditional's false branch was live. The runtime `.absent` case is the ONLY reliable way to
distinguish "no trailing closure at all" from "closure whose current branch is empty". The full
rationale is in the doc comments at `SidebarControlRow.swift:23-34` and
`SidebarCompoundControlBlock.swift:3-10`. If you touch these, the snapshot suite will catch
you — read the pixels before arguing with it.

### 3. NSSlider bleeds past its frame: keep the clip + trailing pad

macOS `Slider` is backed by AppKit's `NSSlider`, which rasterises its track/knob to — and
slightly past — its layout frame via layer-level drawing. **Incident:** slider tracks visibly
touched/overlapped the trailing field's rounded rect on narrow sidebars.
Fix (both parts live in `SidebarControlRow.swift:119-136`): `.clipShape(Rectangle())` on the
content slot (structural) plus an extra `controlColumnSpacing` trailing pad when a trailing
value is present (belt + suspenders). Never remove either; never host a bare `Slider` next to
a field outside `SidebarControlRow`/`DenseSliderControlRow`.

### 4. Bind layers by `layer.id`, never by index

**Incident:** index-keyed bindings captured the index at creation time; SwiftUI reads a detail
view's binding once AFTER its row is deleted or reordered (before teardown), so
`layers[staleIdx]` crashed out of bounds. The canonical pattern is `binding(for: layer)` in
`LayerListSection.swift:255-277`: get by `layers.first(where: { $0.id == id })` with a
captured-value fallback for the dying-view render tick; set by `firstIndex(where:)` lookup.
Any new list-of-models editing UI must use this pattern.

### 5. `editableBlockWidth == readoutBlockWidth` invariant

`controlValueFieldWidth` and `controlReadoutWidth` are both 55 **on purpose**: adjacent
editable and read-only rows share a trailing block width so label columns align without
per-editor tuning. Locked by a pure equality test
(`Tests/FramerAppTests/SidebarLayoutContainmentTests.swift:14` and
`SidebarMetricsTests.swift:35-37`). If you add a new read-only row style, keep the invariant
or change both tokens together.

### 6. ColorPicker labels: `.labelsHidden()` + the `labeledColorPicker` row pattern

SwiftUI's native `ColorPicker(label, selection:)` draws its label INLINE next to the well.
**Incident:** 23 call sites passed non-empty labels, producing stray "Color" / "Fill Color"
text chips floating mid-row. Fix: `ColorPickerWithHex` applies `.labelsHidden()`
(`Controls/ColorPickerWithHex.swift:20`) plus an accessibility label, and the visible label
lives in the 104pt label column via the private `labeledColorPicker(_:selection:onHexCommit:)`
helper (`LayerListSection.swift:11`). Two intentionally empty-labelled call sites remain
(Border, `SidebarPaletteEditor`). Any new color control follows this pattern.

### 7. Derived-picker snap-back guard (for ANY new preset picker)

Pattern to fear: a picker whose selection is DERIVED each render via a `matching(storedValues)`
function. If choosing "Custom" seeds the stored values with data that matches a canonical
preset, `matching()` re-resolves to that preset and the picker silently snaps back.
**Incident — twice, two days apart:** ASCII character palette (commit 9ad0f2c, seed was
Classic's literal string) and Dither color palette (commit 9a5857f, seed was
`VintagePalette.gameBoy`). Fix exemplar at `LayerListSection.swift:3643-3660`: seed with data
guaranteed to match no preset (append a neutral `#808080` swatch), trim to MAX−1 first so the
neutral isn't dropped at the palette cap, and bail early if the user re-picks the current
preset. The derived-selection pattern still exists — every NEW preset picker can reintroduce
this. Full saga: **framer-failure-archaeology**.

### 8. Render keys must include EVERYTHING that affects output

**Incident:** `PresetPreviewGrid` didn't re-render after preset save/rename/delete (render key
omitted the `Preset` array) and after photo rotation (omitted `selectedPhoto?.rotation`).
Current key (`Presets/PresetPreviewGrid.swift:39-42`) is a pure struct of
`selectedPhoto?.id` + `photoRotation` + the full preset list, tested in
`Tests/FramerAppTests/PresetPreviewRenderKeyTests.swift`. When adding any input that changes a
rendered preview, add it to the render key in the same change.

### 9. `@State` in collapsible subtrees is torn down — long-lived caches go on `@Observable` objects

**Incident:** collapsing the Presets section discarded all rendered thumbnails because SwiftUI
destroys `@State` when the conditional subtree unmounts; every expand re-rendered from scratch.
Fix: thumbnails live in `PresetThumbnailCache` — a dedicated `@Observable @MainActor final
class` (`Sources/FramerApp/Presets/PresetThumbnailCache.swift:17`) hung off `AppState`, NOT on
`AppState` directly (that would make every thumbnail write invalidate every view observing any
AppState property — observation scope should match what views read). Related: keep at most ONE
in-flight render task (`@State var renderTask: Task<Void, Never>?`, cancel-before-replace) —
the earlier `renderTasks[UUID()]` dictionary leaked orphaned tasks that wrote stale previews.

---

## Snapshot coupling — read before changing ANY sidebar pixel

`Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` locks ~10 SHA-256 baselines of
rendered sidebar surfaces (shell, layer-row states, output rows, simple/dense/overlay editors,
preset/export surfaces) hosted in a dark `NSHostingView`. Any visual change here — even a
1pt inset — shifts hashes. House rule (binding): **never blind-refresh a hash**; read the
rendered pixels, explain the shift, and land the refresh in the SAME commit as the change that
caused it (historically 1–4 hashes per commit, so bisect can attribute drift). The refresh
protocol, the cross-machine fragility caveat, and how to run this suite live in
**framer-validation-and-qa**. Note this suite runs only under `xcodebuild test`, not
`swift test` — and that tier is currently broken on the dev machine; see
**framer-campaign-restore-validation**.

Field lesson worth keeping: when a refactor is supposed to be visually transparent but a
snapshot shifts, the usual cause is hidden internal state (like `hasContent`) diverging from
what a naive type-based check returns. The snapshot diff is the forcing function — trust it.

## Warning label: `LayerListSection.swift`

`Sources/FramerApp/Editor/LayerListSection.swift` is **4,833 lines and the highest fix-churn
file in the repo** (as of 2026-07-09; the churn count and its exact re-verify command live in
framer-architecture-contract's weak-points table) — the most fragile file in the repo. Make the smallest possible diff, touch
one editor at a time, and expect snapshot churn. New reusable shapes should be PROMOTED out
into `Sidebar/` primitives (as `SidebarFullWidthRow` was), not grown inline.

## iOS (FramerMobile)

The iOS app has its own control surfaces — `Sources/FramerMobile/Layers/LayerDetailView.swift`
and `LayerStrip.swift` — and its own design brief (`assets/design/ios/IOS_DESIGN_BRIEFING.md`;
its mockup path is likewise wrong — actual file is `assets/design/ios/framer-ios-concept.html`).
The macOS sidebar grammar does NOT apply there. Capability-flag gating of effect controls was
extended to iOS by **PR #12** (`fix/effect-params-and-editor-bugs`, **merged 2026-07-09**,
`f2c9521`): LayerDetailView.swift now gates on all five `uses*` flags, including the new
`usesPalette` (verified post-merge — lines 203/237/245/258/262). Parameter/capability-flag
details: **framer-config-and-flags**.

## Checklist: adding a new sidebar control

1. Pick the primitive from the catalog; if none fits, promote a new primitive into
   `Sources/FramerApp/Sidebar/` with the env-threading pattern (non-negotiable 1).
2. All dimensions from `SidebarMetrics`; label in the 104pt column; values in mono
   (`AppFont.numericInput`); no `withAnimation` on value/selection changes.
3. Segmented picker only if options fit the 162pt budget; else `.menu`.
4. Color wells via `labeledColorPicker` / `ColorPickerWithHex` (non-negotiable 6).
5. New preset picker? Apply the snap-back guard (non-negotiable 7).
6. Preview-affecting input? Extend the render key (non-negotiable 8).
7. New file under `Sources/FramerApp/` or `Tests/FramerAppTests/`? You must run
   `xcodegen generate` before `xcodebuild test` sees it — details in **framer-build-and-env**.
8. Expect snapshot hashes to shift; follow the refresh protocol in **framer-validation-and-qa**.

## Provenance and maintenance

Verified 2026-07-09 against main @ 48d85a5 by reading every cited file and running read-only
git commands. Sidebar-grammar lessons distilled from `.sisyphus/notepads/sidebar-harmony/learnings.md`
(the PR #8 engineering diary) with each claim re-verified against current code; note that the
notepad's "304/320/352" width band is stale (superseded by c83b509 on 2026-04-15).
`assets/design/DESIGN_BRIEFING.md` is authoritative for tokens/typography but stale on inspector
width and mockup paths (corrections above; staleness ledger: **framer-docs-and-writing**).

Re-verification one-liners (run from repo root):

| Fact | Command |
|---|---|
| Width band 300/350/520 | `grep -n -A3 'static let .default.' Sources/FramerApp/Sidebar/SidebarLayoutPolicy.swift` |
| SidebarMetrics defaults (104/55/24/12/...) | `sed -n '22,40p' Sources/FramerApp/Sidebar/SidebarMetrics.swift` |
| Color/font tokens | `sed -n '1,75p' Sources/FramerApp/Theme/DesignTokens.swift` |
| Result-builder rationale intact | `grep -n 'absent' Sources/FramerApp/Sidebar/SidebarControlRow.swift Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift` |
| NSSlider clip + pad | `grep -n 'clipShape\|padding(.trailing' Sources/FramerApp/Sidebar/SidebarControlRow.swift` |
| ID-keyed layer binding | `grep -n -A5 'func binding(for layer' Sources/FramerApp/Editor/LayerListSection.swift` |
| Width invariant test | `grep -rn 'controlReadoutWidth' Tests/FramerAppTests/SidebarMetricsTests.swift Tests/FramerAppTests/SidebarLayoutContainmentTests.swift` |
| Snap-back guard | `grep -n '808080' Sources/FramerApp/Editor/LayerListSection.swift` |
| Render key contents | `sed -n '39,45p' Sources/FramerApp/Presets/PresetPreviewGrid.swift` |
| Thumbnail cache class | `grep -n 'final class PresetThumbnailCache' Sources/FramerApp/Presets/PresetThumbnailCache.swift` |
| Snapshot baseline count | `grep -c 'expectedSHA256: "' Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` |
| LayerListSection size / fix churn | `wc -l Sources/FramerApp/Editor/LayerListSection.swift` and `git log --format= --name-only -i --grep=fix -- Sources/FramerApp/Editor/LayerListSection.swift \| grep -c LayerListSection` |
| iOS capability-flag gating intact (PR #12 MERGED 2026-07-09) | `gh pr view 12 --json state` (expect MERGED) and `grep -c 'params.kind.uses' Sources/FramerMobile/Layers/LayerDetailView.swift` (expect ≥5) |
