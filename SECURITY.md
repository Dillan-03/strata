# Security Policy

## What Strata does with your data

- Reads Claude Code configuration files on your Mac: `~/.claude/`, `~/.claude.json`, and the repositories you add.
- Never writes to them in v0.1.
- Never sends anything over the network. No accounts, analytics or telemetry.
- Never runs MCP server commands or contacts MCP servers.
- Masks secrets (tokens, API keys, passwords, header values, environment values) before showing anything in the UI.

## Supported versions

Only the latest release gets security fixes.

## Reporting a vulnerability

Please don't open a public issue. Use **[Report a vulnerability](https://github.com/Dillan-03/verbose-octo-carnival/security/advisories/new)** on GitHub.

Include what you found, how to reproduce it, and what an attacker could do with it. You'll get a reply within 7 days.

Especially welcome:

- A way for Strata to display, log or leak an unmasked secret
- A way for a crafted repository to make Strata execute code, write files or follow paths outside what it should read
- Crashes triggered by malformed configuration files
