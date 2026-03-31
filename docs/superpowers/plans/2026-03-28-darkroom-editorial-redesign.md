# Darkroom Editorial Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the FramerApp from a 3-column NavigationSplitView with system chrome into a 2-column dark "Darkroom Editorial" interface with floating filmstrip, visual preset previews, and custom controls.

**Architecture:** Replace NavigationSplitView with flat HStack(CanvasView + InspectorView). Photo browsing moves from sidebar list to floating filmstrip. Presets become visual thumbnail grid. All views adopt custom dark token system. No changes to FramerCore or data models.

**Tech Stack:** Swift 5.10, SwiftUI (macOS 14+), FramerCore, XcodeGen

**Spec:** `docs/superpowers/specs/2026-03-28-darkroom-editorial-redesign.md`
**Briefing:** `assets/design/DESIGN_BRIEFING.md`
**Mockup:** `assets/design/framer-final-concept.html`

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/FramerApp/Theme/DesignTokens.swift` | Color constants, font helpers, spacing values |
| `Sources/FramerApp/Canvas/CanvasView.swift` | Main viewport: preview image, before/after, drop zone, EXIF bar |
| `Sources/FramerApp/Canvas/FilmstripView.swift` | Floating horizontal photo browser |
| `Sources/FramerApp/Canvas/FilmstripThumbnail.swift` | Individual filmstrip frame |
| `Sources/FramerApp/Inspector/InspectorView.swift` | Right panel: presets, layers, output, export |
| `Sources/FramerApp/Inspector/ExportBar.swift` | Pinned bottom export buttons + queue popover |
| `Sources/FramerApp/Presets/PresetPreviewGrid.swift` | 3-column visual preset grid with rendered thumbnails |
| `Sources/FramerApp/Presets/PresetPreviewCard.swift` | Individual preset card |
| `Sources/FramerApp/Controls/StyledSlider.swift` | Custom slider + numeric input |
| `Sources/FramerApp/Controls/StyledToggle.swift` | Custom toggle switch |
| `Sources/FramerApp/Controls/FormatPicker.swift` | JPEG/PNG pill selector |

### Modified Files
| File | Changes |
|------|---------|
| `Sources/FramerApp/ContentView.swift` | Replace NavigationSplitView → HStack |
| `Sources/FramerApp/App/FramerApp.swift` | Font registration, window size |
| `Sources/FramerApp/Editor/LayerListSection.swift` | Restyle with dark tokens (no logic changes) |
| `project.yml` | Add font resources |

### Deleted Files
| File | Reason |
|------|--------|
| `Sources/FramerApp/Library/LibrarySidebar.swift` | Replaced by FilmstripView + CanvasView toolbar |
| `Sources/FramerApp/Editor/LivePreviewPanel.swift` | Replaced by CanvasView |
| `Sources/FramerApp/Presets/PresetManagerView.swift` | Replaced by PresetPreviewGrid |
| `Sources/FramerApp/Queue/ExportQueueView.swift` | Replaced by ExportBar popover |

### Moved (logic preserved)
| From | To | What moves |
|------|----|------------|
| `LivePreviewPanel.swift` | `CanvasView.swift` | PreviewViewModel usage, onChange handlers, drop handling, ExifInfoBar, EXIFInspectorPopover |
| `LibrarySidebar.swift` | `FilmstripView.swift` | Photo selection binding, openFilePicker(), handleDrop(), removeSelected() |
| `LibrarySidebar.swift` | `CanvasView.swift` | Notification receivers (.framerOpenPhotos, etc.), toolbar add/remove buttons |
| `SettingsPanel.swift` | `InspectorView.swift` | LayerListSection binding, output section, export sheet, all export logic |
| `SettingsPanel.swift` | `ExportBar.swift` | Export buttons, promptAndExport(), directExport() |
| `LibrarySidebar.swift` (SidebarPresetsSection) | `InspectorView.swift` | Preset save/delete/apply, sheets, alerts |
| `LibrarySidebar.swift` (SidebarQueueSection) | `ExportBar.swift` | Queue job list, status icons, clear completed |
| `SettingsPanel.swift` (ColorPickerWithHex) | `Sources/FramerApp/Controls/ColorPickerWithHex.swift` | Extracted unchanged |
| `SettingsPanel.swift` (sliderWithInput) | `StyledSlider.swift` | Restyled as custom control |

---

## Task 1: Design Tokens

**Files:**
- Create: `Sources/FramerApp/Theme/DesignTokens.swift`

- [ ] **Step 1: Create the Theme directory**

```bash
mkdir -p Sources/FramerApp/Theme
```

- [ ] **Step 2: Write DesignTokens.swift**

```swift
import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Surface hierarchy
    static let surface0 = Color(red: 14/255, green: 14/255, blue: 16/255)   // #0E0E10
    static let surface1 = Color(red: 20/255, green: 20/255, blue: 22/255)   // #141416
    static let surface2 = Color(red: 26/255, green: 26/255, blue: 30/255)   // #1A1A1E
    static let surface3 = Color(red: 34/255, green: 34/255, blue: 38/255)   // #222226
    static let surface4 = Color(red: 42/255, green: 42/255, blue: 47/255)   // #2A2A2F

    // Text hierarchy
    static let text0 = Color(red: 240/255, green: 237/255, blue: 232/255)   // #F0EDE8
    static let text1 = Color(red: 184/255, green: 180/255, blue: 173/255)   // #B8B4AD
    static let text2 = Color(red: 125/255, green: 122/255, blue: 116/255)   // #7D7A74
    static let text3 = Color(red: 78/255, green: 76/255, blue: 72/255)      // #4E4C48

    // Accent (warm amber)
    static let accent = Color(red: 212/255, green: 149/255, blue: 106/255)  // #D4956A
    static let accentDim = Color(red: 160/255, green: 104/255, blue: 64/255) // #A06840
    static let accentGlow = Color(red: 212/255, green: 149/255, blue: 106/255).opacity(0.08)
    static let accentSubtle = Color(red: 212/255, green: 149/255, blue: 106/255).opacity(0.15)

    // Functional
    static let success = Color(red: 94/255, green: 159/255, blue: 109/255)  // #5E9F6D
    static let error = Color(red: 199/255, green: 93/255, blue: 93/255)     // #C75D5D

    // Border
    static let borderDefault = Color.white.opacity(0.06)
    static let borderActive = Color.white.opacity(0.12)
}

