# Architecture

Strata has two parts with a hard line between them.

```text
App/ (SwiftUI, macOS only)              Packages/StrataCore/ (Foundation only)
┌──────────────────────────────┐        ┌───────────────────────────────────┐
│ Views  ─►  AppModel           │ uses   │ Scanners  ─►  Resolver  ─►  Report │
│ (no logic, no file access)    │ ─────► │ (file reading)  (precedence rules)  │
│ FSEvents watcher, NSWorkspace │        │ Diagnostics, Redaction              │
└──────────────────────────────┘        └───────────────────────────────────┘
```

- **StrataCore** holds every rule about Claude Code configuration. It builds and tests on Linux as well as macOS, so the rules are tested without Xcode and without a UI.
- **The app** turns a `Report` into lists and an inspector, watches folders for changes, and opens files in Finder. Views stay thin; anything worth testing lives in a model with unit tests.

## Why the app isn't sandboxed

Claude Code keeps its user-level configuration in `~/.claude/` and `~/.claude.json`. A sandboxed app can only read folders the user picks in an open panel, so it would have to ask for your home folder before it could show anything useful. That is a worse privacy trade than a non-sandboxed app that only ever reads.

What Strata does instead:

- **Hardened runtime** is on for release builds (required for notarisation).
- **Read-only by default.** The only code that writes Claude Code configuration is `ConfigWriter`, in StrataCore. It runs only when changes are on in Settings and the user approves one. JSON files (`~/.claude.json`, `.mcp.json`, settings) are edited one entry at a time by `JSONTextEdit`, keeping every other byte and the file's permissions. It refuses:
    - anything outside `~/.claude` and the inspected repository's `.claude` folder
    - anything reached through a symbolic link
    - anything that changed since the fix was reviewed
- **One network request, on click or opt-in.** **Check for Updates** in Settings sends one GET to GitHub's latest-release API through an ephemeral `URLSession` (no cookies, cache or stored credentials). **Check for updates automatically**, off by default, sends the same request when the app opens, at most once a day (`UpdateChecker.isAutomaticCheckDue`). There are no timers or background tasks. StrataCore's `UpdateChecker` parses the reply and builds the release link from the version, never from the response. The app never downloads or installs anything. Plugin update checks read the marketplace copies Claude Code keeps on disk; refreshing them is a command the user runs.
- **One command, on approval.** MCP server commands are displayed, never run. The only process Strata starts is `claude plugin uninstall`, from `PluginUninstallSheet` after the user confirms it, with arguments built by StrataCore's `PluginUninstall` and no shell.

## Generated project

`App/project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` in `App/` to create `Strata.xcodeproj`, which is git-ignored. This keeps merge conflicts out of `project.pbxproj` and keeps the build reproducible in CI.

## Minimum macOS

macOS 15 (Sequoia). The UI uses `NavigationSplitView`, `.inspector`, `ContentUnavailableView` and the Observation framework, which need macOS 14; the minimum is 15 because that's the oldest macOS CI can test on, since GitHub retired its macOS 14 runners in November 2026. StrataCore itself still builds for macOS 14, since it uses only Foundation.
