# How Strata resolves Claude Code configuration

Strata reads files on disk and applies the rules below to work out what applies to a repository. Every rule comes from the official Claude Code documentation, linked in each section and checked in November 2026. When the docs don't say, Strata shows **Unknown** instead of guessing.

> **The big limit:** Strata does static inspection. It can't see inside a running Claude Code session, so it never claims something *is loaded*. It says something *applies* when files on disk mean Claude Code will use it in a new session started at the repository root.

## Statuses

| Status | Meaning |
| --- | --- |
| **Applies** | Will be used, and wins any name clash. |
| **Applies (combined)** | Used alongside other definitions: instruction files, list settings, namespaced plugin skills. |
| **Overridden** | Another definition with the same name wins. The inspector links to it. |
| **Conditional** | Used only under a condition: on-demand loading, an approval prompt, workspace trust. |
| **Inactive** | Present but turned off, excluded, or not installed. |
| **Won't load** | Claude Code skips it because of an error. A diagnostic explains the fix. |
| **Unknown** | The docs don't settle it. |

Plugins also show the furthest **stage** they reached: Declared (only in settings), Installed (files on disk) or Enabled.

## Where Strata assumes the session starts

Strata assumes you run `claude` at the repository root you added. Many rules depend on the working directory: nested skills, ancestor CLAUDE.md files, and where `settings.local.json` is read from. Starting in a subdirectory can change the result.

## Skills and commands

