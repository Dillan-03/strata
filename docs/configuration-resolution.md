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

## Hooks

Strata lists every hook handler as its own item, showing its event, matcher, type, what it runs, and the file that declares it (`HookScanner`). Commands, URLs and prompts are masked like any other value.

- **Where they come from:** `hooks` in managed, user, project and local settings. For each enabled plugin, they also come from `hooks/hooks.json` and the manifest's `hooks`, which can be a file, an inline event map, or a list of both. A plugin hooks file must have the `{"hooks": …}` wrapper, or Claude Code won't load it, so Strata skips it too. ([Hook locations](https://code.claude.com/docs/en/hooks#configuration), [plugin hooks](https://code.claude.com/docs/en/plugins-reference#hooks))
- **They add up:** hooks merge across settings files rather than overriding each other, and a plugin's hooks merge with them. So every hook applies, and none is "overridden". A handler defined identically in more than one settings file runs once, so Strata marks the lower-precedence copies inactive. A plugin's copy stays separate. ([Hook handler fields](https://code.claude.com/docs/en/hooks#hook-handler-fields))
- **Workspace trust:** in an interactive session, Claude Code holds back hooks from every settings file, including `~/.claude/settings.json`, until the folder is trusted. Strata can't read trust, so these hooks are **Conditional**. Plugin hooks follow their plugin: Conditional when the repository enables it. ([Workspace trust](https://code.claude.com/docs/en/hooks#workspace-trust))
- **`disableAllHooks`:** Strata takes the value left after settings precedence. `true` in user, project or local settings turns off user, project, local and plugin hooks, but managed hooks and plugins force-enabled by managed settings keep running. `true` in managed settings turns off every hook. ([Disable or remove hooks](https://code.claude.com/docs/en/hooks#disable-or-remove-hooks), [`disableAllHooks`](https://code.claude.com/docs/en/settings-reference#disableallhooks))
- **`allowManagedHooksOnly`** in managed settings turns off user, project, local and plugin hooks. The exception is plugins that managed `enabledPlugins` force-enables. ([`allowManagedHooksOnly`](https://code.claude.com/docs/en/settings-reference#allowmanagedhooksonly))
- **Running sessions:** Claude Code's file watcher picks up hook edits in settings files without a restart. Plugin hooks change with their plugin, after `/reload-plugins`.

Not covered:
- **Skill and subagent frontmatter hooks:** they only run while that skill or subagent is in use.
- **Hooks passed with `--settings`.**
- **Whether a hook's matcher fires for a given tool:** that depends on the session.

## Permissions

Strata lists every permission rule as its own item, under Settings, with the list it's in (allow, ask or deny), its tool and specifier, and the file that declares it (`PermissionScanner`). Extra directories and `defaultMode` are items too. Rules are masked like any other value.

- **Every file's rules apply.** Rules from managed, user, project and local settings combine. Claude Code checks them in order, deny, then ask, then allow, and the first match decides. A more specific rule doesn't change that order, so an allow rule can't carve an exception out of a deny rule, and a matching ask rule prompts even when a narrower allow rule matches. A deny in any file beats an allow in any other. ([Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions), [settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence))
- **Overridden:** an allow or ask rule is marked overridden only when another rule certainly matches every call it does: a deny (or, for an allow rule, an ask) rule for the same tool with no specifier, or with the same specifier. `Tool(*)` is the same as `Tool`. Strata doesn't work out glob overlaps, and the explanation says so. ([Permission rule syntax](https://code.claude.com/docs/en/permissions#permission-rule-syntax))
- **Workspace trust:** `allow` rules and `additionalDirectories` in a project's `.claude/settings.json` apply only after you accept the workspace trust dialog, so Strata shows them as **Conditional**. `deny` and `ask` rules aren't affected, since they only restrict. ([Project allow rules and workspace trust](https://code.claude.com/docs/en/permissions#project-allow-rules-and-workspace-trust))
- **Local settings** are normally your own file, so their allow rules apply without trust. When `.claude` is a symbolic link, Claude Code treats them as the repository's and waits for trust, so Strata does too. Telling whether the file is tracked in git needs git, which Strata never runs, so the item says so instead. ([When your local settings file needs trust](https://code.claude.com/docs/en/permissions#when-your-local-settings-file-needs-trust))
- **`allowManagedPermissionRulesOnly`** in managed settings makes them the only source of permission rules, so every other file's rules are Inactive. ([Managed settings](https://code.claude.com/docs/en/permissions#managed-settings))
- **`defaultMode`** follows settings precedence: the highest-precedence file's value wins. A `bypassPermissions` in project or local settings is Inactive, because Claude Code 2.1.257 and later ignore it there.
- **Running sessions:** Claude Code reloads settings files when they change, including permissions. ([When edits take effect](https://code.claude.com/docs/en/settings#when-edits-take-effect))

Not covered:
- **Rules passed on the command line:** `--allowedTools`, `--disallowedTools` and `--settings`.
- **Rules added in a session with `/permissions`** that aren't saved to a file.
- **Whether a rule matches a particular call.**

## Context at launch

Strata estimates how much context a repository's configuration takes before the first message (`ContextEstimate`).

- **Counted:**
  - **Instruction files that load at launch:** CLAUDE.md and CLAUDE.local.md in the repository and the folders above it, rules without `paths`, and what they import. Subdirectory CLAUDE.md files and path-scoped rules load later, when Claude touches a matching file, so they aren't counted. ([How CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load))
  - **The skill listing:** each skill's name, description and `when_to_use`. The skill's body loads only when it's invoked, so it isn't counted. Skills with `disable-model-invocation` aren't listed for Claude, so they don't count either. Claude Code trims the listing to fit a budget, so the real figure can be lower. ([Skills](https://code.claude.com/docs/en/skills))
  - **Subagent descriptions.** ([Automatic delegation](https://code.claude.com/docs/en/sub-agents#understand-automatic-delegation))
- **Not counted:**
  - MCP tools, which are deferred by default, so only their names load, and Strata never runs a server to list them ([tool search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search))
  - Claude Code's own system prompt
  - auto memory
- **Tokens are characters ÷ 4,** labelled as an estimate everywhere, because the docs don't document the tokenizer. `/context` in a session gives Claude Code's own count.
- **Warnings** appear only at documented thresholds:
  - a CLAUDE.md over 200 lines, from Claude Code's guidance to keep each one under 200
  - subagent descriptions over 15,000 tokens, where Claude Code itself warns at startup

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

### Reviewing a change

The app keeps each repository's first scan of the session as its starting point and lists every change since then in **Review Changes**. A global change shows up in every repository's scan, so it's listed once, with the repositories it reaches (`ChangeImpact`). **Mark All as Reviewed** makes the current scans the new starting point. Starting points live in memory, so the list starts empty at each launch.

To show a diff, each scan keeps a masked copy of what defines each item (`ItemContent`). Masking happens before the copy leaves the scan:

- **Markdown files** (skills, commands, subagents, instruction files): token-shaped strings are masked anywhere. The value is also masked in a `NAME=value` or `NAME: value` line whose name looks sensitive (`token`, `secret`, `password`, `auth`, `key` and similar). A value with spaces is prose and stays.
- **JSON entries** (MCP servers, settings, plugin records) are compared key by key:
    - every value under `env` or `headers` is masked
    - values whose key looks sensitive are masked
    - credentials in URLs are masked, including database connection strings passed as arguments
    - secret flags in `args` are masked
- A value that changed behind the mask is still reported, from a hash of the real value. The hash is never shown.

### Fixing an overridden copy

With fixes turned on in Settings, the inspector offers fixes for an overridden copy (`FixPlanner`). It does this only when:

- the copy is a skill, command or subagent: things that are whole files or folders, unlike MCP servers and settings, which sit inside JSON files Claude Code also writes
- it's in `~/.claude` or the inspected repository's `.claude` folder, never managed configuration, a plugin, a parent folder or another repository
- nothing between that folder and the copy is a symbolic link

The fixes:

- **Remove this copy** moves it into `~/Library/Application Support/Strata/Backups`. A skill moves as its whole folder.
- **Replace with the copy that runs** overwrites it with the winner, when the winner is the same kind and also in one of those two folders. The fix review screen says when this copies personal configuration into a repository, or the other way round.

`ConfigWriter` is the only code that writes Claude Code configuration. Before it touches anything, it:

- checks the target, and for a replacement the source, are inside those two folders and not reached through a symbolic link
- refuses if either changed since the review screen opened, compared by a hash of every file
- backs the target up

A replacement is copied in beside the target and swapped in by renaming, so a failure part-way puts the original back.

**Undo** puts the backup back, but refuses if:

- something new is where a removed copy was
- a replaced copy was edited after the fix

A running Claude Code session may keep using the old copy until it reloads, as with any other change.

### Uninstalling, plugins and MCP servers

These sit behind the same Settings switch, review screen, backup and undo as fixes (`FixPlanner.change`).

**Uninstall** moves a skill, command or subagent that nothing overrides into the backups, under the same folder and symbolic-link rules as fixes. An overridden copy uses **Remove**, which does the same thing. The review screen says which copy runs once it's gone, if any. It also says when a running session stops seeing it, using the removal rules in [When a running session sees a change](#when-a-running-session-sees-a-change).

**Disable / Enable a plugin** flips its entry in `enabledPlugins`, `"<name>@<marketplace>": true` or `false`, in the settings file that decides it. That's the highest-precedence file that mentions the plugin. Claude Code's own `claude plugin disable` and `enable` change the same setting, and a disabled plugin stays installed. Managed settings are never edited. A plugin with no `enabledPlugins` entry gets the `claude plugin disable` command to copy instead. ([Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins), [plugin disable](https://code.claude.com/docs/en/plugins/cli-reference#plugin-disable), [where a plugin is enabled](https://code.claude.com/docs/en/plugins/loading#find-where-a-plugin-is-enabled))

**Uninstall a plugin** is shown as a command to copy, never run: `claude plugin uninstall <id> --scope <scope>`, with the plugin's install scope. Uninstalling also deletes the plugin's stored options, secrets and data directory when it's the last scope it's installed at. Only Claude Code can do that safely. The ID is shell-quoted, because it comes from files a repository controls. ([plugin uninstall](https://code.claude.com/docs/en/plugins/cli-reference#plugin-uninstall))

**Remove an MCP server** deletes its entry from the file that defines it:

| Scope | File | Entry |
| --- | --- | --- |
| Project | `.mcp.json` at the repository root | `mcpServers.<name>` |
| User | `~/.claude.json` | `mcpServers.<name>` |
| Local | `~/.claude.json` | `projects.<repository path>.mcpServers.<name>` |

Plugin servers are refused, because Claude Code adds and removes them with their plugin. Managed servers are refused too. Strata never starts or contacts a server. ([MCP installation scopes](https://code.claude.com/docs/en/mcp#mcp-installation-scopes), [plugin-provided MCP servers](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers))

Plugin settings and MCP servers live in JSON files that Claude Code also writes, `~/.claude.json` most of all. So `ConfigWriter`:

- edits the entry's text in place (`JSONTextEdit`) and leaves every other byte of the file as it was
- may edit `~/.claude.json` and the repository's `.mcp.json`, as single files outside the two folders, but not if either is a symbolic link
- refuses if the file changed since the review
- backs up the whole file
- writes the new text with one rename, keeping the file's permissions, because `~/.claude.json` is private to its owner

**Undo** reverses only Strata's edit. It puts the removed entry back, or the old value, unless the entry has changed since. Anything Claude Code wrote elsewhere in the file in the meantime is kept.

A plugin change applies after `/reload-plugins` or in a new session. The docs don't say whether a running session picks up an edit to MCP configuration, so Strata says so. ([check which stage a plugin reached](https://code.claude.com/docs/en/plugins/loading#check-which-stage-a-plugin-reached))

### Plugin updates

Strata shows each marketplace plugin's installed version next to the version its marketplace copy on this Mac offers (`PluginUpdates`). It never fetches anything.

- **Installed:** the plugin's manifest `version`, or the version `~/.claude/plugins/installed_plugins.json` records. ([find plugins on disk](https://code.claude.com/docs/en/plugins/loading#find-plugins-on-disk))
- **Offered:**
  - Strata finds the marketplace's copy through `known_marketplaces.json` (`installLocation`, or `~/.claude/plugins/marketplaces/<name>/`) and reads `.claude-plugin/marketplace.json`.
  - Like Claude Code, it takes the plugin's own manifest `version` first, for an entry whose source is a folder in the marketplace, then the entry's `version`. A source path that leaves the marketplace folder isn't read.
  - Without either, Claude Code compares commits, which Strata can't see, so it says so. ([how Claude Code computes the version](https://code.claude.com/docs/en/plugins/loading#how-claude-code-computes-the-version))
- **Comparing:** versions that both parse are compared by Semantic Versioning. Two other strings, such as commit hashes, count as an update when they differ.

Updating stays with Claude Code. **Check for Plugin Updates…** shows, to copy:

- `claude plugin marketplace update`, with the marketplace sources it contacts. It refreshes every marketplace's listing and leaves installed plugins as they are.
- `claude plugin update <id> --scope <scope>` for each plugin with an update. There's no command that updates every plugin at once, so **Copy All** copies one per line.

When the commands change files, Strata rescans. Review Changes then shows what changed: the version, and the plugin's skills, subagents, commands and MCP servers. An update applies after `/reload-plugins` or in a new session. ([plugin update](https://code.claude.com/docs/en/plugins/cli-reference#plugin-update), [update plugins now](https://code.claude.com/docs/en/plugins/install#update-plugins-now))

### Status since the last review

Every item gets a status from its pending change and the problems Strata reports for it now (`SyncStatus`):

| Status | When |
| --- | --- |
| Unchanged | Nothing about the item changed on disk since the last review |
| Changed | Changed, and the docs say a running session picks it up by itself (live, or when it's next used) |
| Reload needed / New session | Changed, and a running session needs `/reload-skills`, `/reload-plugins` or a new session first |
| Conflict | Changed, and Strata reports a conflict or warning for it now. This takes priority over the others |
| Unverified | Changed, and the docs don't say when a running session sees it |

Strata can't see inside a running Claude Code session, so no status says a session is up to date. "Update available" and "update failed" need Strata to write configuration, so they come with approved updates (#30).

**Copy Prompt for Claude Code** turns a change into a message for the session you have open (`UpdatePrompt`). It covers:

- what changed, where, its scope and the repositories it reaches
- the diff, up to 60 lines, built from the masked copies and checked once more for token-shaped text
- conflicts
- when Claude Code sees the change
- steps that fit the kind of item: use the current skill and read it back, list the server's tools, re-read the instruction file, stop using a removed plugin

When the session won't pick the change up by itself, the sheet says what to run first (`/reload-skills`, `/reload-plugins`, or a new session). The prompt only goes to the clipboard; Strata never sends it.

Security notes restate what the Claude Code docs say the changed field does:

| Change | Note | Source |
| --- | --- | --- |
| New or edited MCP server | A new stdio server runs its command when it starts, and a remote one connects to its URL. Command, argument, URL, environment and header edits are each named. Project `.mcp.json` servers ask before first use | [MCP](https://code.claude.com/docs/en/mcp) |
| `hooks` setting, or `hooks` in a skill or subagent's frontmatter | Hooks run shell commands automatically, with Claude Code's environment | [Hooks](https://code.claude.com/docs/en/hooks) |
| `permissions` setting | Changes what Claude Code may do without asking. A `defaultMode` of `bypassPermissions` skips every prompt. Claude Code 2.1.257 and later ignore that value in project and local settings | [Permissions](https://code.claude.com/docs/en/permissions), [Settings](https://code.claude.com/docs/en/settings#a-value-you-set-is-ignored) |
| `apiKeyHelper` setting | A credential helper Claude Code runs | [Settings](https://code.claude.com/docs/en/settings#when-edits-take-effect) |
| New plugin, or one turned on | Plugins can add skills, subagents, hooks and MCP servers | [Plugins](https://code.claude.com/docs/en/plugins) |
| `allowed-tools` in a skill or command | Grants the listed tools without asking during the turn that invokes it. A project skill's grant applies even in a folder that isn't trusted | [Skills](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill) |
| `tools` or `permissionMode` in a subagent | `tools` restricts which tools it can use; `permissionMode` changes how it asks | [Subagents](https://code.claude.com/docs/en/sub-agents#restrict-which-tools-a-subagent-can-use) |

## Not covered in v0.1

- Anything passed on the command line: `--settings`, `--agents`, `--add-dir`, `--plugin-dir`, `--mcp-config`
- Environment variables, including `CLAUDE_CONFIG_DIR` when the app isn't launched from a shell that sets it
- Server-managed settings delivered from the claude.ai console, and MDM profiles
- claude.ai connectors
- Output styles, workflows, keybindings and themes
- Whether a workspace is trusted, which lives in `~/.claude.json` in an undocumented form
