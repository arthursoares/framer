# framer

Swift macOS app and CLI for adding frames, borders, captions, and texture overlays to photos.

## Stack

| Aspect | Value |
|--------|-------|
| Language | Swift 5.10 |
| Platforms | macOS 14+ |
| Package Manager | Swift Package Manager |
| Xcode Project | XcodeGen (`project.yml`) |
| Targets | FramerCore (library), FramerCLI (executable), FramerApp (SwiftUI) |
| Test Framework | XCTest (102 tests) |
| Dependencies | swift-argument-parser 1.3+, Yams 5.1+ |

## Commands

| Task | Command |
|------|---------|
| Build | `swift build` |
| Test | `swift test` |
| Run CLI | `swift run framer` |
| Regen Xcode project | `xcodegen generate` |
| Validate | `swift build && swift test` |
| Filter tests | `swift test --filter ClassName` |

## Architecture

Three-target Swift Package:
- **FramerCore** — Pure processing library (models, rendering, presets). No UI imports.
- **FramerCLI** — Thin CLI wrapper via ArgumentParser. Translates flags → ProcessingConfig → FrameProcessor.
- **FramerApp** — SwiftUI macOS app (defined in `project.yml`, not Package.swift).

Layer-based composition pipeline: canvas → border → orientation → caption → overlay.

### Key Files

| File | Purpose |
|------|---------|
| `Sources/FramerCore/Processing/FrameProcessor.swift` | Main processing pipeline |
| `Sources/FramerCore/Models/CompositionLayer.swift` | Layer composition system |
| `Sources/FramerCore/Models/ProcessingConfig.swift` | All config types |
| `Package.swift` | SPM targets and dependencies |
| `project.yml` | XcodeGen config (FramerApp target) |

## Code Style

- **Naming:** PascalCase types, camelCase properties/methods, `test_unit_behavior` for tests
- **Concurrency:** `@MainActor` for UI state, `Sendable` structs, `nonisolated` + `sending` for background work
- **Imports:** Apple frameworks first, then third-party, then local modules
- **Avoid:** Force unwraps, mutable globals, UI imports in FramerCore, hardcoded paths

## Commit Style

Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`

## Gotchas

- **Tests require Xcode** — `swift test` fails if active developer tools are CLI-only. Fix: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- **Git LFS required** — Texture assets (338MB) are tracked via LFS. Run `git lfs install && git lfs pull` after cloning.
- **XcodeGen is optional** — Only needed to regenerate `Framer.xcodeproj`. Install: `brew install xcodegen`
- **FramerApp not in Package.swift** — It's defined only in `project.yml` for XcodeGen.
