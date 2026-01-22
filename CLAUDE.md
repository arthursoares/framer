# AI Assistant Instructions

**Read and follow:** [.ai-assistant/.instructions.md](.ai-assistant/.instructions.md)

This file is an entry point for AI coding assistants. All guidelines, workflows, and domain-specific instructions are centralized in the `.ai-assistant/` directory.

## Quick Start

1. Read [.ai-assistant/.instructions.md](.ai-assistant/.instructions.md) for global execution protocol
2. Check [.ai-assistant/INDEX.md](.ai-assistant/INDEX.md) for topic navigation
3. Project-specific configuration is in [.ai-project/](.ai-project/)

## Project Overview

**framer** - CLI tool for adding frames, borders, and EXIF-based captions to photos

| Aspect | Value |
|--------|-------|
| Language | Go 1.22 |
| Module | `github.com/arthursoares/framer` |
| Test Framework | Go testing (built-in) |
| CI/CD | GitHub Actions |

## Quick Commands

| Task | Command |
|------|---------|
| Build | `go build` |
| Test | `go test -v ./...` |
| Lint | `go vet ./...` |
| Format | `gofmt -s -w .` |
| Validate | `go vet ./... && go test -v -race ./...` |

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
