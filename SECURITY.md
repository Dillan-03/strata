# Security Policy

## What Strata does with your data

- Reads Claude Code configuration files on your Mac: `~/.claude/`, `~/.claude.json`, and the repositories you add.
- Never writes to them unless you turn on changes in Settings. Then it writes only the change you approve, only inside `~/.claude`, `~/.claude.json`, or the inspected repository's `.claude` folder and `.mcp.json`, never through a symbolic link, and only if the file or copy hasn't changed since you reviewed it. JSON files are edited one entry at a time, keeping their permissions. Every change keeps a backup in `~/Library/Application Support/Strata/Backups` and can be undone. The one command Strata runs is `claude plugin uninstall <id> --scope <scope>`, only when changes are on and you confirm it on a screen that shows the exact command. It runs `claude` from `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin` without a shell, in the repository's folder, with an empty stdin and a 60-second limit, and refuses a plugin ID that starts with `-`. Strata can't undo an uninstall, so the screen shows the reinstall command and keeps the plugin's data folder by default.
- Makes one network request, only when you click **Check for Updates** in Settings, or when it opens at most once a day if you turn on **Check for updates automatically** (off by default): a GET to `https://api.github.com/repos/Dillan-03/strata/releases/latest`, with no cookies, cache or account details. GitHub sees your IP address, as it would for any web request. It never downloads or installs anything. No accounts, analytics or telemetry.
- **Export Report…** writes only the file you choose, with secrets masked and home paths shortened to `~`.
- **Report a Wrong Result…** shows the issue text first, then hands a GitHub link to your browser, with home paths shortened to `~` and secrets masked. Strata sends nothing itself.
- Never runs MCP server commands or contacts MCP servers, and never contacts plugin marketplaces. Plugin updates are `claude plugin` commands it shows for you to run.
- Masks secrets (tokens, API keys, passwords, header values, environment values) before showing anything in the UI.

## Supported versions

Only the latest release gets security fixes.

## Reporting a vulnerability

Please don't open a public issue. Use **[Report a vulnerability](https://github.com/Dillan-03/strata/security/advisories/new)** on GitHub.

Include what you found, how to reproduce it, and what an attacker could do with it. You'll get a reply within 7 days.

Especially welcome:

- A way for Strata to display, log or leak an unmasked secret
- A way for a crafted repository to make Strata execute code, write files or follow paths outside what it should read
- Crashes triggered by malformed configuration files
