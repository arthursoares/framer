# Sidebar Layout Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize the macOS inspector/sidebar layout so standard rows share one horizontal contract, numeric value+unit rows align as one trailing cluster, color rows use the newer shell, and preview/media controls stay width-contained.

**Architecture:** Keep the work inside the existing sidebar presentation layer. Extend shared primitives in `SidebarMetrics`, `SidebarControlRow`, and a dedicated trailing-cluster helper so row layout rules are inherited instead of patched ad hoc. Then convert the specific `LayerListSection` call sites for simple editor rows, color exceptions, and preview/media containment, using tests plus existing snapshot surfaces to verify the new grammar.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit-hosted snapshot tests, XCTest, existing `SidebarHarmonySnapshotTests` and `SidebarMetricsTests`.

---

## File Map

### Create
- `Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift` — reusable right-aligned `[value][unit]` cluster for standard numeric rows.
- `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift` — width-containment regression tests for overlay/LUT/full-width exception rows.

### Modify
- `Sources/FramerApp/Sidebar/SidebarMetrics.swift` — centralize numeric cluster sizing and exception-row containment metrics.
- `Sources/FramerApp/Sidebar/SidebarControlRow.swift` — enforce the shared right-edge contract for standard rows.
- `Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift` — ensure stacked secondary content inherits the same outer width contract.
- `Sources/FramerApp/Editor/LayerListSection.swift` — adopt shared trailing clusters in Border/Padding/Canvas/Resize rows, normalize border color shell, and contain preview/media rows.
- `Tests/FramerAppTests/SidebarMetricsTests.swift` — add failing tests for the new shared cluster metrics.
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` — refresh Border/Canvas/Overlay surfaces after the shared layout contract changes.

### Existing tests reused during implementation
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift:test_simpleEditorSurfaces`
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift:test_overlayEditorSurface`
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift:test_presetAndExportSurfaces`

---

### Task 1: Encode the shared row contract in sidebar primitives

**Files:**
- Create: `Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarMetrics.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarControlRow.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift`
- Test: `Tests/FramerAppTests/SidebarMetricsTests.swift`

- [ ] **Step 1: Write the failing metrics tests**

Add explicit tests for the shared numeric cluster geometry in `Tests/FramerAppTests/SidebarMetricsTests.swift`:

```swift
func test_defaultMetrics_defineNumericTrailingCluster() {
    let metrics = SidebarMetrics()

    XCTAssertEqual(metrics.controlTrailingClusterSpacing, 6)
    XCTAssertEqual(metrics.controlUnitSuffixWidth, 24)
    XCTAssertEqual(metrics.controlValueFieldWidth, 55)
}

func test_defaultMetrics_definePreviewContainmentInsets() {
    let metrics = SidebarMetrics()

    XCTAssertEqual(metrics.fullWidthRowHorizontalInset, metrics.outerInset)
    XCTAssertEqual(metrics.containedPreviewMaxWidth, 350 - (metrics.outerInset * 2))
}
```

- [ ] **Step 2: Run the metrics tests to verify they fail**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarMetricsTests
```

Expected: FAIL because `SidebarMetrics` does not yet expose `controlTrailingClusterSpacing`, `controlUnitSuffixWidth`, `controlValueFieldWidth`, `fullWidthRowHorizontalInset`, or `containedPreviewMaxWidth`.

- [ ] **Step 3: Implement the shared layout primitives**

Extend `SidebarMetrics` and add a reusable trailing cluster view.

`Sources/FramerApp/Sidebar/SidebarMetrics.swift`

```swift
struct SidebarMetrics: Sendable, Equatable {
    let controlTrailingClusterSpacing: CGFloat
    let controlUnitSuffixWidth: CGFloat
    let controlValueFieldWidth: CGFloat
    let fullWidthRowHorizontalInset: CGFloat

    var containedPreviewMaxWidth: CGFloat {
        idealWidth - (fullWidthRowHorizontalInset * 2)
    }

    init(
        widthPolicy: SidebarLayoutPolicy = .default,
        outerInset: CGFloat = 12,
        rowGap: CGFloat = 16,
        expandedBodyInset: CGFloat = 6,
        footerSpacing: CGFloat = 0,
        controlRowMinHeight: CGFloat = 30,
        controlLabelWidth: CGFloat = 104,
        controlColumnSpacing: CGFloat = 10,
        controlTrailingValueWidth: CGFloat = 48,
        controlStackSpacing: CGFloat = 0,
        controlTrailingClusterSpacing: CGFloat = 6,
        controlUnitSuffixWidth: CGFloat = 24,
        controlValueFieldWidth: CGFloat = 55,
        fullWidthRowHorizontalInset: CGFloat = 12
    ) { ... }
}
```

`Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift`

```swift
import SwiftUI

