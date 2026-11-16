# Contributing to Strata

Thanks for helping. Strata is a small macOS tool that's read-only by default, and the bar for changes is that they keep it accurate, fast and safe.

## Ground rules

- **Read-only by default.** Only `ConfigWriter` writes Claude Code configuration, behind the off-by-default fixes setting and an approval for every write. Anything new that writes goes through it, with its checks, backups and undo.
- **Cite the docs.** Every rule about how Claude Code loads or overrides config must match [docs/configuration-resolution.md](docs/configuration-resolution.md), which links each rule to the official documentation. If the docs don't say, Strata shows "unknown" rather than guessing.
- **No secrets anywhere.** Not in code, fixtures, logs, screenshots or test output. Fixtures use obviously fake values.
- **No new dependencies** without an issue explaining why Foundation, SwiftUI or AppKit can't do the job.

## Workflow

1. Open (or pick) an issue. Titles start with `[Feature]`, `[Bug]` or `[Chore]`.
2. Branch from the latest `main`: `feature/issue-12-short-slug`, `fix/issue-21-short-slug` or `chore/issue-5-short-slug`.
3. Make the change with tests. Bug fixes include a regression test where practical.
4. Open a PR using the template, with `Closes #<issue>`.
5. Wait for CI to pass. Fix the root cause of failures rather than retrying.
6. Squash merge. The issue closes when the PR merges.

## Local setup

See [docs/development.md](docs/development.md). In short:

```bash
swift test --package-path Packages/StrataCore   # rules engine, works on macOS and Linux
brew install xcodegen
cd App && xcodegen generate     # creates Strata.xcodeproj
open Strata.xcodeproj
```

## Style

- Swift API Design Guidelines; SwiftLint runs in CI with the committed `.swiftlint.yml`.
- Keep comments for the *why*, not the *what*.
- Views stay thin: logic lives in StrataCore or in view models with unit tests.
