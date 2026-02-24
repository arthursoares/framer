# AI Assistant Instructions

**Read and follow:** [.ai-assistant/.instructions.md](.ai-assistant/.instructions.md)

This file is an entry point for AI coding assistants. All guidelines, workflows, and domain-specific instructions are centralized in the `.ai-assistant/` directory.

## Quick Start

1. Read [.ai-assistant/.instructions.md](.ai-assistant/.instructions.md) for global execution protocol
2. Check [.ai-assistant/INDEX.md](.ai-assistant/INDEX.md) for topic navigation
3. Project-specific configuration is in [.ai-project/](.ai-project/)

## Project Overview

**framer** - Swift macOS app and CLI for adding frames, borders, captions, and texture overlays to photos

| Aspect | Value |
|--------|-------|
| Language | Swift 5.10 |
| Platforms | macOS 14+ |
| Package Manager | Swift Package Manager |
| Xcode Project | XcodeGen (`project.yml`) |
| Targets | FramerCore (library), FramerCLI (executable), FramerApp (SwiftUI) |
| Test Framework | XCTest |

## Quick Commands

| Task | Command |
|------|---------|
| Build | `swift build` |
| Test | `swift test` |
| Xcode Project | `xcodegen generate` |
| Validate | `swift build && swift test` |

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

- [.ai-project/.memory.md](.ai-project/.memory.md) - Project architecture & stack
- [.ai-project/.context.md](.ai-project/.context.md) - Patterns & quick reference
- [.ai-project/project/commands.md](.ai-project/project/commands.md) - All commands

## Available Commands

| Command | Purpose |
|---------|---------|
| `/implement` | Full workflow: explore, plan, code, commit |
| `/debug` | Find and fix bugs |
| `/refactor` | Multi-file changes with tracking |
| `/validate` | Run type check, lint, tests |
| `/commit` | Review and commit changes |
| `/pr` | Create pull request |
