# Strata

Strata is a native macOS app that shows where your Claude Code configuration comes from. Pick a repository and it lists every skill, command, subagent, MCP server, plugin, instruction file and setting that would apply in a new session there. For each one it shows:

- which copy wins
- which copies it overrides
- the file each copy lives in
- why the winner wins

It's for questions like *"Why isn't my repo's `/deploy` skill running?"* (a personal one with the same name wins) or *"Which `.mcp.json` server needs approval?"*.

When configuration changes on disk, from any editor or a `git checkout`, **Review Changes** shows what changed since you last looked. It shows each change as a diff with secrets masked. It also shows the repositories each change reaches, and whether a running Claude Code session picks it up. One click copies a prompt you can paste into that session so it knows what changed.

Strata only reads Claude Code configuration unless you turn on **changes** in Settings. With that on, it can uninstall a skill, command or subagent, remove an overridden copy or replace it with the copy that runs, disable or enable a plugin, and remove an MCP server. To uninstall a plugin, it shows the `claude plugin uninstall` command to copy, because Strata never runs commands. It always shows you exactly what will change first, keeps a backup, and lets you undo. It never runs MCP servers, and it makes no network requests unless you click **Check for Updates** in Settings.

![Strata's inspector for a /deploy skill: the global copy runs and the repository's copy is overridden](https://raw.githubusercontent.com/Dillan-03/strata/screenshots/inspector.png)

| Issues | An MCP server awaiting approval |
| --- | --- |
| ![The issues list, led by a global skill hiding the repository's copy](https://raw.githubusercontent.com/Dillan-03/strata/screenshots/issues.png) | ![An MCP server from .mcp.json, shown as Conditional until approved, with Strata's note that it never runs servers](https://raw.githubusercontent.com/Dillan-03/strata/screenshots/mcp.png) |

![Review Changes: a global skill's description edited, shown as a line diff, picked up live by Claude Code](https://raw.githubusercontent.com/Dillan-03/strata/screenshots/review.png)

Screenshots are captured from the real app by CI whenever the app changes on `main`, using made-up configuration.

## Requirements

- macOS 15 Sequoia or later. CI tests every release on macOS 15 and 26.
- Apple silicon or Intel

## Install

```bash
brew tap dillan-03/strata https://github.com/Dillan-03/strata
brew install --cask dillan-03/strata/strata-inspector
```

Or download `Strata-<version>.zip` from [Releases](https://github.com/Dillan-03/strata/releases), unzip it, and move `Strata.app` to Applications.

> [!NOTE]
> From 0.2.0, releases are signed with a Developer ID certificate and notarised by Apple, so Strata opens normally. 0.1.0 was an unsigned pre-release that macOS blocks at first launch. If you have it, `brew upgrade --cask strata-inspector` replaces it. Each release's notes say whether that build is signed.

| Task | Command |
| --- | --- |
| Upgrade | `brew upgrade --cask strata-inspector` |
| Uninstall | `brew uninstall --cask strata-inspector` |
| Uninstall and remove Strata's preferences and caches | `brew uninstall --zap --cask strata-inspector` |

Uninstalling never touches `~/.claude`, `~/.claude.json`, your repositories, or anything belonging to another app. [docs/distribution.md](docs/distribution.md) lists exactly what `--zap` removes.

## What it reads

| Kind | Sources |
| --- | --- |
| Skills and commands | `~/.claude/skills`, `.claude/skills` (including nested folders), `.claude/commands`, managed skills, plugin skills, claude.ai synced skills |
| Subagents | `~/.claude/agents`, `.claude/agents`, managed and plugin agents |
| MCP servers | `~/.claude.json` (user and per-project), `.mcp.json`, plugin `.mcp.json` and `plugin.json` |
| Plugins | `enabledPlugins` in every settings file, `~/.claude/plugins/installed_plugins.json` |
| Hooks | `hooks` in every settings file, and each enabled plugin's `hooks/hooks.json` and manifest |
| Instructions | `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules`, `AGENTS.md`, parent folders, `@imports` |
| Settings | Managed, `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json` |

Managed configuration is read from `/Library/Application Support/ClaudeCode`. `CLAUDE_CONFIG_DIR` is honoured when the app inherits it.

Every precedence rule Strata applies is written down, with a link to the Claude Code documentation it comes from, in [docs/configuration-resolution.md](docs/configuration-resolution.md).

## Privacy

- No accounts, analytics or telemetry.
- One network request, only when you click **Check for Updates** in Settings: a GET to GitHub's API for this repository's latest release, with no cookies or account details. GitHub sees your IP address, as it would for any web request. Strata never downloads or installs anything. Homebrew does the upgrade.
- **Report a Wrong Result…** shows you the text first, then opens a GitHub issue in your browser with home paths shortened to `~` and secrets masked. Strata sends nothing itself.
- Strata never contacts plugin marketplaces. **Check for Plugin Updates…** compares against the marketplace copies already on your Mac, and shows the `claude plugin` commands that refresh and update them for you to run.
- Read-only by default. Changes are off until you turn them on, and then they only write after you approve each one. They write only to `~/.claude`, `~/.claude.json`, and the inspected repository's `.claude` folder and `.mcp.json`, never through a symbolic link. JSON files are edited one entry at a time, leaving the rest of the file as it was, and every change keeps a backup in `~/Library/Application Support/Strata/Backups`.
- MCP server commands are displayed, never run. Remote servers are never contacted.
- Values that look like credentials (API keys, tokens, passwords, `Authorization` headers, secret-looking environment variables) are masked before they reach the UI.
- Strata stores its own settings and the list of repositories you've added in `~/Library/Preferences/com.dillankerai.strata.plist`. It also keeps backups of copies a fix changed, which hold those files as they were, secrets included.

## Limitations

- **Strata can't see inside a running Claude Code session.** It reads files on disk and reports what *applies* to a new session started at the repository root. A session that's already running may have loaded something else. For example, plugin changes only take effect after `/reload-plugins` or a restart.
- It assumes `claude` is started at the repository root. Starting in a subdirectory can change which nested skills and instruction files load.
- Command-line flags (`--settings`, `--agents`, `--add-dir`, `--plugin-dir`, `--mcp-config`), server-managed settings from the claude.ai console, MDM profiles and claude.ai connectors aren't visible to it.
- Workspace trust is stored in an undocumented form, so anything that depends on trust is shown as **Conditional**, not resolved.
- When the Claude Code documentation doesn't settle a rule, Strata shows **Unknown** rather than guessing.

## Development

```bash
swift test --package-path Packages/StrataCore   # the rules engine; runs on macOS and Linux
brew install xcodegen
cd App && xcodegen generate && open Strata.xcodeproj
```

- [docs/architecture.md](docs/architecture.md): how the app and the rules engine fit together, and why the app isn't sandboxed.
- [docs/development.md](docs/development.md): local setup, project layout, linting.
- [docs/testing.md](docs/testing.md): the test suites and how CI runs them.
- [docs/release-process.md](docs/release-process.md): tagging, signing and publishing.
- [CONTRIBUTING.md](CONTRIBUTING.md): the issue → branch → PR workflow.

## License

[MIT](LICENSE)