// MARK: - Typography

enum AppFont {
    /// Atkinson Hyperlegible for UI text
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Atkinson Hyperlegible Next", size: size).weight(weight)
    }

    /// Source Code Pro for data values
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Source Code Pro", size: size).weight(weight)
    }

    // Presets for common uses
    static let sectionHeader = body(10, weight: .semibold)
    static let layerName = body(12, weight: .medium)
    static let controlLabel = body(11)
    static let buttonText = body(11, weight: .semibold)
    static let toggleLabel = body(10, weight: .semibold)

    static let exifChip = mono(10)
    static let hexValue = mono(10)
    static let templateToken = mono(9)
    static let badgeSummary = mono(9)
    static let numericInput = mono(10)
    static let photoCount = mono(10)
    static let brandTitle = mono(12)
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 16
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 10
}
```

- [ ] **Step 3: Build to verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. The tokens are pure definitions with no consumers yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/FramerApp/Theme/DesignTokens.swift
git commit -m "feat: add design tokens for Darkroom Editorial theme"
```

---

## Task 2: Bundle Fonts + Registration

**Files:**
- Create: `assets/fonts/` directory with font files
- Modify: `project.yml` — add fonts as resources
- Modify: `Sources/FramerApp/App/FramerApp.swift` — register fonts at launch

- [ ] **Step 1: Create font directory and download fonts**

```bash
mkdir -p assets/fonts
```

Download from Google Fonts and place in `assets/fonts/`:
- `AtkinsonHyperlegibleNext-Regular.ttf`
- `AtkinsonHyperlegibleNext-Medium.ttf`
- `AtkinsonHyperlegibleNext-SemiBold.ttf`
- `AtkinsonHyperlegibleNext-Bold.ttf`
- `SourceCodePro-Regular.ttf`
- `SourceCodePro-Medium.ttf`

Use `curl` to download from Google Fonts API or manually place them.

- [ ] **Step 2: Add font resources to project.yml**

In `project.yml`, add a new source entry under the `Framer` target sources:

```yaml
    sources:
      - path: Sources/FramerApp
      - path: assets/textures
        type: folder
        buildPhase: resources
      - path: assets/fonts
        type: folder
        buildPhase: resources
```

- [ ] **Step 3: Add font registration in FramerApp.swift**

Replace the full file:

```swift
import SwiftUI
import FramerCore

@main
struct FramerApp: App {
    @State private var appState = AppState()

    init() {
        registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            FramerCommands(appState: appState)
        }

        Settings {
            PreferencesView()
        }
    }

    /// Registers all .ttf and .otf fonts found in the app bundle's Resources.
    private func registerBundledFonts() {
        let extensions = ["ttf", "otf"]
        for ext in extensions {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
```

- [ ] **Step 4: Regenerate Xcode project and build**

```bash
xcodegen generate && swift build 2>&1 | head -20
```

Expected: Build succeeds. Fonts won't render in `swift build` CLI but will register when the app launches via Xcode.

- [ ] **Step 5: Commit**

```bash
git add assets/fonts/ project.yml Sources/FramerApp/App/FramerApp.swift
git commit -m "feat: bundle Atkinson Hyperlegible + Source Code Pro fonts"
```

---

## Task 3: Layout Swap — ContentView Stub

**Files:**
- Modify: `Sources/FramerApp/ContentView.swift`
- Create: `Sources/FramerApp/Canvas/CanvasView.swift` (stub)
- Create: `Sources/FramerApp/Inspector/InspectorView.swift` (stub)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p Sources/FramerApp/Canvas Sources/FramerApp/Inspector
```

- [ ] **Step 2: Create stub CanvasView.swift**

This stub wraps the existing `LivePreviewPanel` so the app still works:

```swift
import SwiftUI
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        LivePreviewPanel()
    }
}
```

- [ ] **Step 3: Create stub InspectorView.swift**

This stub wraps the existing `SettingsPanel`:

```swift
import SwiftUI
import FramerCore

struct InspectorView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        SettingsPanel()
    }
}
```

- [ ] **Step 4: Rewrite ContentView.swift**

Replace the full file:

```swift
import SwiftUI
import FramerCore

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

- [ ] **Step 5: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. The app renders with the existing LivePreviewPanel and SettingsPanel side by side. The sidebar is gone but LibrarySidebar.swift still compiles (just unused). Photos can still be added via menu Cmd+O and drop.

- [ ] **Step 6: Commit**

```bash
git add Sources/FramerApp/ContentView.swift Sources/FramerApp/Canvas/CanvasView.swift Sources/FramerApp/Inspector/InspectorView.swift
git commit -m "feat: swap NavigationSplitView to HStack layout with stubs"
```

---

## Task 4: FilmstripView

**Files:**
- Create: `Sources/FramerApp/Canvas/FilmstripThumbnail.swift`
- Create: `Sources/FramerApp/Canvas/FilmstripView.swift`
- Modify: `Sources/FramerApp/Canvas/CanvasView.swift` — add filmstrip overlay

- [ ] **Step 1: Create FilmstripThumbnail.swift**

