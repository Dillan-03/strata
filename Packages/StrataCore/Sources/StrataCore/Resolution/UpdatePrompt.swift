import Foundation

/// A message to paste into a running Claude Code session so it knows about a configuration change: what changed,
/// where, what it reaches, conflicts, and what to do to confirm it has the new version.
///
/// Strata never sends it. The content is already masked, and the finished text is checked once more for anything
/// token-shaped before it's handed over.
public enum UpdatePrompt {
    /// Diff lines included before the rest is left to the file.
    static let diffLineLimit = 60

    public static func make(
        for change: ConfigChange,
        impacts: [RepositoryImpact] = [],
        conflicts: [Diagnostic] = [],
        homePath: String
    ) -> String {
        let display = { (path: String) in abbreviate(path, homePath: homePath) }
        let item = change.item
        var lines = [
            "My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:",
            "",
            "\(subject(item)) was \(verb(change.kind)).",
        ]

        if change.kind == .renamed, let previous = change.previous {
            lines.append("- Moved from: \(display(previous.source.path))")
            lines.append("- Now at: \(location(item, display))")
        } else {
            lines.append("- \(change.kind == .deleted ? "Was in" : "File"): \(location(item, display))")
        }
        lines.append("- Scope: \(scope(change))")
        lines += reach(impacts, display)

        let details = diffLines(ConfigDiff(change), for: change)
        if !details.isEmpty {
            lines.append("")
            lines += details
        }

        let problems = conflicts.filter { $0.severity != .info }
        if !problems.isEmpty {
            lines.append("")
            lines.append("Conflicts Strata found:")
            lines += problems.map { "- \($0.title): \($0.detail)" }
        }

        lines.append("")
        lines.append("When Claude Code sees it: \(change.pickup.explanation)")
        lines.append("")
        lines.append("Please:")
        lines += steps(change, display).enumerated().map { "\($0.offset + 1). \($0.element)" }

        return SecretRedactor.redactText(lines.joined(separator: "\n"))
    }

    /// What the user should do before pasting, when the running session won't see the change by itself.
    public static func beforePasting(_ change: ConfigChange) -> String? {
        switch change.pickup.timing {
        case .reloadSkills: "Run /reload-skills in Claude Code first, then paste this."
        case .reloadPlugins: "Run /reload-plugins in Claude Code first, then paste this."
        case .nextSession: "A new session picks this up fully. Pasting this tells the session you have open about it."
        case .unknown: "Claude Code's docs don't say when this applies. A new session is the sure way; pasting this tells the open one."
        case .live, .onDemand: nil
        }
    }

    // MARK: - Pieces

    private static func subject(_ item: ConfigItem) -> String {
        let name = "`\(item.invocation ?? item.name)`"
        let scope = item.scope.title.lowercased()
        switch item.kind {
        case .skill: return "The \(scope) skill \(name)"
        case .command: return "The \(scope) command \(name)"
        case .agent: return "The \(scope) subagent \(name)"
        case .mcpServer: return "The \(scope) MCP server \(name)"
        case .plugin: return "The plugin \(name)"
        case .instruction: return "The \(scope) instruction file \(name)"
        case .setting: return "The \(scope) setting \(name)"
        }
    }

    private static func verb(_ kind: ConfigChange.Kind) -> String {
        switch kind {
        case .created: "added"
        case .updated: "edited"
        case .deleted: "removed"
        case .renamed: "moved"
        }
    }

    private static func location(_ item: ConfigItem, _ display: (String) -> String) -> String {
        display(item.source.path) + (item.source.keyPath.map { ", under `\($0)`" } ?? "")
    }

    private static func scope(_ change: ConfigChange) -> String {
        switch change.reach {
        case .global: "global, so it applies in every repository"
        case .shared: "a parent folder, so it applies in every repository under it"
        case .repository: "this repository only"
        }
    }

    private static func reach(_ impacts: [RepositoryImpact], _ display: (String) -> String) -> [String] {
        var lines: [String] = []
        let applies = impacts.filter { $0.effect == .affected }.map { display($0.repositoryPath) }
        let maybe = impacts.filter { $0.effect == .possiblyAffected }.map { display($0.repositoryPath) }
        if !applies.isEmpty { lines.append("- Takes effect in: \(applies.joined(separator: ", "))") }
        if !maybe.isEmpty { lines.append("- May take effect in: \(maybe.joined(separator: ", ")) (only under a condition)") }
        for impact in impacts {
            if case .shadowed(let winner) = impact.effect {
                lines.append("- No effect in \(display(impact.repositoryPath)): the \(winner.scope.title.lowercased()) copy wins there")
            }
        }
        return lines
    }

