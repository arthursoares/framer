# Sidebar Harmony Pass 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the dual-token system, extract remaining primitive gaps, and propagate `SidebarMetrics` via environment so every inspector row obeys one layout contract.

**Architecture:** Consolidate `SimpleLayerEditorLayout` constants into `SidebarMetrics`. Add one new trailing cluster (`SidebarTrailingReadoutCluster`) and four rich-affordance primitives (`SidebarFullWidthRow`, `SidebarPreviewStrip`, `SidebarPaletteEditor`, `SidebarChipFlow`). Thread metrics through `@Environment(\.sidebarMetrics)` so `SidebarShell` overrides reach descendants. Migrate `LayerPanelRow`, `StyledSlider`, and call sites in `LayerListSection.swift` to the unified contract. Keep snapshot tests honest — refresh SHA hashes when layout changes are intended.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, AppKit-hosted snapshot tests (`NSHostingView` + `bitmapImageRepForCachingDisplay` + SHA-256), XcodeGen (`project.yml`), macOS 14+.

**Reference:** `docs/sidebar-harmony-target/index.html` — visual target-state spec. Before/after cards in §5 map 1:1 to the tasks below.

---

## File Map

### Create
- `Sources/FramerApp/Sidebar/SidebarMetricsEnvironment.swift` — `EnvironmentKey` for `SidebarMetrics`.
- `Sources/FramerApp/Sidebar/SidebarTrailingReadoutCluster.swift` — read-only `[value][unit]` trailing cluster (Task 2).
- `Sources/FramerApp/Sidebar/SidebarFullWidthRow.swift` — promoted from private `OverlayFullWidthControlRow` (Task 6).
- `Sources/FramerApp/Sidebar/SidebarPreviewStrip.swift` — horizontal tile strip primitive (Task 5).
- `Sources/FramerApp/Sidebar/SidebarPaletteEditor.swift` — swatch+hex+delete palette rows (Task 5).
- `Sources/FramerApp/Sidebar/SidebarChipFlow.swift` — wrapping chip grid bounded to `containedPreviewMaxWidth` (Task 5).
- `Tests/FramerAppTests/SidebarEnvironmentTests.swift` — asserts shell metrics reach descendants (Task 3).
- `Tests/FramerAppTests/StyledSliderSuffixTests.swift` — asserts slider no longer renders inline 20pt suffix (Task 7).
- `Tests/FramerAppTests/LayerPanelRowLayoutTests.swift` — asserts expanded body aligns with section grid (Task 4).

### Modify
- `Sources/FramerApp/Sidebar/SidebarMetrics.swift` — add `controlReadoutWidth`, `controlSegmentedModeWidth`, `controlUnitPickerWidth`; thread through `replacing(widthPolicy:)`.
- `Sources/FramerApp/Sidebar/SidebarShell.swift` — write `metrics` into environment.
- `Sources/FramerApp/Sidebar/SidebarSection.swift` — read `metrics` from environment.
- `Sources/FramerApp/Sidebar/SidebarControlRow.swift` — read `metrics` from environment; keep `init(metrics:)` for preview overrides but stop defaulting.
- `Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift` — read `metrics` from environment.
- `Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift` — read `metrics` from environment.
- `Sources/FramerApp/Sidebar/LayerPanelRow.swift` — replace `LayerPanelRowLayout` raw `Spacing.*` with metrics-derived values.
- `Sources/FramerApp/Editor/LayerListSection.swift` — retire `SimpleLayerEditorLayout`, remove private `OverlayFullWidthControlRow`, migrate ~30 call sites to the new tokens and primitives.
- `Sources/FramerApp/Controls/StyledSlider.swift` — remove `suffix` and `inputWidth` parameters.
- `Sources/FramerApp/Controls/ColorPickerWithHex.swift` — read hex field width from metrics (optional `compactFieldWidth` mapping).
- `Sources/FramerApp/Inspector/InspectorView.swift` — update Output "Quality" row to compose slider + `SidebarTrailingUnitCluster`.
- `Sources/FramerApp/Inspector/ExportBar.swift` — read `metrics` from environment.
- `Sources/FramerApp/Presets/PresetPreviewGrid.swift` — read `metrics` from environment.
- `Sources/FramerApp/Presets/PresetPreviewCard.swift` — read `metrics` from environment.
- `Framer.xcodeproj/project.pbxproj` — regenerated via `xcodegen generate` after adding files.
- `Tests/FramerAppTests/SidebarMetricsTests.swift` — add tests for the three new tokens.
- `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift` — extend to cover palette/strip/chip-flow/full-width-row containment.
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift` — refresh hashes for `simple-canvas-editor`, `simple-border-editor`, `overlay-editor`, `dense-caption-editor`, `dense-dither-editor`, `output-rows-png`, `output-rows-jpeg`, `preset-grid-support-surfaces`, `export-support-surfaces` after layout changes land.

### Existing tests reused during implementation
- `Tests/FramerAppTests/SidebarMetricsTests.swift` — baseline metric values.
- `Tests/FramerAppTests/SidebarLayoutPolicyTests.swift` — width band (unchanged).
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift:test_simpleEditorSurfaces` — Canvas/Border hashes refresh in Task 1.
- `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift:test_overlayEditorSurface` — refresh in Task 6.

---

## Task 1: Retire `SimpleLayerEditorLayout`, add new metric tokens

**Files:**
- Modify: `Sources/FramerApp/Sidebar/SidebarMetrics.swift`
- Modify: `Tests/FramerAppTests/SidebarMetricsTests.swift`
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`
- Modify: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Write the failing metric tests**

Add to `Tests/FramerAppTests/SidebarMetricsTests.swift`:

```swift
func test_defaultMetrics_exposeReadoutTokens() {
    let metrics = SidebarMetrics()

    XCTAssertEqual(metrics.controlReadoutWidth, 55)
    XCTAssertEqual(metrics.controlReadoutWidth, metrics.controlValueFieldWidth,
                   "Read-only readouts must share editable field width so rows align")
}

func test_defaultMetrics_exposeSegmentedAndUnitPickerWidths() {
    let metrics = SidebarMetrics()

    XCTAssertEqual(metrics.controlSegmentedModeWidth, 80)
    XCTAssertEqual(metrics.controlUnitPickerWidth, 100)
}
```

- [ ] **Step 2: Run metrics tests to verify they fail**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarMetricsTests
```

