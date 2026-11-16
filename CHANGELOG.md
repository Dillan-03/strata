# Changelog

All notable changes to Strata are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Review Changes**: everything that changed in your Claude Code configuration since you last reviewed it, in one list. Each change shows:
    - a line diff for Markdown files, or a key-by-key diff for JSON entries, with secrets masked
    - the repositories it reaches, and whether a repository's own copy overrides it
    - when a running Claude Code session sees it, with the docs source
    - conflicts, and security notes for hooks, permissions, MCP servers, plugins and `allowed-tools`
- **Copy Prompt for Claude Code** on each change. It's a ready-to-paste message telling a running session:
    - what changed and where, and which repositories it reaches
    - the diff, with secrets masked, and any conflicts
    - how to confirm it has the new version
  It also says when to run `/reload-skills` or `/reload-plugins` first. It only goes to the clipboard.

### Fixed

- A password inside a URL passed as an MCP server argument, such as a database connection string, was shown unmasked in the inspector.

## [0.1.0] - 2026-11-14

First release. Unsigned: builds are ad-hoc signed and not notarised until Developer ID signing is set up ([#22](https://github.com/Dillan-03/strata/issues/22)).

### Added

- Add repositories from any folder. The list is remembered between launches, and moved or missing folders are detected.
- Inspection of skills, legacy commands, subagents, MCP servers, plugins, instruction files and settings, read from managed, global, repository, local, nested, parent-folder, plugin and claude.ai sources.
- Precedence rules for every kind, sourced from the Claude Code documentation, with a plain-language explanation of why each item applies, is combined, is overridden or won't load. Where the documentation is silent, Strata shows Unknown.
- Diagnostics for overridden definitions, duplicate names, malformed JSON and frontmatter, unreadable files, MCP entries with a missing type or executable, missing and external `@imports`, plugins enabled but not installed, and an `AGENTS.md` that is ignored because a `CLAUDE.md` exists.
- Inspector sections: Which Copy Runs, Where It's Set, Contributes (including plugin hooks), Imports, and Load Order at Session Start.
- Search across names, invocations, descriptions and paths, with filters for scope, status and items with issues.
- Automatic refresh when configuration changes on disk, debounced and limited to the affected repository, with a setting to turn it off. ⌘R refreshes by hand.
- Masking of credentials in MCP headers, environment values, arguments and URLs before anything reaches the UI.
- App icon: three stacked layers with the one that wins on top, drawn on Apple's macOS icon template.
- Homebrew cask `strata-inspector`, installed from this repository as a tap.
- Release pipeline that builds a universal app, labels unsigned builds honestly, and verifies checksum, signature, launch and the Homebrew install, uninstall and zap round trip on macOS 15 and 26.
- Issue forms, a pull request template, an issue-title check, and contributing, code of conduct and security documents.

### Known limitations

- Static inspection only: Strata can't see what a running Claude Code session has loaded.
- Command-line flags, server-managed settings, MDM profiles and claude.ai connectors aren't visible.
- Requires macOS 15 Sequoia or later.

[0.1.0]: https://github.com/Dillan-03/strata/releases/tag/v0.1.0