    /// Fields of Strata's own plugin record that say where it read things from, not what the plugin is.
    private static let pluginBookkeeping: Set<String> = ["decidedBy", "root"]

    private static func diffLines(_ diff: ConfigDiff, for change: ConfigChange) -> [String] {
        if change.item.kind == .plugin, change.kind == .created || change.kind == .deleted { return [] }
        switch diff {
        case .text(let text):
            guard !text.hunks.isEmpty else { return ["The content didn't change."] }
            var body: [String] = []
            for hunk in text.hunks {
                if hunk.skippedBefore > 0 { body.append("@@ \(hunk.skippedBefore) unchanged lines @@") }
                body += hunk.lines.map { line in
                    switch line.kind {
                    case .added: "+" + line.text
                    case .removed: "-" + line.text
                    case .unchanged: " " + line.text
                    }
                }
            }
            var header = "What changed (+\(text.addedCount) −\(text.removedCount) lines):"
            if body.count > diffLineLimit {
                header = "What changed (+\(text.addedCount) −\(text.removedCount) lines, first \(diffLineLimit) shown):"
                body = Array(body.prefix(diffLineLimit)) + ["@@ \(body.count - diffLineLimit) more lines: read the file for the rest @@"]
            }
            return [header, "```diff"] + body + ["```"]
        case .keyed(let keys):
            let changed = keys.filter { key in
                key.kind != .unchanged && !(change.item.kind == .plugin && pluginBookkeeping.contains(key.path))
            }
            guard !changed.isEmpty else { return ["The values didn't change."] }
            let lines = changed.map { key -> String in
                let path = key.path.isEmpty ? "value" : "`\(key.path)`"
                switch key.kind {
                case .added: return "- \(path) added: \(key.after ?? "")"
                case .removed: return "- \(path) removed (was \(key.before ?? ""))"
                case .changed where key.changedBehindMask: return "- \(path) changed (the value is masked)"
                default: return "- \(path) changed from \(key.before ?? "") to \(key.after ?? "")"
                }
            }
            let masked = keys.contains { ($0.before ?? "").contains(SecretRedactor.mask) || ($0.after ?? "").contains(SecretRedactor.mask) }
            return ["What changed:"] + lines + (masked ? ["(\(SecretRedactor.mask) marks values Strata masked.)"] : [])
        case .unavailable:
            return []
        }
    }

    private static func steps(_ change: ConfigChange, _ display: (String) -> String) -> [String] {
        let item = change.item
        let name = "`\(item.invocation ?? item.name)`"
        let file = display(item.source.path)
        let confirm = "Read \(file) and tell me in a sentence or two what it now says, so I know you have the new version."

        if change.kind == .deleted {
            switch item.kind {
            case .skill, .command: return ["Stop using \(name): it no longer exists. Tell me if anything we're doing relied on it."]
            case .agent: return ["Don't delegate to the \(name) subagent any more: it no longer exists."]
            case .mcpServer: return ["Don't use tools from the \(name) server any more. Tell me if anything we're doing relied on them."]
            case .plugin: return ["Stop using skills, subagents or tools from the \(name) plugin. Tell me if anything we're doing relied on them."]
            case .instruction: return ["Stop following the instructions that came from \(file): that file is gone."]
            case .setting: return ["Take this into account for the rest of the session, and tell me if it affects what we're doing."]
            }
        }

        switch item.kind {
        case .skill, .command:
            return ["Use the current \(name), not the version you saw earlier in this session.", confirm]
        case .agent:
            return ["Use the current definition of the \(name) subagent when you delegate to it.", confirm]
        case .mcpServer:
            return [
                "Check whether tools from the \(name) server are available to you, and list them.",
                "If they aren't, say so; I'll check the connection with /mcp.",
            ]
        case .plugin:
            return ["Tell me which skills, subagents or MCP tools from the \(name) plugin you can use now."]
        case .instruction:
            return ["Read \(file) again and follow it for the rest of this session.", "Summarise what changed in a sentence or two."]
        case .setting:
            return ["Take this into account for the rest of the session, and tell me if it affects what we're doing."]
        }
    }

    static func abbreviate(_ path: String, homePath: String) -> String {
        guard !homePath.isEmpty, path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }
}
