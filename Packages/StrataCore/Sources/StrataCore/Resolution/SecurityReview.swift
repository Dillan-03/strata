import Foundation

/// Something in a change that can widen what Claude Code runs or may do without asking.
public struct SecurityNote: Hashable, Sendable, Identifiable {
    public enum Level: Hashable, Sendable {
        /// Worth checking before you rely on the change.
        case caution
        /// Context, not a risk on its own.
        case info
    }

    public let level: Level
    public let text: String
    /// The Claude Code docs page the claim comes from.
    public let source: URL?

    public var id: String { text }

    init(_ level: Level, _ text: String, source: String? = nil) {
        self.level = level
        self.text = text
        self.source = source.flatMap(URL.init(string:))
    }
}

/// Security notes for a configuration change. Each note restates what the Claude Code docs say the changed field does.
public enum SecurityReview {
    private enum Docs {
        static let hooks = "https://code.claude.com/docs/en/hooks"
        static let permissions = "https://code.claude.com/docs/en/permissions"
        static let settings = "https://code.claude.com/docs/en/settings"
        static let skillTools = "https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill"
        static let agentTools = "https://code.claude.com/docs/en/sub-agents#restrict-which-tools-a-subagent-can-use"
        static let mcp = "https://code.claude.com/docs/en/mcp"
        static let plugins = "https://code.claude.com/docs/en/plugins"
    }

    public static func notes(for change: ConfigChange) -> [SecurityNote] {
        var notes: [SecurityNote] = []
        let diff = ConfigDiff(change)

        switch change.item.kind {
        case .mcpServer where change.kind != .deleted:
            notes += serverNotes(change, diff: diff)
        case .setting:
            notes += settingNotes(change, diff: diff)
        case .plugin where change.kind != .deleted:
            if change.kind == .created || changedPaths(diff).contains("enabled") {
                notes.append(SecurityNote(
                    .caution,
                    "Plugins can add skills, subagents, hooks and MCP servers. The inspector lists what this one contributes.",
                    source: Docs.plugins
                ))
            }
        case .skill, .command, .agent:
            notes += frontmatterNotes(change)
        case .permission where change.kind != .deleted && ["Allow", "Additional directory"].contains(change.item.metadataValue("List") ?? ""):
            notes.append(SecurityNote(
                .caution,
                change.item.metadataValue("List") == "Allow"
                    ? "The allow rule \(change.item.name) lets matching calls run without asking. Check it's as narrow as you mean."
                    : "This gives Claude read and edit access to \(change.item.name).",
                source: Docs.permissions
            ))
        case .hook where change.kind != .deleted:
            notes.append(SecurityNote(
                .caution,
                "This hook runs automatically on \(change.item.metadataValue("Event") ?? "an event"), with Claude Code's environment: "
                    + "\(change.item.summary ?? "check what it runs").",
                source: Docs.hooks
            ))
        default:
            break
        }

        if change.after?.hasMaskedValues == true || change.before?.hasMaskedValues == true {
            notes.append(SecurityNote(.info, "Values that look like secrets are masked here. Open the file to see them."))
        }
        return notes
    }

    // MARK: - MCP servers

    private static func serverNotes(_ change: ConfigChange, diff: ConfigDiff) -> [SecurityNote] {
        var notes: [SecurityNote] = []
        let paths = changedPaths(diff)
        if change.kind == .created {
            if let command = change.item.metadataValue("Command") {
                notes.append(SecurityNote(.caution, "Claude Code runs `\(command)` on this Mac when it starts this server.", source: Docs.mcp))
            } else if let url = change.item.metadataValue("URL") {
                notes.append(SecurityNote(.caution, "Claude Code connects to \(url) when it starts this server.", source: Docs.mcp))
            }
            if change.item.scope == .project {
                notes.append(SecurityNote(.info, "Claude Code asks before it first uses a server from the project's .mcp.json.", source: Docs.mcp))
            }
        } else {
            if paths.contains(where: { $0 == "command" || $0 == "args" }) {
                notes.append(SecurityNote(.caution, "The command this server runs changed.", source: Docs.mcp))
            }
            if paths.contains("url") {
                notes.append(SecurityNote(.caution, "The address this server connects to changed.", source: Docs.mcp))
            }
            if paths.contains(where: { $0.hasPrefix("env.") || $0.hasPrefix("headers.") || $0 == "headersHelper" }) {
                notes.append(SecurityNote(.info, "Its environment variables or headers changed.", source: Docs.mcp))
            }
        }
        return notes
    }