```swift
import SwiftUI
import FramerCore

struct FilmstripThumbnail: View {
    let item: PhotoItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        AsyncThumbnail(url: item.url)
            .frame(width: 48, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .rotationEffect(.degrees(Double(item.rotation)))
            .opacity(isSelected ? 1.0 : isHovered ? 0.85 : 0.55)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accent, lineWidth: isSelected ? 1.5 : 0)
            )
            .shadow(color: isSelected ? Color.accent.opacity(0.25) : .clear, radius: 8)
            .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 2: Create FilmstripView.swift**

```swift
import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct FilmstripView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(appState.library) { item in
                            FilmstripThumbnail(
                                item: item,
                                isSelected: appState.selectedItems.contains(item.id)
                            )
                            .id(item.id)
                            .onTapGesture {
                                if NSEvent.modifierFlags.contains(.command) {
                                    if appState.selectedItems.contains(item.id) {
                                        appState.selectedItems.remove(item.id)
                                    } else {
                                        appState.selectedItems.insert(item.id)
                                    }
                                } else {
                                    appState.selectedItems = [item.id]
                                }
                            }
                        }

                        // Divider + count
                        if !appState.library.isEmpty {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 6)

                            Text("\(appState.library.count)")
                                .font(AppFont.photoCount)
                                .foregroundStyle(Color.text3)
                        }

                        // Add button
                        Button(action: openFilePicker) {
                            Circle()
                                .strokeBorder(Color.text3, style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.text3)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }
                .onChange(of: appState.selectedItems) { _, newValue in
                    if let first = newValue.first {
                        withAnimation {
                            proxy.scrollTo(first, anchor: .center)
                        }
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK {
            appState.addPhotos(from: panel.urls)
        }
    }
}
```

- [ ] **Step 3: Add filmstrip overlay to CanvasView.swift**

Replace the full file:

```swift
import SwiftUI
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ZStack {
            LivePreviewPanel()

            // Floating filmstrip at bottom
            if !appState.library.isEmpty {
                VStack {
                    Spacer()
                    FilmstripView()
                        .padding(.leading, 14)
                        .padding(.trailing, 294) // clear inspector
                        .padding(.bottom, 14)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. The filmstrip floats over the canvas. Photo selection works via filmstrip taps and Cmd+click for multi-select. The old sidebar photo list still compiles but is unreachable.

- [ ] **Step 5: Commit**

```bash
git add Sources/FramerApp/Canvas/
git commit -m "feat: add floating filmstrip photo browser"
```

---

## Task 5: CanvasView — Full Implementation

**Files:**
- Modify: `Sources/FramerApp/Canvas/CanvasView.swift` — full dark viewport
- Modify: `Sources/FramerApp/Library/PhotoThumbnailView.swift` — make AsyncThumbnail public/internal accessible

- [ ] **Step 1: Rewrite CanvasView.swift with full viewport**

Replace the full file:

```swift
import SwiftUI
import UniformTypeIdentifiers
import FramerCore

struct CanvasView: View {
    @Environment(AppState.self) var appState
    @State private var viewModel = PreviewViewModel()
    @State private var showOriginal = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Viewport
            ZStack {
                // Dark background with warm radial gradient
                Color.surface0
                RadialGradient(
                    colors: [Color.accent.opacity(0.02), .clear],
                    center: UnitPoint(x: 0.5, y: 0.4),
                    startRadius: 0,
                    endRadius: 400
                )

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.text2)
                } else if let img = showOriginal ? viewModel.originalImage : viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(32)
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.text3)
                        Text("No photo selected")
                            .font(AppFont.body(16, weight: .medium))
                            .foregroundStyle(Color.text2)
                        Text("Select a photo from the filmstrip,\nor drag images here")
                            .font(AppFont.body(13))
                            .foregroundStyle(Color.text3)
                            .multilineTextAlignment(.center)
                    }
                }

                // Error display
                if let err = viewModel.error {
                    VStack {
                        Spacer()
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(AppFont.body(11))
                            .foregroundStyle(Color.error)
                            .padding(8)
                            .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                            .padding()
                    }
                }

                // Before/After toggle — top-left
                if viewModel.previewImage != nil {
                    VStack {
                        HStack {
                            BeforeAfterToggle(showOriginal: $showOriginal)
                                .padding(.leading, 16)
                                .padding(.top, 16)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Drop target overlay
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(Color.accentDim, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Color.accentGlow, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                        .padding(12)
                }

                // Floating filmstrip
                if !appState.library.isEmpty {
                    VStack {
                        Spacer()
                        FilmstripView()
                            .padding(.leading, 14)
                            .padding(.trailing, 294)
                            .padding(.bottom, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            // EXIF bar
            if let exif = viewModel.exifData {
                ExifInfoBar(exif: exif, config: appState.currentConfig)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        Color.surface1
                            .overlay(alignment: .top) {
                                Rectangle().fill(Color.borderDefault).frame(height: 1)
                            }
                    }
            }
        }
        .onChange(of: appState.selectedItems) { _, _ in
            showOriginal = false
            updatePreview()
        }
        .onChange(of: appState.currentConfig) { _, _ in updatePreview() }
        .onChange(of: appState.selectedPhoto?.rotation) { _, _ in updatePreview() }
        .onAppear { updatePreview() }
        .onReceive(NotificationCenter.default.publisher(for: .framerOpenPhotos)) { _ in
            openFilePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerSelectAll)) { _ in
            appState.selectedItems = Set(appState.library.map(\.id))
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerDeleteSelected)) { _ in
            removeSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerRotateCW)) { _ in
            for id in appState.selectedItems { appState.rotateItem(id, clockwise: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerRotateCCW)) { _ in
            for id in appState.selectedItems { appState.rotateItem(id, clockwise: false) }
        }
    }

    private func updatePreview() {
        viewModel.updatePreview(for: appState.selectedPhoto, config: appState.currentConfig)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        appState.addPhotos(from: [url])
                    }
                }
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK {
            appState.addPhotos(from: panel.urls)
        }
    }

    private func removeSelected() {
        withAnimation {
            appState.library.removeAll { appState.selectedItems.contains($0.id) }
            appState.selectedItems.removeAll()
        }
    }
}

// MARK: - Before/After Toggle

struct BeforeAfterToggle: View {
    @Binding var showOriginal: Bool

    var body: some View {
        HStack(spacing: 0) {
            toggleButton("Before", isActive: showOriginal) {
                showOriginal = true
            }
            toggleButton("After", isActive: !showOriginal) {
                showOriginal = false
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func toggleButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.toggleLabel)
                .textCase(.uppercase)
                .foregroundStyle(isActive ? Color.text0 : Color.text3)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.white.opacity(0.1) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Restyle ExifInfoBar in LivePreviewPanel.swift**

The `ExifInfoBar` and `EXIFInspectorPopover` structs in `LivePreviewPanel.swift` are still referenced by `CanvasView`. For now, they stay in `LivePreviewPanel.swift` and compile fine. We'll move them in a later cleanup step. No changes needed here yet.

- [ ] **Step 3: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. The canvas now has a dark background with radial gradient, photo shadow, custom before/after toggle, and styled drop zone. Notification handlers moved from LibrarySidebar to CanvasView.

- [ ] **Step 4: Commit**

```bash
git add Sources/FramerApp/Canvas/CanvasView.swift
git commit -m "feat: implement dark canvas viewport with before/after toggle"
```

---

## Task 6: Extract Shared Views from LivePreviewPanel

**Files:**
- Create: `Sources/FramerApp/Canvas/ExifInfoBar.swift` — extracted from LivePreviewPanel
- Delete: `Sources/FramerApp/Editor/LivePreviewPanel.swift`
- Delete: `Sources/FramerApp/Library/LibrarySidebar.swift`

- [ ] **Step 1: Create ExifInfoBar.swift with restyled EXIF bar**

```swift
import SwiftUI
import FramerCore

struct ExifInfoBar: View {
    let exif: ExifData
    let config: ProcessingConfig
    @State private var showingInspector = false

    var captionText: String {
        guard let layers = config.layers,
              let captionLayer = layers.first(where: { if case .caption = $0 { return true }; return false }),
              case .caption(let params) = captionLayer else {
            return "(no caption)"
        }
        switch params.mode {
        case .template(let t): return exif.resolve(template: t)
        case .custom(let s): return s
        case .none: return "(no caption)"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let camera = exif.camera {
                    Text(camera)
                        .font(AppFont.body(11))
                        .foregroundStyle(Color.text2)
                }
                HStack(spacing: 4) {
                    exifChip(exif.iso.map { "ISO \($0)" })
                    exifChip(exif.aperture.map { "f/\($0)" })
                    exifChip(exif.shutterSpeed)
                    exifChip(exif.focalLength.map { "\($0)mm" })
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("CAPTION")
                    .font(AppFont.sectionHeader)
                    .tracking(1.5)
                    .foregroundStyle(Color.text3)
                Text(captionText)
                    .font(AppFont.mono(11))
                    .foregroundStyle(Color.text1)
            }

            Button(action: { showingInspector.toggle() }) {
                Circle()
                    .stroke(Color.borderDefault, lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "info")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.text2)
                    }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInspector) {
                EXIFInspectorPopover(exif: exif)
            }
        }
    }

    @ViewBuilder
    private func exifChip(_ value: String?) -> some View {
        if let v = value {
            Text(v)
                .font(AppFont.exifChip)
                .foregroundStyle(Color.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.surface3, in: Capsule())
        }
    }
}

struct EXIFInspectorPopover: View {
    let exif: ExifData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXIF DATA")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)
                .padding(.bottom, 4)
            row("Camera", exif.camera)
            row("Lens", exif.lens)
            row("ISO", exif.iso)
            row("Aperture", exif.aperture.map { "f/\($0)" })
            row("Shutter", exif.shutterSpeed)
            row("Focal Length", exif.focalLength.map { "\($0)mm" })
            if let date = exif.dateTime {
                row("Date", DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
            }
        }
        .padding(16)
        .frame(minWidth: 220)
        .background(Color.surface1)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.text2)
                .frame(width: 100, alignment: .trailing)
            Text(value ?? "--")
                .foregroundStyle(Color.text1)
        }
        .font(AppFont.body(11))
    }
}
```

- [ ] **Step 2: Delete LivePreviewPanel.swift**

```bash
git rm Sources/FramerApp/Editor/LivePreviewPanel.swift
```

- [ ] **Step 3: Delete LibrarySidebar.swift**

```bash
git rm Sources/FramerApp/Library/LibrarySidebar.swift
```

- [ ] **Step 4: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. All ExifInfoBar/EXIFInspectorPopover references now resolve to the new file. LibrarySidebar was only referenced in ContentView which no longer uses it.

- [ ] **Step 5: Commit**

```bash
git add Sources/FramerApp/Canvas/ExifInfoBar.swift
git commit -m "feat: extract and restyle ExifInfoBar, delete LivePreviewPanel and LibrarySidebar"
```

---

## Task 7: Custom Controls

**Files:**
- Create: `Sources/FramerApp/Controls/StyledSlider.swift`
- Create: `Sources/FramerApp/Controls/StyledToggle.swift`
- Create: `Sources/FramerApp/Controls/FormatPicker.swift`
- Create: `Sources/FramerApp/Controls/ColorPickerWithHex.swift`

- [ ] **Step 1: Create Controls directory**

```bash
mkdir -p Sources/FramerApp/Controls
```

- [ ] **Step 2: Create StyledSlider.swift**

```swift
import SwiftUI

