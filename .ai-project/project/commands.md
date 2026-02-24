# Project Commands

> **Updated:** 2026-02-24

## Development

| Task | Command |
|------|---------|
| Build all targets | `swift build` |
| Run CLI | `swift run framer` |
| Regenerate Xcode project | `xcodegen generate` |
| Open in Xcode | `open Framer.xcodeproj` |

## Testing

| Task | Command |
|------|---------|
| Run all tests | `swift test` |
| Run specific test class | `swift test --filter ClassName` |
| Run specific test | `swift test --filter test_methodName` |
| Verbose output | `swift test 2>&1 \| grep -E "(Test Case\|passed\|failed)"` |

## Quality Checks

| Task | Command |
|------|---------|
| Build check (type safety) | `swift build` |
| Full validation | `swift build && swift test` |

## Git LFS

| Task | Command |
|------|---------|
| Install LFS | `git lfs install` |
| Pull LFS files | `git lfs pull` |
| List tracked files | `git lfs ls-files` |

## Git Workflow

| Task | Command |
|------|---------|
| Status | `git status` |
| Diff | `git diff` |
| Branch | `git checkout -b feat/name` |
| Commit | `git commit -m "type: message"` |

## Quick Reference

```bash
# Full validation before commit
swift build && swift test

# Quick check during development
swift build
```
