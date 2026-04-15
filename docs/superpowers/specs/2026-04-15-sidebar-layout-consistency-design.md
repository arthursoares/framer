# Sidebar Layout Consistency — Design Spec

> **Scope:** macOS inspector/sidebar layout grammar in `Sources/FramerApp/`
> **Focus:** horizontal alignment, field sizing, unit suffix placement, and width containment for richer controls
> **Out of scope:** control behavior bugs, keyboard handling, collapsible Presets behavior, and non-layout interaction changes

---

## Design Decisions (Resolved)

| Decision | Resolution |
|----------|------------|
| Default row layout | One shared row grammar for standard inspector controls |
| Exceptions | Color pickers and preview/media controls may have different internal composition |
| Numeric unit styling | Value field + unit suffix (for example `px`) behave as one right-aligned trailing cluster |
| Implementation style | Prefer normalizing shared sidebar primitives over patching each row ad hoc |

---

## Goal

Make the macOS sidebar feel like one coherent inspector system by enforcing a consistent left edge, a consistent right edge, and a predictable trailing control alignment across standard adjustment rows.

This pass is intended to solve the specific layout complaints already identified in the current inspector work:

- left-side gap is inconsistent across controls
- many parameter controls stop short of the right edge
- some numeric fields are visually oversized relative to the row
- rows with unit suffixes like `px` do not read as one aligned control group
- a subset of color rows still reads like the older layout grammar
- richer preview/media rows can expand in ways that distort the sidebar width

---

## Layout Contract

### Default row grammar

All standard inspector adjustment rows use the same two-lane contract:

- **Label lane:** begins from one shared left inset
- **Control lane:** terminates at one shared right edge

The goal is not that every control has the same internal structure, but that every normal row shares the same outer geometry. A row should visually read as part of the same inspector family even when the control inside differs.

Standard rows include:

- slider rows with trailing values
- numeric input rows
- stepper-style numeric rows
- dropdown / picker rows
- segmented choice rows
- toggle/value rows

### Right-edge authority

The right edge of the inspector becomes the authoritative stop for all standard controls. Rows should no longer look left-loose and right-short. If a control occupies less visual width, it still belongs to a trailing cluster whose outer edge aligns with the rest of the sidebar.

### Left-edge consistency

The extra left gap currently visible in some adjustments is removed. Standard rows should share the same left start point so stacked controls feel vertically locked together instead of drifting in and out.

---

## Control Families

### 1. Default family: standard inspector rows

These rows inherit the shared grammar directly.

Examples in the current inspector include:

- `Thickness`
- `Canvas Width`
- `Canvas Height`
- `DPI`
- `Resize Max Width`
- `Resize Max Height`
- other trailing-value rows in the layer editors that already conceptually behave like normal inspector parameters

These controls should not define their own width logic if a shared row primitive can express the same result.

### 2. Exception family: color controls

Color controls are allowed a different internal arrangement because they may combine:

- swatch
- hex field
- picker affordance
- optional clear/reset behavior

However, they should still visually live inside the newer inspector shell rather than falling back to the older loose layout. For example, rows like `Border > Color` should look like a controlled exception, not like a completely different UI system.

### 3. Exception family: preview/media controls

Preview/media rows are also allowed richer internal composition. This includes controls such as:

- frame / texture / light leak / wet plate preview surfaces
- LUT preview surfaces
- similar media-selection rows with thumbnails or inline preview tiles

These controls may break the simple row interior, but they must still respect the outer sidebar width and should never horizontally resize the sidebar, clip trailing actions, or introduce a different shell width.

---

## Numeric Input Rules

### Value + unit = one cluster

For numeric rows with explicit unit suffixes, the value field and unit suffix behave as one right-aligned trailing cluster.

Examples:

- `Canvas Width` → `[value][px]`
- `Canvas Height` → `[value][px]`
- `Resize Max Width` → `[value][px]`
- `Resize Max Height` → `[value][px]`

The cluster should be visually flush to the right edge of the control lane. The field should not float independently while the suffix sits as detached secondary text.

### Field sizing

Numeric input fields should be only as wide as they need to be within the shared row grammar. Oversized fields that consume too much of the row should be tightened so they read as inspector controls rather than form inputs.