struct StyledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix: String = ""
    var inputWidth: CGFloat = 55

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: snappedBinding, in: range)
                .tint(Color.accentDim)

            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .font(AppFont.numericInput)
                .foregroundStyle(Color.text1)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: inputWidth)
                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )

            if !suffix.isEmpty {
                Text(suffix)
                    .font(AppFont.mono(9))
                    .foregroundStyle(Color.text3)
                    .frame(width: 20)
            }
        }
    }

    private var snappedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = (($0 / step).rounded() * step).clamped(to: range) }
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 3: Create StyledToggle.swift**

```swift
import SwiftUI

struct StyledToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Color.accentDim : Color.surface4)
                .frame(width: 32, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Color.text0 : Color.text2)
                        .frame(width: 12, height: 12)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Create FormatPicker.swift**

```swift
import SwiftUI

struct FormatPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            pillButton("JPEG", tag: "jpeg")
            pillButton("PNG", tag: "png")
        }
        .background(Color.surface3, in: Capsule())
    }

    private func pillButton(_ label: String, tag: String) -> some View {
        Button {
            selection = tag
        } label: {
            Text(label)
                .font(AppFont.buttonText)
                .foregroundStyle(selection == tag ? Color.accent : Color.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selection == tag ? Color.accentSubtle : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 5: Extract ColorPickerWithHex.swift from SettingsPanel**

```swift
import SwiftUI
import FramerCore

struct ColorPickerWithHex: View {
    let label: String
    @Binding var selection: Color
    @State private var hexText: String = ""

    init(_ label: String, selection: Binding<Color>) {
        self.label = label
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker(label, selection: $selection)
            TextField("#HEX", text: $hexText)
                .textFieldStyle(.plain)
                .font(AppFont.hexValue)
                .foregroundStyle(Color.text1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: 80)
                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .onSubmit { applyHex() }
        }
        .onAppear { syncHexFromColor() }
        .onChange(of: selection) { _, _ in syncHexFromColor() }
    }

    private func syncHexFromColor() {
        if let hex = selection.hexString {
            hexText = hex
        }
    }

    private func applyHex() {
        let cleaned = hexText.trimmingCharacters(in: .whitespaces)
        guard let codable = try? CodableColor(hex: cleaned) else { return }
        if let nsColor = NSColor(cgColor: codable.cgColor) {
            selection = Color(nsColor: nsColor)
        }
    }
}
```

- [ ] **Step 6: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. Controls are defined but not yet wired into any views.

- [ ] **Step 7: Commit**

```bash
git add Sources/FramerApp/Controls/
git commit -m "feat: add custom styled controls (slider, toggle, format picker, color picker)"
```

---

## Task 8: InspectorView — Full Implementation

**Files:**
- Modify: `Sources/FramerApp/Inspector/InspectorView.swift` — full implementation
- Create: `Sources/FramerApp/Inspector/ExportBar.swift`

- [ ] **Step 1: Create ExportBar.swift**

```swift
import SwiftUI
import FramerCore

struct ExportBar: View {
    @Environment(AppState.self) var appState
    @AppStorage("lastExportDirectory") private var lastExportDirectory: String = ""
    @State private var showingExportSheet = false
    @State private var showingQueuePopover = false
    @State private var pendingExportItems: [PhotoItem] = []
    @State private var selectedPresetIDs: Set<UUID> = []
    @State private var includeCurrentSettings = true

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.borderDefault).frame(height: 1)
            HStack(spacing: 12) {
                // Export Selected
                Button {
                    promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Selected")
                            .font(AppFont.buttonText)
                        if !appState.selectedItems.isEmpty {
                            Text("\(appState.selectedItems.count)")
                                .font(AppFont.badgeSummary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.surface4, in: Capsule())
                        }
                    }
                    .foregroundStyle(Color.text1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.borderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.selectedItems.isEmpty)

                Spacer()

                // Queue indicator
                if !appState.exportQueue.isEmpty {
                    Button {
                        showingQueuePopover.toggle()
                    } label: {
                        queueIndicator
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingQueuePopover) {
                        ExportQueuePopover()
                    }
                }

                // Export All
                Button {
                    promptAndExport(appState.library)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.system(size: 10))
                        Text("All")
                            .font(AppFont.buttonText)
                        if !appState.library.isEmpty {
                            Text("\(appState.library.count)")
                                .font(AppFont.badgeSummary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accent.opacity(0.2), in: Capsule())
                        }
                    }
                    .foregroundStyle(Color.text0)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentDim, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.accent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.library.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surface1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportSelected)) { _ in
            promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportAll)) { _ in
            promptAndExport(appState.library)
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
    }

    @ViewBuilder
    private var queueIndicator: some View {
        let running = appState.exportQueue.filter { $0.status == .running }
        let failed = appState.exportQueue.filter { if case .failed = $0.status { return true }; return false }

        HStack(spacing: 4) {
            if let job = running.first {
                ProgressView(value: job.progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(Color.accent)
                Text("\(job.completedCount)/\(job.items.count)")
                    .font(AppFont.photoCount)
                    .foregroundStyle(Color.text2)
            } else if !failed.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.error)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.success)
            }
        }
    }

    // MARK: - Export Logic (moved from SettingsPanel)

    private func promptAndExport(_ items: [PhotoItem]) {
        guard !items.isEmpty else { return }
        if appState.presets.isEmpty {
            directExport(items)
        } else {
            pendingExportItems = items
            showingExportSheet = true
        }
    }

    private func directExport(_ items: [PhotoItem]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        if !lastExportDirectory.isEmpty, let url = URL(string: lastExportDirectory) {
            panel.directoryURL = url
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        lastExportDirectory = dir.absoluteString
        appState.exportItems(items, to: dir)
    }

    private func performExport() {
        showingExportSheet = false
        let items = pendingExportItems
        guard !items.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        if !lastExportDirectory.isEmpty, let url = URL(string: lastExportDirectory) {
            panel.directoryURL = url
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        lastExportDirectory = dir.absoluteString

        if includeCurrentSettings {
            appState.exportItems(items, to: dir)
        }

        let presetConfigs = appState.presets
            .filter { selectedPresetIDs.contains($0.id) }
            .map { (name: $0.name, config: $0.config) }

        if !presetConfigs.isEmpty {
            appState.exportItems(items, to: dir, withPresets: presetConfigs)
        }

        selectedPresetIDs.removeAll()
    }

    private var exportSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Export \(pendingExportItems.count) photo\(pendingExportItems.count == 1 ? "" : "s")")
                    .font(AppFont.body(14, weight: .semibold))
                    .foregroundStyle(Color.text0)

                Toggle(isOn: $includeCurrentSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.text2)
                        Text("Current Settings")
                            .font(AppFont.body(12))
                        if let name = appState.activePresetName {
                            Text("(\(name))")
                                .font(AppFont.body(11))
                                .foregroundStyle(Color.text2)
                        }
                    }
                }

                if !appState.presets.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Also export with presets:")
                            .font(AppFont.body(11))
                            .foregroundStyle(Color.text2)

                        ForEach(appState.presets) { preset in
                            Toggle(isOn: presetToggleBinding(preset.id)) {
                                Text(preset.name)
                                    .font(AppFont.body(12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("Cancel") {
                    showingExportSheet = false
                    selectedPresetIDs.removeAll()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                let totalExports = (includeCurrentSettings ? 1 : 0) + selectedPresetIDs.count
                Button("Export\(totalExports > 1 ? " (\(totalExports) presets)" : "")") {
                    performExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(totalExports == 0)
            }
            .padding(20)
        }
        .frame(width: 340)
    }

    private func presetToggleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedPresetIDs.contains(id) },
            set: { enabled in
                if enabled { selectedPresetIDs.insert(id) }
                else { selectedPresetIDs.remove(id) }
            }
        )
    }
}

// MARK: - Export Queue Popover

struct ExportQueuePopover: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EXPORT QUEUE")
                    .font(AppFont.sectionHeader)
                    .tracking(1.5)
                    .foregroundStyle(Color.text3)
                Spacer()
                if appState.exportQueue.contains(where: { $0.status == .done }) {
                    Button("Clear") {
                        appState.exportQueue.removeAll { $0.status == .done }
                    }
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text2)
                    .buttonStyle(.plain)
                }
            }

            ForEach(appState.exportQueue) { job in
                jobRow(job)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(Color.surface1)
    }

    private func jobRow(_ job: ExportJob) -> some View {
        HStack(spacing: 6) {
            statusIcon(job.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(job.items.count) photo\(job.items.count == 1 ? "" : "s")")
                        .font(AppFont.body(11))
                        .foregroundStyle(Color.text1)
                    if let label = job.label {
                        Text(label)
                            .font(AppFont.mono(9))
                            .foregroundStyle(Color.text3)
                    }
                }
                .lineLimit(1)
                if job.status == .running {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accent)
                        .frame(height: 3)
                }
            }
            Spacer()
            if job.status == .done {
                Button {
                    NSWorkspace.shared.open(job.outputDirectory)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
            }
            if case .failed = job.status {
                Button {
                    appState.retryJob(job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIcon(_ status: ExportJob.JobStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(Color.text3)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(Color.accent)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.error)
        }
    }
}
```

- [ ] **Step 2: Rewrite InspectorView.swift**

```swift
import SwiftUI
import FramerCore

struct InspectorView: View {
    @Environment(AppState.self) var appState
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""
    @State private var presetToDelete: Preset?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Active preset banner
                    if let presetName = appState.activePresetName {
                        activePresetBanner(presetName)
                    }

                    // Presets section
                    presetsSection

                    // Layers section
                    layersSection

                    // Output section
                    outputSection
                }
                .padding(12)
            }

            ExportBar()
        }
        .frame(width: 280)
        .background(Color.surface1)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.borderDefault).frame(width: 1)
        }
        .onAppear { ensureLayersInitialized() }
        .onChange(of: appState.currentConfig.layers == nil) { _, layersAreNil in
            if layersAreNil { ensureLayersInitialized() }
        }
        .sheet(isPresented: $showingSaveSheet) { savePresetSheet }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "Unknown error")
        }
        .alert("Delete Preset?", isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { presetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    try? appState.presetStore.delete(id: preset.id)
                    appState.loadPresets()
                    presetToDelete = nil
                }
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete \"\(preset.name)\"?")
            }
        }
    }

    // MARK: - Active Preset Banner

    private func activePresetBanner(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(Color.accent)
            Text(name)
                .font(AppFont.body(11, weight: .semibold))
                .foregroundStyle(Color.accent)
            Spacer()
            Button {
                appState.activePresetName = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.accentGlow, in: RoundedRectangle(cornerRadius: CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.accent.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)

            if appState.presets.isEmpty {
                Text("No presets yet")
                    .font(AppFont.body(11))
                    .foregroundStyle(Color.text3)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.presets) { preset in
                    presetRow(preset)
                }
            }

            Button(action: { showingSaveSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                    Text("Save Current Settings")
                        .font(AppFont.body(11))
                }
                .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        Button {
            appState.currentConfig = preset.config
            appState.activePresetName = preset.name
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.text3)
                    .frame(width: 14)
                Text(preset.name)
                    .font(AppFont.layerName)
                    .foregroundStyle(Color.text0)
                    .lineLimit(1)
                Spacer()
                if appState.activePresetName == preset.name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                appState.activePresetName == preset.name
                    ? Color.accentGlow
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: CornerRadius.sm)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                appState.currentConfig = preset.config
                appState.activePresetName = preset.name
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
            }
            Button {
                let updated = Preset(id: preset.id, name: preset.name, config: appState.currentConfig)
                do {
                    try appState.presetStore.save(updated)
                    appState.loadPresets()
                    appState.activePresetName = preset.name
                } catch {
                    saveError = error.localizedDescription
                }
            } label: {
                Label("Update with Current Settings", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive) {
                presetToDelete = preset
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Layers Section

    private var layersSection: some View {
        LayerListSection(layers: layersBinding)
    }

    private var layersBinding: Binding<[CompositionLayer]> {
        Binding(
            get: { appState.currentConfig.layers ?? CompositionLayer.defaultLayers() },
            set: { appState.currentConfig.layers = $0 }
        )
    }

    private func ensureLayersInitialized() {
        if appState.currentConfig.layers == nil {
            appState.currentConfig.layers = CompositionLayer.defaultLayers()
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUT")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)

            // Format picker
            HStack {
                Text("Format")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                FormatPicker(selection: outputFormatBinding)
            }

            // Quality slider (JPEG only)
            if case .jpeg(let q) = appState.currentConfig.outputFormat {
                HStack {
                    Text("Quality")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text2)
                    Spacer()
                    StyledSlider(
                        value: Binding(
                            get: { Double(q) },
                            set: { appState.currentConfig.outputFormat = .jpeg(quality: Int($0)) }
                        ),
                        range: 60...100,
                        step: 5,
                        suffix: "%"
                    )
                    .frame(maxWidth: 180)
                }
            }

            // Strip EXIF toggle
            HStack {
                Text("Strip EXIF metadata")
                    .font(AppFont.controlLabel)
                    .foregroundStyle(Color.text2)
                Spacer()
                StyledToggle(isOn: Binding(
                    get: { appState.currentConfig.noMetadata },
                    set: { appState.currentConfig.noMetadata = $0 }
                ))
            }
        }
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { appState.currentConfig.outputFormat == .png ? "png" : "jpeg" },
            set: { appState.currentConfig.outputFormat = $0 == "png" ? .png : .jpeg(quality: 100) }
        )
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(AppFont.body(14, weight: .semibold))
                .foregroundStyle(Color.text0)

            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack {
                Button("Cancel") {
                    newPresetName = ""
                    showingSaveSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let name = newPresetName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let preset = Preset(name: name, config: appState.currentConfig)
                    do {
                        try appState.presetStore.save(preset)
                        appState.loadPresets()
                        appState.activePresetName = preset.name
                        newPresetName = ""
                        showingSaveSheet = false
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }
}
```

- [ ] **Step 3: Delete SettingsPanel's ColorPickerWithHex and clamped extension**

Remove the `ColorPickerWithHex` struct and `Double.clamped` extension from `SettingsPanel.swift` since they now live in `Controls/`. Then delete `SettingsPanel.swift` entirely since `InspectorView` replaces it:

```bash
git rm Sources/FramerApp/Editor/SettingsPanel.swift
```

- [ ] **Step 4: Delete unused preset and queue views**

```bash
git rm Sources/FramerApp/Presets/PresetManagerView.swift
git rm Sources/FramerApp/Queue/ExportQueueView.swift
```

- [ ] **Step 5: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. The inspector shows preset list, layer section, output controls, and pinned export bar. Export queue appears as popover.

- [ ] **Step 6: Commit**

```bash
git add Sources/FramerApp/Inspector/ Sources/FramerApp/Controls/
git commit -m "feat: implement InspectorView with ExportBar and queue popover"
```

---

## Task 9: PresetPreviewGrid (Visual Preset Thumbnails)

**Files:**
- Create: `Sources/FramerApp/Presets/PresetPreviewGrid.swift`
- Create: `Sources/FramerApp/Presets/PresetPreviewCard.swift`
- Modify: `Sources/FramerApp/Inspector/InspectorView.swift` — replace preset list with grid

- [ ] **Step 1: Create PresetPreviewCard.swift**

```swift
import SwiftUI
import FramerCore

struct PresetPreviewCard: View {
    let preset: Preset
    let isActive: Bool
    let thumbnail: NSImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Thumbnail area — 4:3 aspect ratio
                ZStack {
                    Color.surface3

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.text3)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)
                .clipped()

                // Label strip
                Text(preset.name)
                    .font(AppFont.templateToken)
                    .foregroundStyle(isActive ? Color.accent : Color.text2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isActive ? Color.accentGlow : Color.surface2)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isActive ? Color.accent : .clear, lineWidth: 2)
            )
            .shadow(color: isActive ? Color.accent.opacity(0.15) : .clear, radius: 6)
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.surface0)
                        }
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Create PresetPreviewGrid.swift**

```swift
import SwiftUI
import FramerCore

struct PresetPreviewGrid: View {
    @Environment(AppState.self) var appState
    @State private var presetPreviews: [UUID: NSImage] = [:]
    @State private var renderTasks: [UUID: Task<Void, Never>] = [:]
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""
    @State private var saveError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(appState.presets) { preset in
                PresetPreviewCard(
                    preset: preset,
                    isActive: appState.activePresetName == preset.name,
                    thumbnail: presetPreviews[preset.id],
                    onTap: {
                        appState.currentConfig = preset.config
                        appState.activePresetName = preset.name
                    }
                )
            }

            // Save card
            Button(action: { showingSaveSheet = true }) {
                VStack(spacing: 0) {
                    ZStack {
                        Color.clear
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.text3)
                            Text("Save")
                                .font(AppFont.templateToken)
                                .foregroundStyle(Color.text3)
                        }
                    }
                    .aspectRatio(4/3, contentMode: .fit)

                    Color.clear.frame(height: 22) // match label strip height
                }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(Color.text3, style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
            }
            .buttonStyle(.plain)
        }
        .onChange(of: appState.selectedPhoto?.id) { _, _ in
            schedulePreviewRenders()
        }
        .onAppear {
            schedulePreviewRenders()
        }
        .sheet(isPresented: $showingSaveSheet) {
            savePresetSheet
        }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    // MARK: - Preview Rendering

    private func schedulePreviewRenders() {
        // Cancel all in-flight renders
        for (_, task) in renderTasks { task.cancel() }
        renderTasks.removeAll()
        presetPreviews.removeAll()

        guard let photo = appState.selectedPhoto else { return }

        // Debounce 200ms, then render each preset
        let presets = appState.presets
        let url = photo.url
        let rotation = photo.rotation

        for preset in presets {
            let presetID = preset.id
            let config = preset.config

            let task = Task {
                // Debounce
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }

                let processor = FrameProcessor()
                do {
                    // Render at reduced resolution by using a downscaled source
                    let preview = try await Task.detached {
                        try processor.previewImage(for: url, config: config, rotation: rotation)
                    }.value
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        presetPreviews[presetID] = preview
                    }
                } catch {
                    // Silently fail — card shows placeholder
                }
            }
            renderTasks[presetID] = task
        }
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(AppFont.body(14, weight: .semibold))
                .foregroundStyle(Color.text0)

            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack {
                Button("Cancel") {
                    newPresetName = ""
                    showingSaveSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let name = newPresetName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let preset = Preset(name: name, config: appState.currentConfig)
                    do {
                        try appState.presetStore.save(preset)
                        appState.loadPresets()
                        appState.activePresetName = preset.name
                        newPresetName = ""
                        showingSaveSheet = false
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }
}
```

- [ ] **Step 3: Update InspectorView to use PresetPreviewGrid**

In `Sources/FramerApp/Inspector/InspectorView.swift`, replace the `presetsSection` computed property:

```swift
    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(AppFont.sectionHeader)
                .tracking(1.5)
                .foregroundStyle(Color.text3)

            PresetPreviewGrid()
        }
    }