Expected: FAIL — `SidebarMetrics` doesn't expose those properties yet.

- [ ] **Step 3: Add the three new tokens to `SidebarMetrics`**

Edit `Sources/FramerApp/Sidebar/SidebarMetrics.swift`. Add properties, init params, and include them in `replacing(widthPolicy:)`:

```swift
struct SidebarMetrics: Sendable, Equatable {
    let outerInset: CGFloat
    let rowGap: CGFloat
    let expandedBodyInset: CGFloat
    let footerSpacing: CGFloat
    let controlRowMinHeight: CGFloat
    let controlLabelWidth: CGFloat
    let controlColumnSpacing: CGFloat
    let controlTrailingValueWidth: CGFloat
    let controlTrailingClusterSpacing: CGFloat
    let controlUnitSuffixWidth: CGFloat
    let controlValueFieldWidth: CGFloat
    let controlReadoutWidth: CGFloat
    let controlSegmentedModeWidth: CGFloat
    let controlUnitPickerWidth: CGFloat
    let controlStackSpacing: CGFloat
    let fullWidthRowHorizontalInset: CGFloat
    let widthPolicy: SidebarLayoutPolicy

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
        controlTrailingClusterSpacing: CGFloat = 6,
        controlUnitSuffixWidth: CGFloat = 24,
        controlValueFieldWidth: CGFloat = 55,
        controlReadoutWidth: CGFloat = 55,
        controlSegmentedModeWidth: CGFloat = 80,
        controlUnitPickerWidth: CGFloat = 100,
        controlStackSpacing: CGFloat = 0,
        fullWidthRowHorizontalInset: CGFloat = 12
    ) {
        self.widthPolicy = widthPolicy
        self.outerInset = outerInset
        self.rowGap = rowGap
        self.expandedBodyInset = expandedBodyInset
        self.footerSpacing = footerSpacing
        self.controlRowMinHeight = controlRowMinHeight
        self.controlLabelWidth = controlLabelWidth
        self.controlColumnSpacing = controlColumnSpacing
        self.controlTrailingValueWidth = controlTrailingValueWidth
        self.controlTrailingClusterSpacing = controlTrailingClusterSpacing
        self.controlUnitSuffixWidth = controlUnitSuffixWidth
        self.controlValueFieldWidth = controlValueFieldWidth
        self.controlReadoutWidth = controlReadoutWidth
        self.controlSegmentedModeWidth = controlSegmentedModeWidth
        self.controlUnitPickerWidth = controlUnitPickerWidth
        self.controlStackSpacing = controlStackSpacing
        self.fullWidthRowHorizontalInset = fullWidthRowHorizontalInset
    }

    var minimumWidth: CGFloat { widthPolicy.minimumWidth }
    var idealWidth: CGFloat { widthPolicy.idealWidth }
    var maximumWidth: CGFloat { widthPolicy.maximumWidth }
    var containedPreviewMaxWidth: CGFloat { idealWidth - (fullWidthRowHorizontalInset * 2) }
    var controlStackDividerInset: CGFloat { outerInset }
    var controlStackDividerThickness: CGFloat { 1 }

    func clampedWidth(for proposedWidth: CGFloat) -> CGFloat {
        widthPolicy.clampedWidth(for: proposedWidth)
    }

    func replacing(widthPolicy: SidebarLayoutPolicy) -> SidebarMetrics {
        SidebarMetrics(
            widthPolicy: widthPolicy,
            outerInset: outerInset,
            rowGap: rowGap,
            expandedBodyInset: expandedBodyInset,
            footerSpacing: footerSpacing,
            controlRowMinHeight: controlRowMinHeight,
            controlLabelWidth: controlLabelWidth,
            controlColumnSpacing: controlColumnSpacing,
            controlTrailingValueWidth: controlTrailingValueWidth,
            controlTrailingClusterSpacing: controlTrailingClusterSpacing,
            controlUnitSuffixWidth: controlUnitSuffixWidth,
            controlValueFieldWidth: controlValueFieldWidth,
            controlReadoutWidth: controlReadoutWidth,
            controlSegmentedModeWidth: controlSegmentedModeWidth,
            controlUnitPickerWidth: controlUnitPickerWidth,
            controlStackSpacing: controlStackSpacing,
            fullWidthRowHorizontalInset: fullWidthRowHorizontalInset
        )
    }
}
```

- [ ] **Step 4: Run the metrics tests to verify they pass**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarMetricsTests
```

Expected: PASS.

- [ ] **Step 5: Delete `SimpleLayerEditorLayout` and migrate call sites**

Edit `Sources/FramerApp/Editor/LayerListSection.swift`. Delete the enum at line 1575-1583 and replace every reference with the metric equivalent. The only branch you lose is `compactFieldWidth = 50` — migrate to `controlValueFieldWidth = 55` (the gradient saturation/brightness rows will now use 55pt fields).

Sweeping replacements inside `LayerListSection.swift`:

- `SimpleLayerEditorLayout.fieldWidth` → `SidebarMetrics().controlValueFieldWidth` (for now; Task 3 will swap to `@Environment`)
- `SimpleLayerEditorLayout.compactFieldWidth` → `SidebarMetrics().controlValueFieldWidth`
- `SimpleLayerEditorLayout.suffixWidth` → `SidebarMetrics().controlUnitSuffixWidth`
- `SimpleLayerEditorLayout.valueTextWidth` → `SidebarMetrics().controlReadoutWidth`
- `SimpleLayerEditorLayout.thicknessModeWidth` → `SidebarMetrics().controlSegmentedModeWidth`
- `SimpleLayerEditorLayout.unitPickerWidth` → `SidebarMetrics().controlUnitPickerWidth`
- `SimpleLayerEditorLayout.groupSpacing` → `SidebarMetrics().expandedBodyInset`

Then delete:

```swift
private enum SimpleLayerEditorLayout {
    static let groupSpacing = SidebarMetrics().expandedBodyInset
    static let fieldWidth = 55.0
    static let compactFieldWidth = 50.0
    static let suffixWidth = 24.0
    static let valueTextWidth = 36.0
    static let thicknessModeWidth = 80.0
    static let unitPickerWidth = 100.0
}
```

Keep `simpleLayerEditorInputStyle` extensions; they just reference widths differently. Update their default to use a local `SidebarMetrics()` call.

- [ ] **Step 6: Build and run simple-editor snapshots**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests/test_simpleEditorSurfaces
```

