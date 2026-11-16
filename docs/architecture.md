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
- **Read-only by default.** The only code that writes Claude Code configuration is `ConfigWriter`, in StrataCore. It runs only when fixes are on and the user approves a fix. It refuses:
    - anything outside `~/.claude` and the inspected repository's `.claude` folder
    - anything reached through a symbolic link
    - anything that changed since the fix was reviewed
- **No network.** The app makes no network requests.
- **No execution.** MCP server commands are displayed, never run.

## Generated project

`App/project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` in `App/` to create `Strata.xcodeproj`, which is git-ignored. This keeps merge conflicts out of `project.pbxproj` and keeps the build reproducible in CI.

## Minimum macOS

macOS 15 (Sequoia). The UI uses `NavigationSplitView`, `.inspector`, `ContentUnavailableView` and the Observation framework, which need macOS 14; the minimum is 15 because that's the oldest macOS CI can test on, since GitHub retired its macOS 14 runners in November 2026. StrataCore itself still builds for macOS 14, since it uses only Foundation.