```

And remove the `presetRow`, `showingSaveSheet`, `newPresetName`, `presetToDelete`, `saveError` state properties and the save/delete alerts from InspectorView since PresetPreviewGrid now owns preset save. Keep the delete alert only if context menus on preset cards need it — otherwise PresetPreviewGrid handles it internally.

Simplified InspectorView state becomes:

```swift
struct InspectorView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let presetName = appState.activePresetName {
                        activePresetBanner(presetName)
                    }
                    presetsSection
                    layersSection
                    outputSection
                }
                .padding(12)
            }

            ExportBar()
        }
        .frame(width: 280)
        .background(Color.surface1)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.borderDefault).frame(width: 1)
        }
        .onAppear { ensureLayersInitialized() }
        .onChange(of: appState.currentConfig.layers == nil) { _, layersAreNil in
            if layersAreNil { ensureLayersInitialized() }
        }
    }

    // ... activePresetBanner, presetsSection, layersSection, outputSection as before
    // but presetsSection now uses PresetPreviewGrid
}
```

- [ ] **Step 4: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. Preset grid shows 3-column layout with rendered thumbnails when a photo is selected.

- [ ] **Step 5: Commit**

```bash
git add Sources/FramerApp/Presets/ Sources/FramerApp/Inspector/InspectorView.swift
git commit -m "feat: add visual preset preview grid with live thumbnail rendering"
```

---

## Task 10: LayerListSection Restyle

**Files:**
- Modify: `Sources/FramerApp/Editor/LayerListSection.swift` — apply dark theme tokens

- [ ] **Step 1: Update section header styling**

In `LayerListSection.swift`, update the `Section` header at line 47-49:

Change:
```swift
} header: {
    Text("Layers (\(layers.count))")
}
```

To:
```swift
} header: {
    Text("LAYERS (\(layers.count))")
        .font(AppFont.sectionHeader)
        .tracking(1.5)
        .foregroundStyle(Color.text3)
}
```

- [ ] **Step 2: Update LayerRow styling**

In the `LayerRow` struct, update text styling to use design tokens. Key changes:
- Layer name: use `AppFont.layerName` and `Color.text0`
- Badge/summary text: use `AppFont.badgeSummary` and `Color.text2` in `surface-4` pill
- Delete button: use `Color.error` on hover
- DisclosureGroup background: transparent default, `Color.surface2` when expanded, `Color.borderDefault` hover border

These are incremental find-and-replace changes throughout the file. The logic (undo, drag, bindings) stays identical — only `.font()`, `.foregroundStyle()`, and `.background()` modifiers change.

- [ ] **Step 3: Update layer control views**

For each control view (`BorderLayerControls`, `PaddingLayerControls`, `CanvasLayerControls`, etc.):
- Replace `sliderWithInput()` calls with `StyledSlider()`
- Replace native `Toggle` with `StyledToggle`
- Replace `ColorPickerWithHex` references to use the one from `Controls/`
- Update label fonts to `AppFont.controlLabel` with `Color.text2`

- [ ] **Step 4: Build and verify**

```bash
swift build 2>&1 | head -20
```

Expected: Build succeeds. Layer list renders with dark theme styling.

- [ ] **Step 5: Commit**

```bash
git add Sources/FramerApp/Editor/LayerListSection.swift
git commit -m "feat: restyle LayerListSection with Darkroom Editorial tokens"
```

---

## Task 11: Polish and Cleanup

**Files:**
- Delete: `Sources/FramerApp/Library/PhotoThumbnailView.swift` — move `AsyncThumbnail` into its own file
- Create: `Sources/FramerApp/Canvas/AsyncThumbnail.swift`
- Cleanup unused imports and files

- [ ] **Step 1: Extract AsyncThumbnail to its own file**

Create `Sources/FramerApp/Canvas/AsyncThumbnail.swift` containing the `AsyncThumbnail` struct from `PhotoThumbnailView.swift` (lines 40-99). Keep it unchanged.

```swift
import SwiftUI
import CoreGraphics
import ImageIO

struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Color.text3)
            }
        }
        .task {
            if let cgImage = await Self.loadCGThumbnail(from: url) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
    }

    private static func loadCGThumbnail(from url: URL) async -> CGImage? {
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            return cached.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        return await Task.detached { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            let nsImage = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            thumbnailCache.setObject(nsImage, forKey: url as NSURL)
            return thumbnail
        }.value
    }

    private nonisolated(unsafe) static let thumbnailCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 500
        return cache
    }()
}
```

- [ ] **Step 2: Delete PhotoThumbnailView.swift**

```bash
git rm Sources/FramerApp/Library/PhotoThumbnailView.swift
```

- [ ] **Step 3: Remove the Library directory if empty**

```bash
rmdir Sources/FramerApp/Library 2>/dev/null || true
```

- [ ] **Step 4: Build and verify the complete app**

```bash
swift build 2>&1 | head -30
```

Expected: Clean build with no warnings related to the redesign. All features work: photo import, filmstrip selection, preview rendering, layer editing, preset management, export.

- [ ] **Step 5: Run tests**

```bash
swift test 2>&1 | tail -20
```

Expected: All FramerCore tests pass. No UI tests exist to break.

- [ ] **Step 6: Commit**

```bash
git add Sources/FramerApp/Canvas/AsyncThumbnail.swift
git commit -m "refactor: extract AsyncThumbnail, remove obsolete Library views"
```

---

## Task 12: Final Verification

- [ ] **Step 1: Verify all old files are removed**

```bash
# These should all be gone
ls Sources/FramerApp/Editor/LivePreviewPanel.swift 2>&1
ls Sources/FramerApp/Editor/SettingsPanel.swift 2>&1
ls Sources/FramerApp/Library/LibrarySidebar.swift 2>&1
ls Sources/FramerApp/Library/PhotoThumbnailView.swift 2>&1
ls Sources/FramerApp/Presets/PresetManagerView.swift 2>&1
ls Sources/FramerApp/Queue/ExportQueueView.swift 2>&1
```

Expected: All return "No such file or directory"

- [ ] **Step 2: Verify new file structure**

```bash
find Sources/FramerApp -name "*.swift" | sort
```

Expected file tree:
```
Sources/FramerApp/App/AppState.swift
Sources/FramerApp/App/FramerApp.swift
Sources/FramerApp/App/FramerCommands.swift
Sources/FramerApp/App/PreferencesView.swift
Sources/FramerApp/Canvas/AsyncThumbnail.swift
Sources/FramerApp/Canvas/CanvasView.swift
Sources/FramerApp/Canvas/ExifInfoBar.swift
Sources/FramerApp/Canvas/FilmstripThumbnail.swift
Sources/FramerApp/Canvas/FilmstripView.swift
Sources/FramerApp/Controls/ColorPickerWithHex.swift
Sources/FramerApp/Controls/FormatPicker.swift
Sources/FramerApp/Controls/StyledSlider.swift
Sources/FramerApp/Controls/StyledToggle.swift
Sources/FramerApp/ContentView.swift
Sources/FramerApp/Editor/LayerListSection.swift
Sources/FramerApp/Editor/PreviewViewModel.swift
Sources/FramerApp/Inspector/ExportBar.swift
Sources/FramerApp/Inspector/InspectorView.swift
Sources/FramerApp/Presets/PresetPreviewCard.swift
Sources/FramerApp/Presets/PresetPreviewGrid.swift
Sources/FramerApp/Theme/DesignTokens.swift
```

- [ ] **Step 3: Full build + test**

```bash
swift build && swift test
```

Expected: Build succeeds, all tests pass.

- [ ] **Step 4: Regenerate Xcode project**

```bash
xcodegen generate
```

Expected: Project generated successfully with all new files included.