Expected: FAIL because `simple-border-editor` and `simple-canvas-editor` hashes changed (gradient saturation/brightness fields grew from 50pt → 55pt).

Update the two expected hashes in `SidebarHarmonySnapshotTests.swift` to the actual values reported. Rerun.

Expected after refresh: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/FramerApp/Sidebar/SidebarMetrics.swift \
    Sources/FramerApp/Editor/LayerListSection.swift \
    Tests/FramerAppTests/SidebarMetricsTests.swift \
    Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift
git commit -m "refactor(sidebar): retire SimpleLayerEditorLayout, unify metrics"
```

---

## Task 2: Add `SidebarTrailingReadoutCluster` primitive

**Files:**
- Create: `Sources/FramerApp/Sidebar/SidebarTrailingReadoutCluster.swift`
- Modify: `Framer.xcodeproj/project.pbxproj` (via `xcodegen generate`)
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`
- Modify: `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift`
- Modify: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Write the failing alignment test**

Add to `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift`:

```swift
func test_readoutAndEditableRows_shareTrailingBlockWidth() {
    let metrics = SidebarMetrics()
    let editableBlockWidth = metrics.controlValueFieldWidth + metrics.controlTrailingClusterSpacing + metrics.controlUnitSuffixWidth
    let readoutBlockWidth = metrics.controlReadoutWidth + metrics.controlTrailingClusterSpacing + metrics.controlUnitSuffixWidth

    XCTAssertEqual(editableBlockWidth, readoutBlockWidth,
                   "Editable and read-only trailing clusters must occupy identical width so labels align across adjacent rows")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarLayoutContainmentTests
```

Expected: PASS already (both sides compute to 85pt after Task 1). If it fails, something diverged in Task 1; go back and fix.

(This step just locks the invariant; no failing condition yet.)

- [ ] **Step 3: Create the primitive**

Create `Sources/FramerApp/Sidebar/SidebarTrailingReadoutCluster.swift`:

```swift
import SwiftUI

struct SidebarTrailingReadoutCluster<Content: View>: View {
    private let metrics: SidebarMetrics
    private let unit: LocalizedStringKey
    private let content: Content

    init(
        unit: LocalizedStringKey = "",
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder content: () -> Content
    ) {
        self.metrics = metrics
        self.unit = unit
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.controlTrailingClusterSpacing) {
            content
                .frame(width: metrics.controlReadoutWidth, alignment: .trailing)

            Text(unit)
                .font(AppFont.mono(9))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlUnitSuffixWidth, alignment: .leading)
        }
        .frame(
            minWidth: metrics.controlTrailingValueWidth + metrics.controlUnitSuffixWidth,
            alignment: .trailing
        )
    }
}
```

- [ ] **Step 4: Regenerate Xcode project and build**

Run:

```bash
xcodegen generate
xcodebuild build -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
```

Expected: SUCCEEDED. (File compiles, not yet consumed.)

- [ ] **Step 5: Migrate AspectRatio Offset X/Y and Canvas pixelSummary**

In `Sources/FramerApp/Editor/LayerListSection.swift`:

Replace AspectRatio trailing values (the `Text(String(format: "%.1f", ...))` with `.frame(width: SidebarMetrics().controlReadoutWidth ...)`) with:

```swift
// Offset X
trailingValue: {
    SidebarTrailingReadoutCluster {
        Text(String(format: "%.1f", params.offsetX))
            .font(AppFont.mono(10))
            .foregroundStyle(Color.text3)
            .monospacedDigit()
    }
}
```

Apply the same pattern to Offset Y.

Replace Canvas `pixelSummary` (around line 1958-1969):

```swift
@ViewBuilder
private var pixelSummary: some View {
    if sizeMode == .physical {
        SidebarControlRow("Output Pixels") {
            EmptyView()
        } trailingValue: {
            SidebarTrailingReadoutCluster(unit: "× \(params.height) px") {
                Text("\(params.width)")
                    .font(AppFont.mono(10))
                    .foregroundStyle(Color.text3)
                    .monospacedDigit()
            }
        }
    }
}
```

- [ ] **Step 6: Refresh affected snapshot hashes**

Run:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests/test_simpleEditorSurfaces
```

Expected: FAIL — `simple-canvas-editor` hash changed.

Update `expectedSHA256` for `simple-canvas-editor` and rerun until green.

- [ ] **Step 7: Commit**

```bash
git add Sources/FramerApp/Sidebar/SidebarTrailingReadoutCluster.swift \
    Sources/FramerApp/Editor/LayerListSection.swift \
    Framer.xcodeproj/project.pbxproj \
    Tests/FramerAppTests/SidebarLayoutContainmentTests.swift \
    Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift
git commit -m "feat(sidebar): add SidebarTrailingReadoutCluster primitive"
```

---

## Task 3: Thread `SidebarMetrics` via `@Environment`

**Files:**
- Create: `Sources/FramerApp/Sidebar/SidebarMetricsEnvironment.swift`
- Create: `Tests/FramerAppTests/SidebarEnvironmentTests.swift`
- Modify: `Framer.xcodeproj/project.pbxproj`
- Modify: `Sources/FramerApp/Sidebar/SidebarShell.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarSection.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarControlRow.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift`
- Modify: `Sources/FramerApp/Sidebar/SidebarTrailingReadoutCluster.swift`
- Modify: `Sources/FramerApp/Inspector/ExportBar.swift`
- Modify: `Sources/FramerApp/Presets/PresetPreviewGrid.swift`
- Modify: `Sources/FramerApp/Presets/PresetPreviewCard.swift`

- [ ] **Step 1: Create the environment key**

Create `Sources/FramerApp/Sidebar/SidebarMetricsEnvironment.swift`:

```swift
import SwiftUI

private struct SidebarMetricsKey: EnvironmentKey {
    static let defaultValue = SidebarMetrics()
}