Source: [Skills](https://code.claude.com/docs/en/skills.md).

**Locations**
- Enterprise: `.claude/skills/<name>/SKILL.md` in the managed settings directory
- Personal: `~/.claude/skills/<name>/SKILL.md`
- Project: `.claude/skills/<name>/SKILL.md`
- Nested: `<subdir>/.claude/skills/<name>/SKILL.md`
- Plugin: `<plugin>/skills/<name>/SKILL.md`, or a root `SKILL.md`
- claude.ai account: `~/.claude/skills/synced/`
- Legacy command files: `.claude/commands/**/*.md`, named by relative path with `/` replaced by `:`

**Same name in more than one place**

| Same name in | Which runs |
| --- | --- |
| Enterprise, personal and project | Enterprise over personal, personal over project |
| A skill and a command file | The skill |
| Root and nested skills | Both load; the nested one is listed as `/<subdir>:<name>` |
| Plugin skill and any other | Both load; plugin skills are `/plugin:name` |
| A claude.ai skill and any other | The other one; the synced skill runs only under its full name |

**Won't load:** a bare `.md` directly in `skills/`, a folder with no `SKILL.md`, folder names `synced` or `anthropic-skills…` outside a plugin, and names containing characters such as zero-width spaces or `<`.

**When they load:** nested skills load the first time Claude reads or edits a file in that subdirectory, or with `/add-dir`. Skill text is watched live; plugin changes need `/reload-plugins`.

## Subagents

Source: [Subagents](https://code.claude.com/docs/en/sub-agents.md).

**Identity** comes from the frontmatter `name`, never the file name. `name` and `description` are required. Names can't contain `:`.

**Priority**, highest first:
1. Managed settings
2. `--agents` CLI flag (not visible to Strata)
3. Project `.claude/agents/`
4. User `~/.claude/agents/`
5. Plugin `agents/`

**This is the opposite of skills.** A repo subagent beats your personal one, but a personal skill beats the repo's.

Two files in the same agents folder (including subfolders) with the same `name` load in an undocumented order, so Strata marks both Unknown. Plugin agent subfolders become part of the scoped name, such as `my-plugin:review:security`.

## MCP servers

Source: [MCP](https://code.claude.com/docs/en/mcp.md).

**Locations**
- Local: `~/.claude.json` → `projects["<repo path>"].mcpServers`
- Project: `.mcp.json` at the repository root
- User: `~/.claude.json` → `mcpServers`
- Plugin: `.mcp.json` at the plugin root, or `mcpServers` in `plugin.json`
- Managed: `managed-mcp.json` in the managed directory

**Precedence:** local, then project, then user, then plugin, then claude.ai connectors.
- The whole entry comes from the winner. **Fields are never merged** across scopes.
- The three scopes match duplicates by **name**.
- Plugins and connectors match by **endpoint**. Scheme and host case, default ports and trailing slashes don't make a difference; path, query, user info and non-default ports do.

**Configuration errors:** an entry with a `url` but no `type` is read as stdio and skipped. `type: "sdk"` is skipped. `streamable-http` is an alias for `http`.

**Project servers need approval.** Claude Code asks the first time an interactive session starts.
- `enabledMcpjsonServers` or `enableAllProjectMcpServers` in your own settings or `~/.claude.json` approves a server.
- The same keys committed in `.claude/settings.json` only count after you trust the workspace.
- `disabledMcpjsonServers` in any file rejects a server.
- Servers you toggle off in `/mcp` are recorded per project in `~/.claude.json` under `disabledMcpServers`.

**What Strata never does:** run a server command or connect to a server. "Command not found" checks only look for the file. Bare commands are looked up on PATH and standard folders, and marked Info rather than an error, because apps launched from the Dock don't see your shell's PATH.

## Plugins

Sources: [Plugin loading](https://code.claude.com/docs/en/plugins/loading.md), [Install plugins](https://code.claude.com/docs/en/plugins/install.md).

**Stages:** declared in settings (`enabledPlugins`) → fetched to disk (`~/.claude/plugins/installed_plugins.json` and `cache/`) → loaded by a session. Strata sees the first two. The third only changes after `/reload-plugins` or a restart.

**Enablement** is decided per plugin id (`name@marketplace`) by the highest-precedence settings file that mentions it. Lowest to highest:
1. `--add-dir`
2. User
3. Project
4. Local
5. `--settings` flag
6. Managed

A managed `true` force-enables and a managed `false` blocks. A file that doesn't mention the id leaves the lower value in place. A plugin that no file mentions uses its manifest's `defaultEnabled`, which defaults to `true`.

**Other origins**
- `@skills-dir`: a skill folder with `.claude-plugin/plugin.json`
- `@synced`: from claude.ai, in `~/.claude/plugins/synced/`
- `@inline`: `--plugin-dir`, which Strata can't see

A plugin enabled by the repository's `.claude/settings.json` loads only after workspace trust, so Strata marks it Conditional.

`installed_plugins.json` isn't formally documented. Strata reads both the object-per-plugin and array-of-installs shapes and reports anything else as an unrecognised format.

## Instructions (CLAUDE.md, rules, AGENTS.md)

Source: [Memory](https://code.claude.com/docs/en/memory.md).

**Instruction files are concatenated, never overridden.** Strata lists them in load order, broadest first:

1. Managed `CLAUDE.md`
2. `~/.claude/CLAUDE.md` and `~/.claude/rules/`
3. Each folder above the repository, from `/` down: `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`
4. The repository: `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/**/*.md`

Within a folder, `CLAUDE.local.md` comes after `CLAUDE.md`. The docs don't state the order between `./CLAUDE.md` and `./.claude/CLAUDE.md`.

**Rules** with `paths` frontmatter load only when Claude touches matching files.

**Subdirectory** `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md` and rules load on demand, when Claude reads or edits a file in that folder.

**AGENTS.md** is read only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists in the working directory or above it. `~/.claude/CLAUDE.md`, managed files and rules don't count towards that check. The **Project instructions** setting changes this:
- `claude-md-or-agents-md` (the default)
- `claude-md-and-agents-md`
- `claude-md`
- `managed-only`

It's read from user and managed settings only (`pluginConfigs["cc-plugin-agents-md@builtin"].options.instructionFiles`).

**Imports** (`@path`):
- Resolved relative to the importing file, and followed up to **four hops**.
- Imports inside code spans and fenced blocks are skipped, and `\ ` escapes a space.
- An import in a project file that points outside the repository triggers a one-time approval dialog.

**`claudeMdExcludes`** are glob patterns matched against absolute paths. They merge across every settings layer and can't exclude the managed CLAUDE.md.

## Settings

Sources: [Settings](https://code.claude.com/docs/en/settings.md), [`.claude` directory](https://code.claude.com/docs/en/claude-directory.md).

**Files**
- Managed: `managed-settings.json`
- User: `~/.claude/settings.json`
- Shared project: `.claude/settings.json`
- Project local: `.claude/settings.local.json`

**Precedence:** managed, then `--settings`, then local, then project, then user.

| Key type | Rule |
| --- | --- |
| Scalars | The highest file that sets the key wins |
| Lists | Merge across files |
| `fallbackModel` | Whole value from the highest file |
| `modelPicker` | From managed or user settings only; ignored in project and local |
| `availableModels` | A managed list applies as-is; otherwise lists merge |
| `permissions` | Rules from every file combine |
| `hooks` | Hooks from every file apply |
| `enabledPlugins` | Merged per plugin id (see Plugins) |
| Other objects, such as `env` and `modelSettings` | The docs don't say whether keys merge, so Strata shows Unknown when more than one file sets them |

Environment variables aren't a level in this stack, and Strata can't see them. A few security keys honour a stricter value from a lower file even over managed settings.

## Changes between scans

Strata compares each scan with the one before it and reports what was added, edited, removed or moved. That covers edits from any editor, tool or `git checkout` (`ChangeDetector`).

- **Edited** means the item's fingerprint changed. The fingerprint is a hash of its file, or of its own entry in a JSON file. Key order and whitespace in JSON don't count. Fingerprints stay in memory and are never shown or saved.
- **Moved** means one item disappeared and another of the same kind appeared with identical content. This applies to skills, commands, subagents, instruction files and MCP servers. It doesn't apply to settings or plugins, where two unrelated entries can hold the same value.
- **Reach**:
    - global: managed, `~/.claude`, plugins and claude.ai, which affect every repository
    - shared: parent-folder instruction files, which affect every repository under that folder
    - repository: everything else
- A status change caused by another item isn't reported against the item that didn't change. For example, a new repo skill overriding a global one is reported as the repo skill being added, not as an edit to the global skill.

### When a running session sees a change

Strata can't see inside a running session. This is what the Claude Code docs say, as of November 2026.

| Change | Running session | Source |
| --- | --- | --- |
| Skill in `~/.claude/skills` or the project's `.claude/skills` | Picked up live. A skills folder created after the session started needs `/reload-skills`; Strata suggests it for the first skill in a folder | [Skills](https://code.claude.com/docs/en/skills#edit-a-skill-during-a-session) |
| Subagent in `~/.claude/agents` or the project's `.claude/agents` | Picked up within seconds. The first agent in a folder created after the session started needs a restart | [Subagents](https://code.claude.com/docs/en/sub-agents#write-subagent-files) |
| Plugin, a plugin's skills, agents or MCP servers, or `enabledPlugins` | `/reload-plugins`, or a new session | [Plugins](https://code.claude.com/docs/en/plugins/install#keep-plugins-updated) |
| Settings | Reloaded live, except `model`, `effortLevel` and `modelSettings`, which are read at session start | [Settings](https://code.claude.com/docs/en/settings#when-edits-take-effect) |
| Instruction files loaded at launch | A new session. The project-root `CLAUDE.md` is also re-read after `/compact` | [Memory](https://code.claude.com/docs/en/memory) |
| Subdirectory `CLAUDE.md` and path-scoped rules | The next time they load on demand | [Memory](https://code.claude.com/docs/en/memory) |
| MCP servers in `~/.claude.json` or `.mcp.json` | Unknown: the docs don't say | [MCP](https://code.claude.com/docs/en/mcp) |
| Commands in `.claude/commands`, nested, managed and claude.ai skills | Unknown: the docs don't say | [Skills](https://code.claude.com/docs/en/skills) |

## Not covered in v0.1

- Anything passed on the command line: `--settings`, `--agents`, `--add-dir`, `--plugin-dir`, `--mcp-config`
- Environment variables, including `CLAUDE_CONFIG_DIR` when the app isn't launched from a shell that sets it
- Server-managed settings delivered from the claude.ai console, and MDM profiles
- claude.ai connectors
- Output styles, workflows, keybindings and themes
- Whether a workspace is trusted, which lives in `~/.claude.json` in an undocumented form