    // MARK: - Settings

    private static func settingNotes(_ change: ConfigChange, diff: ConfigDiff) -> [SecurityNote] {
        var notes: [SecurityNote] = []
        let adding = change.kind != .deleted
        switch change.item.name {
        case "hooks" where adding:
            notes.append(SecurityNote(
                .caution,
                "Hooks run shell commands automatically at points in Claude Code's lifecycle, with Claude Code's environment. Check every command.",
                source: Docs.hooks
            ))
        case "permissions":
            notes.append(SecurityNote(.caution, "Changes what Claude Code may do without asking you first.", source: Docs.permissions))
            if case .keyed(let keys) = diff, keys.contains(where: { $0.path == "permissions.defaultMode" && $0.after == "bypassPermissions" && $0.kind != .unchanged }) {
                if [.project, .local].contains(change.item.scope) {
                    notes.append(SecurityNote(
                        .caution,
                        "bypassPermissions in a repository file: Claude Code 2.1.257 and later ignore it here; earlier versions skip every permission prompt.",
                        source: Docs.settings
                    ))
                } else {
                    notes.append(SecurityNote(.caution, "bypassPermissions skips every permission prompt.", source: Docs.permissions))
                }
            }
        case "apiKeyHelper" where adding:
            notes.append(SecurityNote(.caution, "apiKeyHelper is a credential helper: a command Claude Code runs to get an API key.", source: Docs.settings))
        case "enabledPlugins" where adding:
            notes.append(SecurityNote(.info, "Turning a plugin on can add skills, subagents, hooks and MCP servers.", source: Docs.plugins))
        default:
            break
        }
        return notes
    }

    // MARK: - Frontmatter

    private static func frontmatterNotes(_ change: ConfigChange) -> [SecurityNote] {
        guard change.kind != .deleted else { return [] }
        let old = frontmatter(change.before)
        let new = frontmatter(change.after)
        func changed(_ key: String) -> Bool { new?[key] != nil && old?[key] != new?[key] }

        var notes: [SecurityNote] = []
        if change.item.kind != .agent, changed("allowed-tools") {
            let untrusted = change.item.scope == .project ? " Claude Code applies it even in a folder you haven't trusted." : ""
            notes.append(SecurityNote(
                .caution,
                "allowed-tools lets Claude use the listed tools without asking during the turn that invokes it.\(untrusted)",
                source: Docs.skillTools
            ))
        }
        if change.item.kind == .agent, changed("tools") {
            notes.append(SecurityNote(.info, "Changes which tools this subagent can use.", source: Docs.agentTools))
        }
        if change.item.kind == .agent, changed("permissionMode") {
            notes.append(SecurityNote(.caution, "Changes how this subagent asks for permission.", source: Docs.agentTools))
        }
        if changed("hooks") {
            notes.append(SecurityNote(.caution, "Hooks in this file run automatically, with Claude Code's environment. Check every command.", source: Docs.hooks))
        }
        return notes
    }

    private static func frontmatter(_ content: ItemContent?) -> Frontmatter? {
        guard case .text(let text)? = content else { return nil }
        return (try? Frontmatter.parse(document: text))?.frontmatter
    }

    private static func changedPaths(_ diff: ConfigDiff) -> [String] {
        guard case .keyed(let keys) = diff else { return [] }
        return keys.filter { $0.kind != .unchanged }.map(\.path)
    }
}