struct SidebarTrailingUnitCluster<Field: View>: View {
    private let metrics: SidebarMetrics
    private let unit: LocalizedStringKey
    private let field: Field

    init(
        unit: LocalizedStringKey,
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder field: () -> Field
    ) {
        self.metrics = metrics
        self.unit = unit
        self.field = field()
    }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.controlTrailingClusterSpacing) {
            field
                .frame(width: metrics.controlValueFieldWidth, alignment: .trailing)

            Text(unit)
                .font(AppFont.mono(9))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlUnitSuffixWidth, alignment: .leading)
        }
        .frame(minWidth: metrics.controlTrailingValueWidth + metrics.controlUnitSuffixWidth, alignment: .trailing)
    }
}
```

Update `SidebarControlRow` so the control lane aligns to `.trailing` when a trailing value exists, while still allowing the main content to expand within the row shell:

```swift
HStack(alignment: .center, spacing: metrics.controlColumnSpacing) {
    content
        .frame(maxWidth: .infinity, alignment: trailingValue.hasContent ? .trailing : .leading)

    if trailingValue.hasContent {
        trailingValue.body
            .frame(minWidth: metrics.controlTrailingValueWidth, alignment: .trailing)
    }
}
.frame(maxWidth: .infinity, alignment: .trailing)
```

Keep `SidebarCompoundControlBlock` width-neutral by preserving `.frame(maxWidth: .infinity, alignment: .leading)` around both primary and secondary containers.

- [ ] **Step 4: Run the metrics tests to verify they pass**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarMetricsTests
```

Expected: PASS.

- [ ] **Step 5: Commit the primitive contract changes**

Run:

```bash
git add Sources/FramerApp/Sidebar/SidebarMetrics.swift Sources/FramerApp/Sidebar/SidebarControlRow.swift Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift Tests/FramerAppTests/SidebarMetricsTests.swift
git commit -m "refactor(sidebar): encode shared row layout contract"
```

---

### Task 2: Normalize standard numeric rows and the border color exception

**Files:**
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`
- Test: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Run the existing simple-editor snapshot tests as the baseline**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests/test_simpleEditorSurfaces
```

Expected: PASS on the current baseline hashes before implementation.

- [ ] **Step 2: Convert the standard numeric rows to the shared trailing cluster**

In `Sources/FramerApp/Editor/LayerListSection.swift`, replace ad hoc trailing `HStack` value+suffix groups with `SidebarTrailingUnitCluster` in:

- `BorderLayerControls` → `Thickness`
- `PaddingLayerControls` → `Thickness`
- `CanvasLayerControls.pixelFields` → `Width` / `Height`
- `CanvasLayerControls.physicalFields` → `DPI`, `Width`, `Height`
- the existing `ResizeLayerControls` max-width/max-height rows

Example conversion:

```swift
SidebarControlRow("Thickness") {
    Slider(value: thicknessValue, in: thicknessRange)
        .tint(Color.accentDim)
} trailingValue: {
    SidebarTrailingUnitCluster(unit: LocalizedStringKey(thicknessMode.rawValue)) {
        TextField("", value: thicknessValue, format: .number)
            .simpleLayerEditorInputStyle(width: SimpleLayerEditorLayout.fieldWidth, accessibilityLabel: "Thickness")
            .monospacedDigit()
    }
}
```

Use the same cluster pattern for `px`, `dpi`, `cm`, and `mm` rows so the unit and value behave as one trailing group.

- [ ] **Step 3: Move the border color row into the newer shell**

Still in `LayerListSection.swift`, stop rendering border color as a loose legacy row. Wrap it in a proper row shell so it behaves like a controlled exception:

```swift
ColorPickerWithHex("", selection: colorBinding)
    .denseControlRow("Color")
```

If `.denseControlRow(...)` does not preserve the desired swatch/hex composition for this call site, use `OverlayFullWidthControlRow("Color") { ... }` instead — but keep it inside the newer sidebar shell and not as a bare control.