This directly applies to rows like `Thickness`, where the current field width feels too large and stops short of the correct trailing edge.

### Missing suffix normalization

Rows that conceptually operate in pixels should include the `px` suffix when they participate in the numeric-cluster pattern. This specifically includes the current `Resize Max Width` / `Resize Max Height` presentation.

---

## Slider and Discrete-Value Rules

Slider rows still belong to the shared row grammar, but not every current slider should remain a slider.

### Standard slider rows

For continuous values, the slider occupies the main control lane and any trailing numeric value aligns to the same right edge used by other rows.

### Discrete numeric rows

If a parameter is better expressed as an exact count or bounded discrete value than as a gestural slider, it should move out of the slider family and into a compact stepper-style numeric control.

Relevant examples from current feedback:

- `Dither Pixel Scale`
- `Dither Levels`

These should participate in the same right-aligned trailing system as other numeric rows, rather than behaving like long sliders.

---

## Width Containment Rules

The sidebar shell width is stable. Individual layer panels, disclosure expansions, and preview/media controls must fit inside that width instead of redefining it.

### Required behavior

- Expanding richer controls must not widen the sidebar
- Preview/media rows must not push or clip trailing buttons
- Rows with multiple embedded controls must still respect the same outer container width

This rule specifically covers the current preview-style families such as frame / texture / light leak / wet plate and LUT preview behavior.

---

## Row Mapping for Current Feedback

### Standard-row fixes

These issues are addressed by the default grammar:

- `Thickness` field too large and not reaching the correct right edge
- `Canvas Width / Height` fields not clamped correctly with the `px` suffix
- `Resize Max Width / Max Height` missing `px` and not behaving as proper trailing unit rows
- the general complaint that parameters should align to the right edge of the sidebar
- the general complaint that the left alignment does not use the full sidebar width consistently

### Color-row fixes

These issues are addressed by the controlled exception grammar for color rows:

- `Border > Color` still looking like the older layout

### Preview/media containment fixes

These issues are addressed by the width-containment rule:

- richer preview/media controls causing horizontal sidebar resize
- right-side actions becoming hidden when some sections expand
- LUT preview needing to behave within the same preview containment contract as the texture/frame families

---

## Technical Design

### Shared primitive responsibility

This work should be driven primarily through shared inspector primitives rather than one-off row patches. The current dense inspector work already introduced a row grammar and compound control structure; this design extends that approach by making horizontal alignment rules more explicit and more consistently inherited.

The implementation should prefer:

- one shared row-width/alignment contract for standard rows
- one shared trailing cluster pattern for numeric value + unit rows
- explicit container rules for exception families

The implementation should avoid:

- hardcoding widths at many individual call sites
- allowing individual rows to define incompatible leading/trailing geometry
- solving containment issues by letting the sidebar shell grow wider

### Likely file surface

This design is expected to affect the sidebar presentation layer only. Likely touch points include:

- `Sources/FramerApp/Sidebar/SidebarControlRow.swift`
- `Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift`
- `Sources/FramerApp/Sidebar/SidebarMetrics.swift`
- `Sources/FramerApp/Editor/LayerListSection.swift`
- specialized helper views used by color rows and preview/media rows

The exact implementation plan should decide whether a dedicated trailing-cluster helper is preferable to extending the existing dense row APIs.

---

## Constraints

- Keep the scope limited to layout consistency for this pass
- Do not bundle unrelated interaction changes into the same design scope
- Preserve the denser inspector direction already established in the sidebar worktree
- Use explicit exceptions only where the control type genuinely requires it
- Prefer consistent containment and alignment over local visual hacks

---

## Success Criteria

The layout pass is successful when all of the following are true:

1. Standard adjustment rows share the same left start and right stop
2. Numeric value + unit rows read as one right-aligned trailing cluster
3. Oversized text fields like `Thickness` no longer dominate the row
4. Pixel-based rows such as Canvas and Resize present their `px` suffix consistently
5. Color rows no longer visually fall back to the old inspector grammar
6. Preview/media controls stay contained within the sidebar width when expanded
7. The sidebar reads as one system rather than a mix of old and new row layouts
