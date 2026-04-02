# Acerola Shader Layer Handoff

Date: 2026-04-02
Branch: `feat/acerola-shader-layer`
Worktree: `/Users/arthur.soares/Github/framer-acerola-shader`

## Current Status

The shader-layer feature is broadly implemented and working:

- `Shader` layer model exists and round-trips through JSON and YAML
- six styles are implemented:
  - `ASCII`
  - `Crimewave`
  - `Narc`
  - `Shiba`
  - `Pixel Sort`
  - `Distant Past`
- built-in shader presets exist
- shader controls are wired in macOS and iOS editors
- preview/export parity tests are in place

The latest uncommitted slice adds extracted-color support to `ASCII` and aligns extracted-color UI wording with the rest of the app.

## Latest Uncommitted Work

### ASCII color mode

`ASCII` no longer only supports explicit foreground/background colors.

New model:

- `ASCIIColorMode.manual(foreground:background:)`
- `ASCIIColorMode.dominantTwoTone(flipped:saturationShift:lightnessShift:)`

This is implemented in:

- [CompositionLayer.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerCore/Models/CompositionLayer.swift)
- [ShaderASCIIRenderer.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerCore/Processing/ShaderASCIIRenderer.swift)
- [ShaderRenderer.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerCore/Processing/ShaderRenderer.swift)
- [BorderRenderer.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerCore/Processing/BorderRenderer.swift)

Behavior:

- `manual` uses stored foreground/background colors
- `dominantTwoTone` reuses the same dominant two-color extraction approach used by other stylized paths
- `dominantTwoTone` supports:
  - palette flip
  - saturation adjustment
  - brightness adjustment

### Preset and config support

The new `ASCII` color mode is persisted in both JSON and YAML.

Updated files:

- [YAMLConfig.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerCore/Presets/YAMLConfig.swift)
- [PresetStore.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerCore/Presets/PresetStore.swift)

Notes:

- YAML supports legacy manual foreground/background decoding
- the built-in `Shader ASCII` preset now defaults to extracted colors rather than hardcoded white-on-black

### UI/editor changes

Both app targets now expose `ASCII` color mode as:

- `Manual`
- `Dominant`

When `Dominant` is selected, the editor shows:

- `Flip Palette`
- `Saturation`
- `Brightness`

Updated files:

- [LayerListSection.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerApp/Editor/LayerListSection.swift)
- [LayerDetailView.swift](/Users/arthur.soares/Github/framer-acerola-shader/Sources/FramerMobile/Layers/LayerDetailView.swift)

Additionally, other extracted-color UI labels in these editors were renamed from `Lightness` to `Brightness` for consistency.

## Tests and Verification

Latest verification on the current working tree:

- `swift test`
  - passed
  - `222` tests, `0` failures
- `xcodebuild -project Framer.xcodeproj -scheme Framer -destination 'platform=macOS' build`
  - succeeded
- `xcodebuild -project Framer.xcodeproj -scheme FramerMobile -destination 'generic/platform=iOS Simulator' build`
  - succeeded

Focused coverage added or updated:

- [CompositionLayerTests.swift](/Users/arthur.soares/Github/framer-acerola-shader/Tests/FramerCoreTests/CompositionLayerTests.swift)
  - legacy ASCII foreground/background decode compatibility
- [PresetStoreTests.swift](/Users/arthur.soares/Github/framer-acerola-shader/Tests/FramerCoreTests/PresetStoreTests.swift)
  - YAML round-trip for dominant two-tone ASCII color shifts
  - built-in shader preset expectations updated
- [ShaderRendererTests.swift](/Users/arthur.soares/Github/framer-acerola-shader/Tests/FramerCoreTests/ShaderRendererTests.swift)
  - extracted dominant two-tone palette is used by ASCII
- [FrameProcessorTests.swift](/Users/arthur.soares/Github/framer-acerola-shader/Tests/FramerCoreTests/FrameProcessorTests.swift)
  - existing preview/export parity coverage remains green

## Known Rough Edges

- The builds still emit strict-concurrency warnings around some shader-editor closures. They are warning-only and not blocking.
- The visual match to the AcerolaFX references is still approximate for several styles.
- `ASCII` is much better after glyph rendering and extracted colors, but likely still needs tuning of:
  - glyph ramp selection
  - luminance mapping
  - default extracted palette shifts

## Recommended Next Steps

If resuming later, the next highest-value work is visual tuning rather than more system work.

Recommended order:

1. Tune `ASCII` against concrete reference frames.
2. Revisit `Pixel Sort` behavior against reference look expectations.
3. Recalibrate composite looks (`Crimewave`, `Narc`, `Shiba`) with side-by-side visual checks.
4. Clean up strict-concurrency warnings in shader editor closures once the behavior is stable.

## Current Modified Files

At the time of writing, the branch has these uncommitted changes:

- `Sources/FramerApp/Editor/LayerListSection.swift`
- `Sources/FramerCore/Models/CompositionLayer.swift`
- `Sources/FramerCore/Presets/PresetStore.swift`
- `Sources/FramerCore/Presets/YAMLConfig.swift`
- `Sources/FramerCore/Processing/BorderRenderer.swift`
- `Sources/FramerCore/Processing/ShaderASCIIRenderer.swift`
- `Sources/FramerCore/Processing/ShaderPrimitives.swift`
- `Sources/FramerCore/Processing/ShaderRenderer.swift`
- `Sources/FramerMobile/Layers/LayerDetailView.swift`
- `Tests/FramerCoreTests/CompositionLayerTests.swift`
- `Tests/FramerCoreTests/FrameProcessorTests.swift`
- `Tests/FramerCoreTests/PresetStoreTests.swift`
- `Tests/FramerCoreTests/ShaderRendererTests.swift`

## Useful Recent Commits

- `820ef49` `test: cover shader editor invariants`
- `6cf623d` `test: keep shader layers in preset previews`
- `4895ac5` `feat: add shader editor controls`
- `a191f91` `test: verify built-in shader preset configs`
- `d3b5345` `feat: add built-in shader presets`
- `3430e3c` `test: exercise shader parity through frame processor`
- `edeede6` `test: add shader preview parity coverage`
- `2bc1eae` `fix: harden composite shader rendering`
- `9efe437` `feat: add composite shader styles`
- `1cf76c7` `fix: harden pixel sort shader renderer`
- `9e87fdc` `feat: add pixel sort shader style`
- `37191f9` `fix: align ascii shader preview parity`