- [ ] **Step 4: Run the simple-editor snapshots and refresh hashes**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests/test_simpleEditorSurfaces
```

Expected: FAIL because the `simple-canvas-editor` and `simple-border-editor` hashes changed.

Update the two expected hashes in `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`, then rerun the same command.

Expected after hash refresh: PASS.

- [ ] **Step 5: Commit the standard-row and border-color normalization**

Run:

```bash
git add Sources/FramerApp/Editor/LayerListSection.swift Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift
git commit -m "refactor(sidebar): normalize numeric and color rows"
```

---

### Task 3: Contain preview/media exception rows without widening the sidebar

**Files:**
- Create: `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift`
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`
- Test: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Write the failing width-containment tests**

Create `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift` with a helper that renders a view into an `NSHostingView` and asserts the fitted width does not exceed the intended sidebar width:

```swift
import XCTest
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class SidebarLayoutContainmentTests: XCTestCase {
    func test_overlay_editor_stays_within_sidebar_width() {
        XCTAssertLessThanOrEqual(
            renderedWidth(of: OverlayLayerControls(params: OverlayLayerParams()) { _ in }, width: 350),
            350
        )
    }

    func test_lut_editor_stays_within_sidebar_width() {
        XCTAssertLessThanOrEqual(
            renderedWidth(of: LUTLayerControls(params: LUTLayerParams()) { _ in }, width: 350),
            350
        )
    }

    private func renderedWidth<V: View>(of view: V, width: CGFloat) -> CGFloat {
        let root = view
            .environment(\.colorScheme, .dark)
            .frame(width: width, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.width
    }
}
```

- [ ] **Step 2: Run the containment tests to verify they fail**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarLayoutContainmentTests
```

Expected: FAIL if overlay/LUT preview rows are still reporting a width larger than the 350pt sidebar shell.

- [ ] **Step 3: Contain the exception-family rows**

In `Sources/FramerApp/Editor/LayerListSection.swift`, update the overlay and LUT preview/media call sites so preview tiles and supporting actions respect the same outer width:

```swift
OverlayFullWidthControlRow("Preview") {
    previewContent
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
        .clipped()
}

OverlayFullWidthControlRow("Library") {
    libraryActions
        .frame(maxWidth: .infinity, alignment: .leading)
}
```

Apply the same containment rule to LUT preview rows so they match the texture/frame families instead of expanding beyond the sidebar shell. Prefer width-contained containers over hardcoded row-specific widths.

- [ ] **Step 4: Run containment tests and overlay snapshots**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarLayoutContainmentTests -only-testing:FramerAppTests/SidebarHarmonySnapshotTests/test_overlayEditorSurface
```

Expected: the containment tests PASS. If the overlay snapshot hash changes, update the expected hash in `SidebarHarmonySnapshotTests.swift` and rerun until green.

- [ ] **Step 5: Commit the exception-row containment work**

Run:

```bash
git add Sources/FramerApp/Editor/LayerListSection.swift Tests/FramerAppTests/SidebarLayoutContainmentTests.swift Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift
git commit -m "fix(sidebar): contain preview and media rows"
```

---

### Task 4: Final verification and cleanup

**Files:**
- Review only; no planned new files

- [ ] **Step 1: Run focused sidebar tests**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
  -only-testing:FramerAppTests/SidebarMetricsTests \
  -only-testing:FramerAppTests/SidebarLayoutContainmentTests \
  -only-testing:FramerAppTests/SidebarHarmonySnapshotTests
```

Expected: PASS.

- [ ] **Step 2: Run package tests and macOS build**

Run:

```bash
swift test
xcodebuild build -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
```

Expected: both commands succeed.

- [ ] **Step 3: Check diagnostics on touched files**

Verify diagnostics are clean for:

- `Sources/FramerApp/Sidebar/SidebarMetrics.swift`
- `Sources/FramerApp/Sidebar/SidebarControlRow.swift`
- `Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift`
- `Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift`
- `Sources/FramerApp/Editor/LayerListSection.swift`
- `Tests/FramerAppTests/SidebarMetricsTests.swift`
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`
- `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift`

- [ ] **Step 4: Commit the final verification pass if any snapshot hashes changed in this task**

Run:

```bash
git add Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift
git commit -m "test(sidebar): refresh layout consistency coverage"
```

If no files changed in this task, skip the commit.

---

## Spec Coverage Check

- **Shared row grammar:** covered by Task 1 and Task 2.
- **Numeric value + unit trailing cluster:** covered by Task 1 and Task 2.
- **Color rows remain controlled exceptions:** covered by Task 2.
- **Preview/media rows stay width-contained:** covered by Task 3.
- **Avoid ad hoc call-site patching:** addressed by Task 1’s shared primitive work.

No gaps found relative to `docs/superpowers/specs/2026-04-15-sidebar-layout-consistency-design.md`.
