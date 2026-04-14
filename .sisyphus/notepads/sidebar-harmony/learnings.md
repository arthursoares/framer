# sidebar-harmony learnings

- `project.yml:19-52` defines the macOS app target as `Framer`, sourced from `Sources/FramerApp`, with no sibling test target today.
- `project.yml:88-105` only wires `build`, `run`, and `archive` for the `Framer` scheme; there is no `test` action or test bundle list yet.
- Existing tests are SwiftPM-only: `Package.swift:15-65` declares `FramerCoreTests` and `FramerCLITests` as `.testTarget`s, and there are no XcodeGen test targets in `project.yml`.
- The repo’s test-bundle naming convention is `Tests/<TargetName>Tests/` (for example `Tests/FramerCoreTests/FrameProcessorTests.swift:1-5` and `Tests/FramerCLITests/ProcessCommandTests.swift:1-5`), with `import XCTest` plus `@testable import <Module>`.
- `Tests/FramerCoreTests/FrameProcessorTests.swift:1-8` shows a test bundle resource pattern via `Bundle.module` and copied test resources, while `Tests/FramerCLITests/ProcessCommandTests.swift:1-4` shows a lean logic-only bundle with multiple `@testable` imports.
- For a future `FramerAppTests`, the least-surprise fit is a new `Tests/FramerAppTests/` folder and a matching XcodeGen test target wired into the `Framer` scheme, while remembering the app module itself is named `Framer`, not `FramerApp`.

- Desktop sidebar width is currently hard-coded in `Sources/FramerApp/ContentView.swift:14-20` (`InspectorView().frame(width: 320)`), so this is the single fixed-width anchor for the macOS sidebar area.
- Sidebar-adjacent state vocabulary already present:
  - `Sources/FramerApp/App/AppState.swift:7-22,34-36,220-232` (`selectedItems`, `selectedPhoto`, `exportQueue`, `ExportJob.JobStatus` = `queued/running/done/cancelled/failed`)
  - `Sources/FramerApp/Inspector/InspectorView.swift:11-16,49-60` (`activePresetName`, `isPresetModified`, clear preset action)
  - `Sources/FramerApp/Inspector/ExportBar.swift:7-11,49-59,106-131,194-296,357-380` (`showingExportSheet`, `showingQueuePopover`, `selectedPresetIDs`, `includeCurrentSettings`, queue popover, export sheet, job status icon mapping)
  - `Sources/FramerApp/Presets/PresetPreviewGrid.swift:20-29,107-108,219-232` (`isActive`, `activePresetName`, `appliedPresetConfig`)
  - `Sources/FramerApp/Editor/LayerListSection.swift:2296-2330` (`selectedKind` for overlay categories)
- `320` also appears in `Sources/FramerApp/Presets/PresetPreviewGrid.swift:159` as `compactPreviewMaxDimension`, but that is preview rendering, not sidebar width.
- The current `Sources/FramerApp/` layout has no `Sidebar/` folder; safest new home for a pure-Swift sidebar policy is `Sources/FramerApp/Sidebar/SidebarLayoutPolicy.swift`, with sidebar-state tests living nearby under `Tests/...` once Task 2 starts.

- Task 1 harness gotcha: `FramerAppTests` needs the same `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE` settings as the `Framer` app target in `project.yml`; without that, `xcodebuild test` builds the bundle but macOS refuses to load it into `Framer.app` because of a Team ID mismatch.
- Keeping `SidebarLayoutPolicy`, `SidebarState`, and `SidebarStateMatrix` in one pure-Swift file under `Sources/FramerApp/Sidebar/` let the new app tests codify the approved `304 / 320 / 352` width band and sidebar-only state vocabulary without touching any visible SwiftUI layout yet.

- Task 2 establishes `SidebarMetrics` as the sidebar-local source of truth for the current shell rhythm (`outerInset = 12`, `rowGap = 16`, `expandedBodyInset = 8`, `footerSpacing = 0`) while delegating width clamping back to `SidebarLayoutPolicy` so the width band still lives in one place.
- `SidebarShell` can safely mirror the current inspector chrome without migrating consumers yet: it packages the `ScrollView`, leading 1pt border, `surface1` background, bottom `safeAreaInset`, and min/ideal/max width frame in one sidebar-scoped primitive.
- A narrow `SidebarMetricsTests` app test is a good TDD seam for future sidebar shell work because it verifies metrics/policy interplay without needing a SwiftUI view-inspection dependency.
- Task 3 gotcha: adding new files under `Sources/FramerApp/Sidebar/` required rerunning `xcodegen generate` before `xcodebuild test`, because the checked-in `Framer.xcodeproj` did not automatically pick up new sidebar source files.
- `SidebarStateStyle` works well as a pure value type with nested semantic enums (`Background`, `Border`, `Foreground`) plus computed SwiftUI colors; that keeps the approved state matrix testable without forcing early consumer migration or view-inspection dependencies.