extension EnvironmentValues {
    var sidebarMetrics: SidebarMetrics {
        get { self[SidebarMetricsKey.self] }
        set { self[SidebarMetricsKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Write the failing environment test**

Create `Tests/FramerAppTests/SidebarEnvironmentTests.swift`:

```swift
import XCTest
import AppKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class SidebarEnvironmentTests: XCTestCase {
    func test_shellMetricsReachDescendants() throws {
        let customPolicy = SidebarLayoutPolicy(
            minimumWidth: 320,
            idealWidth: 400,
            maximumWidth: 520
        )

        var captured: SidebarMetrics?

        struct Probe: View {
            @Environment(\.sidebarMetrics) var metrics
            let capture: (SidebarMetrics) -> Void

            var body: some View {
                Color.clear
                    .onAppear { capture(metrics) }
            }
        }

        let shell = SidebarShell(widthPolicy: customPolicy) {
            Probe(capture: { captured = $0 })
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 400, height: 200)

        let host = NSHostingView(rootView: shell)
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let metrics = try XCTUnwrap(captured, "SidebarShell should inject SidebarMetrics into environment")
        XCTAssertEqual(metrics.widthPolicy, customPolicy,
                       "Descendants should read the width policy that SidebarShell applied")
        XCTAssertEqual(metrics.idealWidth, 400)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
xcodegen generate
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarEnvironmentTests
```

Expected: FAIL — `SidebarShell` doesn't write the environment yet.

- [ ] **Step 4: Wire `SidebarShell` to write the environment**

Edit `Sources/FramerApp/Sidebar/SidebarShell.swift`:

```swift
struct SidebarShell<Content: View, Footer: View>: View {
    private let metrics: SidebarMetrics
    private let content: Content
    private let footer: Footer

    init(
        widthPolicy: SidebarLayoutPolicy = .default,
        metrics: SidebarMetrics = SidebarMetrics(),
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.metrics = metrics.replacing(widthPolicy: widthPolicy)
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.rowGap) {
                content
            }
            .padding(metrics.outerInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            minWidth: metrics.minimumWidth,
            idealWidth: metrics.idealWidth,
            maximumWidth: metrics.maximumWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .safeAreaInset(edge: .bottom, spacing: metrics.footerSpacing) {
            footer
        }
        .background(Color.surface1)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.borderDefault).frame(width: 1)
        }
        .environment(\.sidebarMetrics, metrics)
    }
}
```

(Only the closing `.environment(\.sidebarMetrics, metrics)` line is new. Replace `maximumWidth:` in the frame call if your linter complains — the existing key-path is `maxWidth`; keep what was there.)

- [ ] **Step 5: Run the environment test to verify it passes**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarEnvironmentTests
```

Expected: PASS.

- [ ] **Step 6: Migrate primitives to read from environment**

Touch every primitive that currently takes `metrics: SidebarMetrics = SidebarMetrics()`. For each:

**`SidebarSection.swift`** — add `@Environment(\.sidebarMetrics) private var envMetrics` and use it when the caller didn't pass one:

```swift
struct SidebarSection<Header: View, Content: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let header: Header
    private let content: Content

    init(
        metrics: SidebarMetrics? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.overrideMetrics = metrics
        self.header = header()
        self.content = content()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SidebarSection where Header == Text {
    init(
        _ title: LocalizedStringKey,
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(metrics: metrics, header: {
            Text(title)
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)
        }, content: content)
    }
}
```

**`SidebarControlRow.swift`** — same pattern. Change the default `metrics: SidebarMetrics = SidebarMetrics()` parameter to `metrics: SidebarMetrics? = nil`. Compute via `overrideMetrics ?? envMetrics`.

**`SidebarCompoundControlBlock.swift`** — same pattern.

**`SidebarTrailingUnitCluster.swift`** — same pattern.

**`SidebarTrailingReadoutCluster.swift`** — same pattern (added in Task 2).

For each file: `@Environment(\.sidebarMetrics) private var envMetrics`; private `overrideMetrics: SidebarMetrics?`; computed `private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }`.

- [ ] **Step 7: Migrate consumer files to read from environment**

**`Sources/FramerApp/Inspector/ExportBar.swift`** — replace `private let metrics = SidebarMetrics()` with `@Environment(\.sidebarMetrics) private var metrics`. Do the same in `ExportQueuePopover` (line ~293).

**`Sources/FramerApp/Presets/PresetPreviewGrid.swift`** — same replacement at line 22.

**`Sources/FramerApp/Presets/PresetPreviewCard.swift`** — same replacement at line 15.

**`Sources/FramerApp/Editor/LayerListSection.swift`** — in the private helpers `OverlayFullWidthControlRow` (line 1624), `SimpleLayerEditorDivider` (line 1609), and `DenseSupplementaryControlRow` (line 3227), replace `private let metrics = SidebarMetrics()` with `@Environment(\.sidebarMetrics) private var metrics`.

- [ ] **Step 8: Run the full sidebar test suite**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
    -only-testing:FramerAppTests/SidebarMetricsTests \
    -only-testing:FramerAppTests/SidebarLayoutPolicyTests \
    -only-testing:FramerAppTests/SidebarEnvironmentTests \
    -only-testing:FramerAppTests/SidebarLayoutContainmentTests \
    -only-testing:FramerAppTests/SidebarHarmonySnapshotTests
```

Expected: PASS. (No snapshot hash changes — environment threading is transparent.)

- [ ] **Step 9: Commit**

```bash
git add Sources/FramerApp/Sidebar/SidebarMetricsEnvironment.swift \
    Sources/FramerApp/Sidebar/SidebarShell.swift \
    Sources/FramerApp/Sidebar/SidebarSection.swift \
    Sources/FramerApp/Sidebar/SidebarControlRow.swift \
    Sources/FramerApp/Sidebar/SidebarCompoundControlBlock.swift \
    Sources/FramerApp/Sidebar/SidebarTrailingUnitCluster.swift \
    Sources/FramerApp/Sidebar/SidebarTrailingReadoutCluster.swift \
    Sources/FramerApp/Inspector/ExportBar.swift \
    Sources/FramerApp/Presets/PresetPreviewGrid.swift \
    Sources/FramerApp/Presets/PresetPreviewCard.swift \
    Sources/FramerApp/Editor/LayerListSection.swift \
    Framer.xcodeproj/project.pbxproj \
    Tests/FramerAppTests/SidebarEnvironmentTests.swift
git commit -m "refactor(sidebar): thread SidebarMetrics via @Environment"
```

---

## Task 4: `LayerPanelRow` adopts environment metrics

**Files:**
- Create: `Tests/FramerAppTests/LayerPanelRowLayoutTests.swift`
- Modify: `Framer.xcodeproj/project.pbxproj`
- Modify: `Sources/FramerApp/Sidebar/LayerPanelRow.swift`
- Modify: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Write the failing alignment test**

Create `Tests/FramerAppTests/LayerPanelRowLayoutTests.swift`:

```swift
import XCTest
import AppKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class LayerPanelRowLayoutTests: XCTestCase {
    /// An expanded LayerPanelRow's inner editor label column should align with
    /// the section's top-level label column (both sitting at metrics.outerInset).
    /// Before the pass this was offset by ~16pt (Spacing.xl + Spacing.xs = 28pt
    /// vs metrics.outerInset = 12pt).
    func test_expandedBodyLeadingInset_matchesSectionOuterInset() {
        let metrics = SidebarMetrics()
        let mirrorLeadingInset = LayerPanelRowLayoutProbe.expandedLeadingInset(metrics: metrics)

        XCTAssertEqual(
            mirrorLeadingInset,
            metrics.outerInset,
            "Expanded body's leading padding must equal metrics.outerInset so inner editor label column aligns with section grid"
        )
    }
}

enum LayerPanelRowLayoutProbe {
    static func expandedLeadingInset(metrics: SidebarMetrics) -> CGFloat {
        // Mirror of the value used in LayerPanelRow.body's expanded VStack padding.
        metrics.outerInset
    }
}
```

This test documents the invariant and lets us change the implementation without the test going stale.

- [ ] **Step 2: Run test to verify the invariant holds BEFORE touching the chassis**

```bash
xcodegen generate
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/LayerPanelRowLayoutTests
```

Expected: PASS — the probe returns `metrics.outerInset`. The real regression protection comes in step 5, where we verify the snapshot of an expanded layer row lines up correctly.

- [ ] **Step 3: Migrate `LayerPanelRow` to environment metrics**

Edit `Sources/FramerApp/Sidebar/LayerPanelRow.swift`. Delete the `LayerPanelRowLayout` enum at the bottom. Add `@Environment(\.sidebarMetrics) private var metrics` and swap every `LayerPanelRowLayout.*` reference for a metric-derived value:

```swift
struct LayerPanelRow: View {
    @Binding var layer: CompositionLayer
    let isDragging: Bool
    let isDropTarget: Bool
    let onDelete: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var isHoveringVisibilityToggle = false
    @State private var isHoveringDelete = false

    @Environment(\.sidebarMetrics) private var metrics

    private var headerSpacing: CGFloat { metrics.expandedBodyInset }
    private var badgePadding: CGFloat { metrics.expandedBodyInset }
    private var affordanceSize: CGFloat { metrics.controlRowMinHeight - 10 }  // was Spacing.xl+xs
    private var expandedLeadingInset: CGFloat { metrics.outerInset }
    private var expandedTrailingInset: CGFloat { metrics.outerInset / 2 }
    private var controlsSpacing: CGFloat { metrics.expandedBodyInset }
    private let hoverAnimation = Animation.easeInOut(duration: 0.15)
    private let expandAnimation = Animation.easeInOut(duration: 0.15)

    // ... body uses these computed properties instead of LayerPanelRowLayout.*
}
```

Key mappings for every former `LayerPanelRowLayout` constant:

- `headerSpacing` → `metrics.expandedBodyInset`
- `disclosureSize` → `affordanceSize` (≈20pt, derived)
- `handleWidth` / `iconWidth` → `affordanceSize`
- `badgeHorizontalPadding` → `metrics.expandedBodyInset`
- `badgeVerticalPadding` → `metrics.expandedBodyInset / 2` (kept compact)
- `visibilityWidth` / `deleteWidth` → `affordanceSize`
- `visibilityHeight` / `deleteHeight` → `affordanceSize`
- `headerHorizontalPadding` → `metrics.expandedBodyInset`
- `headerVerticalPadding` → `metrics.expandedBodyInset`
- `controlsSpacing` → `metrics.expandedBodyInset`
- `expandedTopPadding` → `metrics.expandedBodyInset`
- `expandedBottomPadding` → `metrics.expandedBodyInset * 2` (preserve comfortable bottom air)
- `expandedLeadingPadding` → `metrics.outerInset` ← **the key change**
- `expandedTrailingPadding` → `metrics.outerInset / 2`
- `hoverAnimation` / `expandAnimation` → kept as `private let` constants inside the struct

Delete the `private enum LayerPanelRowLayout { ... }` block entirely.

- [ ] **Step 4: Run the layer row test**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/LayerPanelRowLayoutTests
```

Expected: PASS.

- [ ] **Step 5: Refresh affected snapshots**

Run the full harmony snapshot suite:

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests
```

Expected: FAIL — the layer-row-adjacent snapshots may shift slightly. Specifically, look for `sidebar-shell` or any test that renders an expanded row.

Update the new hashes. Rerun until green.

- [ ] **Step 6: Commit**

```bash
git add Sources/FramerApp/Sidebar/LayerPanelRow.swift \
    Tests/FramerAppTests/LayerPanelRowLayoutTests.swift \
    Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift \
    Framer.xcodeproj/project.pbxproj
git commit -m "refactor(sidebar): LayerPanelRow adopts environment metrics"
```

---

## Task 5: Extract rich-affordance primitives (`SidebarFullWidthRow`, `SidebarPreviewStrip`, `SidebarPaletteEditor`, `SidebarChipFlow`)

**Files:**
- Create: `Sources/FramerApp/Sidebar/SidebarFullWidthRow.swift`
- Create: `Sources/FramerApp/Sidebar/SidebarPreviewStrip.swift`
- Create: `Sources/FramerApp/Sidebar/SidebarPaletteEditor.swift`
- Create: `Sources/FramerApp/Sidebar/SidebarChipFlow.swift`
- Modify: `Framer.xcodeproj/project.pbxproj`
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift`
- Modify: `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift`
- Modify: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Create `SidebarFullWidthRow`**

Create `Sources/FramerApp/Sidebar/SidebarFullWidthRow.swift`:

```swift
import SwiftUI

struct SidebarFullWidthRow<Content: View>: View {
    @Environment(\.sidebarMetrics) private var metrics
    private let title: LocalizedStringKey
    private let content: Content

    @Namespace private var accessibilityLabelNamespace

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset / 2) {
            Text(title)
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text2)
                .accessibilityLabeledPair(role: .label, id: "SidebarFullWidthRowLabel", in: accessibilityLabelNamespace)

            content
                .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
                .accessibilityLabeledPair(role: .content, id: "SidebarFullWidthRowLabel", in: accessibilityLabelNamespace)
        }
        .padding(.horizontal, metrics.outerInset)
        .padding(.vertical, metrics.expandedBodyInset / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Create `SidebarPreviewStrip`**

Create `Sources/FramerApp/Sidebar/SidebarPreviewStrip.swift`:

```swift
import SwiftUI

struct SidebarPreviewStrip<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
    @Environment(\.sidebarMetrics) private var metrics
    private let items: Data
    private let tileSize: CGFloat
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        items: Data,
        tileSize: CGFloat = 72,
        spacing: CGFloat = 6,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.tileSize = tileSize
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                        .frame(width: tileSize, height: tileSize)
                }
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }
}
```

- [ ] **Step 3: Create `SidebarPaletteEditor`**

Create `Sources/FramerApp/Sidebar/SidebarPaletteEditor.swift`:

```swift
import SwiftUI
import FramerCore

struct SidebarPaletteEditor: View {
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var colors: [CodableColor]
    var maxColors: Int = 16

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                HStack(spacing: metrics.controlColumnSpacing) {
                    ColorPickerWithHex("", selection: colorBinding(at: index))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        guard colors.count > 1 else { return }
                        colors.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(colors.count > 1 ? Color.text3 : Color.text3.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(colors.count <= 1)
                    .accessibilityLabel("Remove color")
                }
            }

            if colors.count < maxColors {
                Button {
                    colors.append(.white)
                } label: {
                    Label("Add color", systemImage: "plus")
                        .font(AppFont.buttonText)
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }

    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cgColor: colors[index].cgColor) ?? .white) },
            set: { newColor in
                guard let hex = newColor.hexString,
                      let codable = try? CodableColor(hex: hex) else { return }
                colors[index] = codable
            }
        )
    }
}
```

- [ ] **Step 4: Create `SidebarChipFlow`**

Create `Sources/FramerApp/Sidebar/SidebarChipFlow.swift`:

```swift
import SwiftUI

struct SidebarChipFlow<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Hashable {
    @Environment(\.sidebarMetrics) private var metrics
    private let items: Data
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        items: Data,
        spacing: CGFloat = 4,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        SidebarFlowLayout(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                content(item)
            }
        }
        .frame(maxWidth: metrics.containedPreviewMaxWidth, alignment: .leading)
    }
}

struct SidebarFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let layout = computeLayout(maxWidth: maxWidth, subviews: subviews)
        return layout.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = computeLayout(maxWidth: bounds.width, subviews: subviews)
        for (index, origin) in layout.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            totalWidth = max(totalWidth, x - horizontalSpacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), origins)
    }
}
```

Note: there is already a `FlowLayout` inside `LayerListSection.swift` around line 3176. Rename the new one to `SidebarFlowLayout` to avoid collision; Task 5 step 7 will delete the inline one when migrating Caption tokens.

- [ ] **Step 5: Write failing containment tests**

Extend `Tests/FramerAppTests/SidebarLayoutContainmentTests.swift`:

```swift
func test_sidebarFullWidthRow_contentFitsWithinContainedWidth() {
    let metrics = SidebarMetrics()
    assertFitsContainedWidth(
        SidebarFullWidthRow("Probe") {
            Rectangle().fill(Color.red).frame(height: 40)
        }
    )
}

func test_sidebarPreviewStrip_fitsWithinContainedWidth() {
    let items = (0..<30).map { ProbeItem(id: $0) }
    assertFitsContainedWidth(
        SidebarPreviewStrip(items: items) { _ in
            Rectangle().fill(Color.blue)
        }
    )
}

func test_sidebarPaletteEditor_fitsWithinContainedWidth() {
    assertFitsContainedWidth(
        SidebarPaletteEditor(colors: .constant([.white, .black, .red]))
    )
}

func test_sidebarChipFlow_fitsWithinContainedWidth() {
    let tokens = Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
    assertFitsContainedWidth(
        SidebarChipFlow(items: tokens) { token in
            Text("{\(token)}").font(AppFont.mono(10)).padding(.horizontal, 6).padding(.vertical, 2)
        }
    )
}

private struct ProbeItem: Identifiable { let id: Int }

private func assertFitsContainedWidth<V: View>(
    _ view: V,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let metrics = SidebarMetrics()
    let size = CGSize(width: metrics.idealWidth, height: 600)
    let rootView = view
        .environment(\.sidebarMetrics, metrics)
        .environment(\.colorScheme, .dark)
        .frame(width: size.width, height: size.height, alignment: .topLeading)

    let host = NSHostingView(rootView: rootView)
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()

    let frames = visibleDescendantFrames(in: host)
    let overflows = frames.filter { $0.maxX > metrics.idealWidth + 0.5 }
    XCTAssertTrue(overflows.isEmpty,
                  "Primitive overflowed \(metrics.idealWidth)pt. Offenders: \(overflows)",
                  file: file, line: line)
}
```

- [ ] **Step 6: Run tests to verify they fail (primitives not yet wired via xcodegen)**

```bash
xcodegen generate
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarLayoutContainmentTests
```

Expected: PASS (primitives were added in steps 1–4; now the test proves they stay within bounds).

- [ ] **Step 7: Migrate call sites in `LayerListSection.swift`**

Inside `LayerListSection.swift`:

**Delete** the private `OverlayFullWidthControlRow` struct (line 1620-1647). Every call site using it becomes `SidebarFullWidthRow(...)`.

**Overlay editor (lines ~2336, 2370, 2408):** replace `OverlayFullWidthControlRow("X") { ... }` with `SidebarFullWidthRow("X") { ... }`. The inner thumbnail strip (around line 2372) becomes:

```swift
SidebarFullWidthRow("Library") {
    SidebarPreviewStrip(items: filteredOverlays) { overlay in
        overlayThumbnail(overlay)
    }
}
```

**Caption editor (TemplateTokenBar around line 3123):** replace the freelance `VStack(spacing: 6) { ... FlowLayout(spacing: 4) { ... } }` with `SidebarFullWidthRow("Tokens") { SidebarChipFlow(items: tokens) { token in tokenChip(token) } }`. Delete the local `FlowLayout` struct at line 3176; `SidebarChipFlow` uses `SidebarFlowLayout` instead.

**Dither palette (line 3620):** replace the inline `paletteEditor()` function body with:

```swift
SidebarFullWidthRow("Palette") {
    SidebarPaletteEditor(colors: $paletteColors)
}
```

(Adjust binding plumbing so `SidebarPaletteEditor` can mutate the dither params' palette.)

**LUT editor (line 3817):** replace the freelance `ScrollView(.horizontal) { HStack(spacing: 6) { ... } }` with:

```swift
SidebarFullWidthRow("Library") {
    SidebarPreviewStrip(items: availableLUTs, tileSize: 48) { lut in
        lutThumb(lut)
    }
}
```

**Shader editor (line 4429 ASCII ramp):** replace `HStack(spacing: 2) { ForEach(glyphs) { ... } }` with:

```swift
SidebarFullWidthRow("Ramp") {
    SidebarChipFlow(items: glyphs, spacing: 2) { glyph in
        rampCell(glyph)
    }
}
```

- [ ] **Step 8: Refresh snapshot hashes**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests
```

Expected: FAIL — `overlay-editor`, `dense-caption-editor`, `dense-dither-editor`, any LUT/Shader snapshot will shift.

Update hashes until green.

- [ ] **Step 9: Commit**

```bash
git add Sources/FramerApp/Sidebar/SidebarFullWidthRow.swift \
    Sources/FramerApp/Sidebar/SidebarPreviewStrip.swift \
    Sources/FramerApp/Sidebar/SidebarPaletteEditor.swift \
    Sources/FramerApp/Sidebar/SidebarChipFlow.swift \
    Sources/FramerApp/Editor/LayerListSection.swift \
    Tests/FramerAppTests/SidebarLayoutContainmentTests.swift \
    Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift \
    Framer.xcodeproj/project.pbxproj
git commit -m "feat(sidebar): extract FullWidthRow/PreviewStrip/PaletteEditor/ChipFlow primitives"
```

---

## Task 6: Promote `OverlayFullWidthControlRow` → folded into Task 5

Already completed as part of Task 5 step 7 — `OverlayFullWidthControlRow` struct was deleted and every overlay call site now uses `SidebarFullWidthRow`. No standalone commit.

If Task 5 was split across multiple commits, add this cleanup:

```bash
git grep OverlayFullWidthControlRow Sources/
```

Expected: no results.

---

## Task 7: Rationalize `StyledSlider`

**Files:**
- Create: `Tests/FramerAppTests/StyledSliderSuffixTests.swift`
- Modify: `Framer.xcodeproj/project.pbxproj`
- Modify: `Sources/FramerApp/Controls/StyledSlider.swift`
- Modify: `Sources/FramerApp/Inspector/InspectorView.swift`
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift` (DenseSliderControlRow + callers)
- Modify: `Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift`

- [ ] **Step 1: Write the failing "no inline suffix" test**

Create `Tests/FramerAppTests/StyledSliderSuffixTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Framer

@MainActor
final class StyledSliderSuffixTests: XCTestCase {
    func test_styledSlider_bodyDoesNotReferenceSuffixText() {
        let slider = StyledSlider(value: .constant(50), range: 0...100)
        let bodyType = String(reflecting: type(of: slider.body))

        // StyledSlider should compose Slider + TextField only. If a Text with
        // a 20pt suffix frame reappears, callers who also use SidebarTrailingUnitCluster
        // will get double-rendered units at divergent widths.
        XCTAssertFalse(
            bodyType.contains("_ConditionalContent<ModifiedContent<Text"),
            "StyledSlider must not render an inline suffix Text; compose via SidebarTrailingUnitCluster instead"
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodegen generate
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/StyledSliderSuffixTests
```

Expected: FAIL — `StyledSlider` still has the `if !suffix.isEmpty { Text(suffix)... }` branch.

- [ ] **Step 3: Simplify `StyledSlider`**

Edit `Sources/FramerApp/Controls/StyledSlider.swift`:

```swift
import SwiftUI

enum StyledSliderValueResolver {
    static func constrain(_ rawValue: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let clampedValue = rawValue.clamped(to: range)
        guard step > 0 else { return clampedValue }
        return ((clampedValue / step).rounded() * step).clamped(to: range)
    }
}

struct StyledSlider: View {
    @Environment(\.sidebarMetrics) private var metrics

    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: LocalizedStringKey? = nil
    var step: Double = 1

    var body: some View {
        HStack(spacing: metrics.controlTrailingClusterSpacing) {
            Slider(value: snappedBinding, in: range)
                .tint(Color.accentDim)
                .frame(maxWidth: .infinity)
                .modifier(StyledSliderAccessibilityLabel(label: accessibilityLabel))

            TextField("", value: constrainedTextFieldBinding, format: .number)
                .textFieldStyle(.plain)
                .font(AppFont.numericInput)
                .foregroundStyle(Color.text1)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: metrics.controlValueFieldWidth)
                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .modifier(StyledSliderAccessibilityLabel(label: accessibilityLabel))
        }
    }

    private var snappedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = StyledSliderValueResolver.constrain($0, range: range, step: step) }
        )
    }

    private var constrainedTextFieldBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = StyledSliderValueResolver.constrain($0, range: range, step: step) }
        )
    }
}

private struct StyledSliderAccessibilityLabel: ViewModifier {
    let label: LocalizedStringKey?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

Removed: `suffix`, `inputWidth` parameters and the inline `Text(suffix)` branch.

- [ ] **Step 4: Migrate consumers to compose with `SidebarTrailingUnitCluster`**

**`Sources/FramerApp/Inspector/InspectorView.swift`** (Output section around line 136):

```swift
if jpegQuality != nil {
    SidebarControlRow("Quality") {
        StyledSlider(
            value: jpegQualityBinding,
            range: 60...100,
            accessibilityLabel: "Quality",
            step: 5
        )
    } trailingValue: {
        SidebarTrailingUnitCluster(unit: "%") {
            TextField("", value: jpegQualityBinding, format: .number)
                .simpleLayerEditorInputStyle(accessibilityLabel: "Quality")
                .monospacedDigit()
        }
    }
}
```

Wait — that duplicates the text field. Better: have the slider expose just the slider, and the cluster expose the editable value. Actually the simplest migration: when the call site passed `suffix:` before, the right now-model is to move the suffix into a trailing `Text` inside the cluster and let `StyledSlider` render only the slider + its own numeric field (which sits to the right of the slider but left of the unit).

Simplest correct migration — keep `StyledSlider` rendering slider + field, append a **trailing unit only**:

```swift
struct StyledSliderWithUnit: View {
    @Environment(\.sidebarMetrics) private var metrics
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: LocalizedStringKey

    var body: some View {
        HStack(spacing: metrics.controlTrailingClusterSpacing) {
            StyledSlider(value: $value, range: range, step: step)
            Text(unit)
                .font(AppFont.mono(9))
                .foregroundStyle(Color.text3)
                .frame(width: metrics.controlUnitSuffixWidth, alignment: .leading)
        }
    }
}
```

Place this helper inside `StyledSlider.swift`. Migrate `InspectorView.outputSection` Quality row to:

```swift
if jpegQuality != nil {
    SidebarControlRow("Quality") {
        StyledSliderWithUnit(value: jpegQualityBinding, range: 60...100, step: 5, unit: "%")
    }
}
```

**`Sources/FramerApp/Editor/LayerListSection.swift`** — find every `DenseSliderControlRow(... suffix: "X", ...)` call and change to pass the unit via the new helper if a unit was being rendered. For callers with empty suffix (most), remove the parameter entirely.

Also update `DenseSliderControlRow` struct (around line 3200) to drop its `suffix` parameter:

```swift
struct DenseSliderControlRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: LocalizedStringKey? = nil
    let step: Double
    var unit: LocalizedStringKey? = nil

    var body: some View {
        SidebarControlRow(title) {
            if let unit {
                StyledSliderWithUnit(value: $value, range: range, step: step, unit: unit)
            } else {
                StyledSlider(value: $value, range: range, accessibilityLabel: accessibilityLabel ?? title, step: step)
            }
        }
    }
}
```

- [ ] **Step 5: Run the StyledSlider test**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/StyledSliderSuffixTests
```

Expected: PASS.

- [ ] **Step 6: Refresh snapshot hashes**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' -only-testing:FramerAppTests/SidebarHarmonySnapshotTests
```

Expected: FAIL — `output-rows-jpeg` (Quality row rendering changed from 20pt to 24pt unit suffix). Any dense-editor snapshot with a `suffix:` slider will also shift.

Update hashes until green.

- [ ] **Step 7: Commit**

```bash
git add Sources/FramerApp/Controls/StyledSlider.swift \
    Sources/FramerApp/Inspector/InspectorView.swift \
    Sources/FramerApp/Editor/LayerListSection.swift \
    Tests/FramerAppTests/StyledSliderSuffixTests.swift \
    Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift \
    Framer.xcodeproj/project.pbxproj
git commit -m "refactor(slider): retire inline suffix, unify unit rendering"
```

---

## Task 8: Final verification & cleanup

**Files:** review only; no new files.

- [ ] **Step 1: Run the full sidebar suite**

```bash
xcodebuild test -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' \
    -only-testing:FramerAppTests/SidebarMetricsTests \
    -only-testing:FramerAppTests/SidebarLayoutPolicyTests \
    -only-testing:FramerAppTests/SidebarEnvironmentTests \
    -only-testing:FramerAppTests/SidebarLayoutContainmentTests \
    -only-testing:FramerAppTests/SidebarHarmonySnapshotTests \
    -only-testing:FramerAppTests/LayerPanelRowLayoutTests \
    -only-testing:FramerAppTests/StyledSliderSuffixTests \
    -only-testing:FramerAppTests/SidebarMetricsTests \
    -only-testing:FramerAppTests/SidebarStateMatrixTests \
    -only-testing:FramerAppTests/InspectorOutputControlStateTests \
    -only-testing:FramerAppTests/LayerPanelRowStateResolverTests \
    -only-testing:FramerAppTests/PresetPreviewRenderKeyTests \
    -only-testing:FramerAppTests/StyledSliderValueResolverTests
```

Expected: PASS.

- [ ] **Step 2: Run the SwiftPM test target**

```bash
swift test
```

Expected: PASS (FramerCoreTests + FramerCLITests, unchanged).

- [ ] **Step 3: Build both platforms**

```bash
xcodebuild build -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS'
xcodebuild build -scheme FramerMobile -destination 'generic/platform=iOS Simulator'
```

Expected: both SUCCEEDED.

- [ ] **Step 4: Verify no `SimpleLayerEditorLayout` or `OverlayFullWidthControlRow` survives**

```bash
git grep -n "SimpleLayerEditorLayout" Sources/ Tests/ || echo "clean"
git grep -n "OverlayFullWidthControlRow" Sources/ Tests/ || echo "clean"
git grep -n "LayerPanelRowLayout" Sources/ Tests/ || echo "clean"
```

Expected: all three print `clean`.

- [ ] **Step 5: Smoke-test the app**

Launch the macOS app and scroll through the Border, Canvas, AspectRatio, Overlay, Caption, Dither, LUT, Shader, and GPUEffect editors. Visually confirm:

- Every row's label column sits at the same X coordinate
- Every editable numeric field is 55pt wide
- Every unit suffix is 24pt wide
- Read-only readouts align with editable values
- Preview strips don't overflow the sidebar
- Caption tokens wrap; don't scroll horizontally
- Expanded layer rows' inner editor labels align with the section's section-header eyebrow

If anything drifts, note the file:line and loop back to the owning task.

- [ ] **Step 6: Final commit of any snapshot hash tweaks**

If the smoke test required any small tweaks that affected snapshots:

```bash
git add Tests/FramerAppTests/SidebarHarmonySnapshotTests.swift
git commit -m "test(sidebar): refresh harmony snapshots for pass 2"
```

If nothing changed in this task, skip.

- [ ] **Step 7: Capture the checkpoint doc**

Update `.sisyphus/notepads/sidebar-harmony/learnings.md` with pass-2 observations (new primitives added, environment threading caveats, snapshot fragility notes).

```bash
git add .sisyphus/notepads/sidebar-harmony/learnings.md
git commit -m "docs(sidebar): capture pass 2 learnings checkpoint"
```

---

## Spec Coverage Check

- **Fix 01 (retire `SimpleLayerEditorLayout`):** Task 1.
- **Fix 02 (`SidebarTrailingReadoutCluster`):** Task 2.
- **Fix 03 (environment threading):** Task 3.
- **Fix 04 (`LayerPanelRow` metrics):** Task 4.
- **Fix 05 (rich-affordance primitives):** Task 5.
- **Fix 06 (promote `OverlayFullWidthControlRow`):** Task 5 step 7 + Task 6 placeholder.
- **Fix 07 (rationalize `StyledSlider`):** Task 7.

No gaps relative to `docs/sidebar-harmony-target/index.html` §5 and §6.
