# Changelog

All notable changes to Strata are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Permission rules** as their own items under Settings: every `allow`, `ask` and `deny` rule, extra directory and `defaultMode`, with the file that sets it. Rules a deny or ask rule certainly beats show as Overridden, repository allow rules that wait for workspace trust show as Conditional, and new allow rules get a security note in Review Changes.
- **Context at launch**: an estimate of how many tokens a repository's instruction files, skill listing and subagent descriptions take before your first message, in the summary bar, with a breakdown, the largest pieces, and each item's share in the inspector. It warns at the thresholds Claude Code documents, a CLAUDE.md over 200 lines and subagent descriptions over 15,000 tokens, and says plainly what it can't count.
- **Output styles, status line and keybindings** under Settings, and **plugin LSP servers and monitors** under Plugins. Strata shows which output style applies, raising an issue when `outputStyle` doesn't match a style's name exactly, which status line runs, each keybinding, and every command these run, masked and never started.
- **Export Report…** (⇧⌘E) saves a repository's report as Markdown or JSON, every item or only what the list shows, with secrets masked and home paths shortened to ~, to share in a pull request or issue.

## [0.4.0] - 2026-11-17

### Added

- On first launch, Strata suggests the folders Claude Code has been used in, from its project list in `~/.claude.json`, so you can add them with one click.
- **Hooks** category: every hook from your settings files and enabled plugins as its own item, with its event, matcher, what it runs (secrets masked) and the file that declares it. Hooks waiting for workspace trust show as Conditional, and ones that `disableAllHooks`, `allowManagedHooksOnly` or a duplicate turn off show as Inactive with the reason. ⌘6 opens it, and Instructions, Settings and Issues move to ⌘7 to ⌘9.
- **Report a Wrong Result…** in the inspector and the item list's context menu. It shows the text first, then opens a pre-filled GitHub issue in your browser with what Strata showed for the item, home paths shortened to ~ and secrets masked. Strata itself sends nothing.

## [0.3.0] - 2026-11-17

### Added

- **Filter chips** above the item list for status, scope and Has Issues. Each shows how many items it would show, chips that match nothing are hidden, and they share their state with the Filter menu.
- **About** in Settings, with Strata's version and build, and a **Check for Updates** button. It makes one request to GitHub for the latest release, only when you click. If there's a newer version, it shows a link to the release notes and the `brew upgrade` command to copy. Strata still never downloads or installs anything.
- **Uninstall…** for skills, commands and subagents in `~/.claude` or the repository's `.claude` folder, in the inspector and the list's context menu. The review says which copy runs instead, if any, and when a running Claude Code session stops seeing it. Like fixes, it keeps a backup and can be undone. Plugin, managed and claude.ai items aren't offered, with the reason why.
- **Disable / Enable** a plugin, by flipping its `enabledPlugins` entry in the settings file that decides it, and **Remove** an MCP server from `.mcp.json` or `~/.claude.json`. Only that entry changes; the rest of the file, including what Claude Code writes to `~/.claude.json`, is left as it was, and undo reverses just that entry. To uninstall a plugin, Strata shows the `claude plugin uninstall` command to copy.
- **Plugin updates**: each marketplace plugin's installed version next to the version in its marketplace copy on your Mac, in the inspector and in **Inspect → Check for Plugin Updates…**. It shows the `claude plugin marketplace update` and `claude plugin update` commands to copy, with the sources they contact. Strata itself never fetches anything.

### Changed

- The Settings switch for fixes is now **Let Strata change Claude Code configuration when you approve**, since it covers uninstalling, plugins and MCP servers too. Your existing choice carries over.

### Fixed

- In a window narrower than 1,200 points, the category picker is a pop-up instead of a segmented control. The full-width control pushed Filter, Rescan and the inspector button into the toolbar's » overflow menu.

## [0.2.0] - 2026-11-16

The first signed release, with change tracking: see what changed in your Claude Code configuration since you last looked, and fix overridden copies.

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
- **Status since your last review** on every changed item: a tag in the list and a line in the inspector, with a button to review that change. Possible statuses:
    - Changed: picked up by itself
    - Reload needed: run `/reload-skills` or `/reload-plugins`
    - New session
    - Conflict
    - Unverified: the docs don't say when it applies
- **Fixes for overridden copies**, off until you turn them on in Settings. When a skill, command or subagent in `~/.claude` or the repository's `.claude` folder is overridden, the inspector offers to remove it, or to replace it with the copy that runs. Before anything changes, a review screen shows:
    - what happens, and every file involved
    - a masked diff of the main file

  Strata then checks that neither copy changed since you opened the review. It only ever writes inside those two folders, never through a symbolic link. Each fix keeps a backup in `~/Library/Application Support/Strata/Backups` and can be undone from the result screen or Settings, unless that would overwrite something new.
- **Notifications for changes**, off until you turn them on in Settings:
    - edits that land within a few seconds of each other arrive as one notification, held back at most 30 seconds
    - each change is announced once until you review it
    - clicking a notification opens Review Changes
    - you can pause them for an hour or until tomorrow, or silence one repository from its menu in the sidebar

### Changed

- Releases are signed with a Developer ID certificate and notarised by Apple, so Strata opens normally after a Homebrew install. 0.1.0 was unsigned: if you installed it, `brew upgrade --cask strata-inspector` replaces it.

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

[0.4.0]: https://github.com/Dillan-03/strata/releases/tag/v0.4.0
[0.3.0]: https://github.com/Dillan-03/strata/releases/tag/v0.3.0
[0.2.0]: https://github.com/Dillan-03/strata/releases/tag/v0.2.0
[0.1.0]: https://github.com/Dillan-03/strata/releases/tag/v0.1.0
