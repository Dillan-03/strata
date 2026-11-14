# Development

## Requirements

- macOS 14 or later with Xcode 16, for the app
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or later (`brew install xcodegen`)
- [SwiftLint](https://github.com/realm/SwiftLint) 0.65 (`brew install swiftlint`), optional locally because CI runs it

The rules engine also builds on Linux with Swift 6.0 or later. No Xcode is needed there.

## First build

```bash
git clone https://github.com/Dillan-03/verbose-octo-carnival.git strata
cd strata
swift test --package-path Packages/StrataCore
cd App && xcodegen generate && open Strata.xcodeproj
```

`Strata.xcodeproj` is generated from `App/project.yml` and git-ignored. Re-run `xcodegen generate` after changing `project.yml`, or after adding or removing files.

## Layout

```text
App/
  project.yml            XcodeGen spec: targets, settings, Info.plist keys
  Strata/                SwiftUI app: AppModel, views, folder watching
  StrataTests/           App unit tests (models, persistence, refresh)
  StrataUITests/         XCUITest flows against fixture folders
Packages/StrataCore/
  Sources/StrataCore/
    Environment/         Where config lives on this machine; which file changes matter
    Parsing/             Frontmatter, JSON, @imports, secret masking
    Scanning/            One scanner per kind of configuration
    Resolution/          Precedence rules and diagnostics
    Model/               ConfigItem, Diagnostic, InspectionReport, queries
  Tests/StrataCoreTests/ Fixture-based tests for every rule
packaging/               Homebrew cask template
scripts/                 Release build, signing, packaging and install checks
docs/                    Architecture, resolution rules, release process
```

The split matters. Anything about how Claude Code loads configuration lives in StrataCore and is tested there; the app only displays a report. If you find yourself writing precedence logic in a view, move it into StrataCore.

## Running against your own configuration

Run the **Strata** scheme. It reads your real `~/.claude` and `~/.claude.json` but never writes to them.

To try it against a throwaway setup instead, edit the scheme and add these:

| Kind | Value |
| --- | --- |
| Launch argument | `-StrataUITesting` (uses a separate preferences domain, so your saved repository list is untouched) |
| Environment variable | `STRATA_UITEST_HOME=/path/to/fake/home` (where `.claude` and `.claude.json` are read from) |
| Environment variable | `STRATA_UITEST_REPOSITORY=/path/to/repo` (opened at launch) |

## Linting

```bash
swiftlint lint --strict
shellcheck scripts/*.sh
```

CI also runs `actionlint` on the workflows.

## Changing a resolution rule

1. Find the rule in [configuration-resolution.md](configuration-resolution.md) and check it against the linked Claude Code documentation.
2. Update the doc first, with the source link.
3. Add a failing fixture test in `Packages/StrataCore/Tests/StrataCoreTests`, then change the scanner or `Resolver`.
4. If the docs don't settle the question, the answer is **Unknown**, not a guess.
