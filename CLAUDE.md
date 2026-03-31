# AI Assistant Instructions

**Read and follow:** [.ai-assistant/.instructions.md](.ai-assistant/.instructions.md)

This file is an entry point for AI coding assistants. All guidelines, workflows, and domain-specific instructions are centralized in the `.ai-assistant/` directory.

## Quick Start

1. Read [.ai-assistant/.instructions.md](.ai-assistant/.instructions.md) for global execution protocol
2. Check [.ai-assistant/INDEX.md](.ai-assistant/INDEX.md) for topic navigation
3. Project-specific configuration is in [.ai-project/](.ai-project/)

## Project Overview

**framer** - Swift macOS/iOS app and CLI for adding frames, borders, captions, and texture overlays to photos

| Aspect | Value |
|--------|-------|
| Language | Swift 5.10 |
| Platforms | macOS 14+, iOS 17+ |
| Package Manager | Swift Package Manager |
| Xcode Project | XcodeGen (`project.yml`) |
| Targets | FramerCore (library), FramerCLI (executable), FramerApp (macOS SwiftUI), FramerMobile (iOS SwiftUI) |
| Test Framework | XCTest |
| Git LFS | Texture overlays in `assets/textures/` are stored with Git LFS |

## Quick Commands

| Task | Command |
|------|---------|
| Build (macOS) | `swift build` |
| Build (iOS) | `xcodebuild build -scheme FramerMobile -destination 'generic/platform=iOS Simulator'` |
| Test | `swift test` |
| Xcode Project | `xcodegen generate` |
| Validate | `swift build && swift test` |

## Setup

After cloning, fetch Git LFS files (texture overlays are ~150 files stored via LFS):
```
git lfs install
git lfs pull
```
Without this, overlay textures will be 132-byte pointer files and overlays won't render.

## Commit Style

Use conventional commits:
```
feat: add new feature
fix: resolve bug
refactor: restructure code
test: add/update tests
docs: documentation changes
chore: maintenance tasks
```

## Project Context

- [assets/design/DESIGN_BRIEFING.md](assets/design/DESIGN_BRIEFING.md) - macOS UI design spec ("Darkroom Editorial")
- [assets/design/ios/IOS_DESIGN_BRIEFING.md](assets/design/ios/IOS_DESIGN_BRIEFING.md) - iOS UI design spec

## Available Commands

| Command | Purpose |
|---------|---------|
| `/implement` | Full workflow: explore, plan, code, commit |
| `/debug` | Find and fix bugs |
| `/refactor` | Multi-file changes with tracking |
| `/validate` | Run type check, lint, tests |
| `/commit` | Review and commit changes |
| `/pr` | Create pull request |
