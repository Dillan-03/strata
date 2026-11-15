import Foundation

/// Compares two scans of one repository and reports what was added, edited, removed or moved.
///
/// An edit is a change to an item's fingerprint, the hash of its file or JSON entry. A change in an item's status
/// caused by a different item (a new repo skill overriding a global one) isn't an edit of that item; the edit that
/// caused it is reported on its own.
public enum ChangeDetector {
    /// Kinds whose definitions are whole files or self-contained entries, so equal content in a new place is a move.
    /// Settings and plugins are excluded: two unrelated keys can easily hold the same value.
    static let movableKinds: Set<ItemKind> = [.skill, .command, .agent, .instruction, .mcpServer]

    public static func changes(from old: InspectionReport, to new: InspectionReport) -> [ConfigChange] {
        let before = Dictionary(old.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var changes: [ConfigChange] = []
        var created = new.items.filter { before[$0.id] == nil }
        var deleted = old.items.filter { after[$0.id] == nil }

        for item in new.items {
            guard let was = before[item.id], was.fingerprint != item.fingerprint else { continue }
            changes.append(ConfigChange(
                kind: .updated, item: item, previous: was,
                before: old.contents[was.id], after: new.contents[item.id],
                pickup: pickup(.updated, item, old: old)
            ))
        }

        for item in created where movableKinds.contains(item.kind) && item.fingerprint != nil {
            guard let index = deleted.firstIndex(where: { $0.kind == item.kind && $0.fingerprint == item.fingerprint }) else { continue }
            let was = deleted.remove(at: index)
            changes.append(ConfigChange(
                kind: .renamed, item: item, previous: was,
                before: old.contents[was.id], after: new.contents[item.id],
                pickup: pickup(.renamed, item, old: old)
            ))
        }
        let moved = Set(changes.filter { $0.kind == .renamed }.map(\.item.id))
        created.removeAll { moved.contains($0.id) }

        changes += created.map { ConfigChange(kind: .created, item: $0, after: new.contents[$0.id], pickup: pickup(.created, $0, old: old)) }
        changes += deleted.map { ConfigChange(kind: .deleted, item: $0, before: old.contents[$0.id], pickup: pickup(.deleted, $0, old: old)) }

        return changes.sorted {
            ($0.reach.order, $0.item.kind.order, $0.item.name, $0.kind.rawValue) < ($1.reach.order, $1.item.kind.order, $1.item.name, $1.kind.rawValue)
        }
    }

    // MARK: - When a running session sees it

    private enum Docs {
        static let skills = "https://code.claude.com/docs/en/skills#edit-a-skill-during-a-session"
        static let agents = "https://code.claude.com/docs/en/sub-agents#write-subagent-files"
        static let settings = "https://code.claude.com/docs/en/settings#when-edits-take-effect"
        static let plugins = "https://code.claude.com/docs/en/plugins/install#keep-plugins-updated"
        static let mcp = "https://code.claude.com/docs/en/mcp"
        static let memory = "https://code.claude.com/docs/en/memory"
    }

    /// Settings Claude Code reads once, at session start.
    static let startupOnlySettings: Set<String> = ["model", "effortLevel", "modelSettings"]

    static func pickup(_ kind: ConfigChange.Kind, _ item: ConfigItem, old: InspectionReport) -> SessionPickup {
        switch item.kind {
        case .skill:
            if item.scope == .plugin {
                return SessionPickup(.reloadPlugins, "Plugin skills change with their plugin. Run /reload-plugins, or start a new session.", source: Docs.plugins)
            }
            guard [.user, .project].contains(item.scope) else {
                return SessionPickup(.unknown, "The Claude Code docs only describe live updates for ~/.claude/skills and the project's .claude/skills.", source: Docs.skills)
            }
            if kind == .created, isFirst(item, in: skillsRoot, old: old) {
                return SessionPickup(
                    .reloadSkills,
                    "Claude Code only watches skills folders that existed when the session started. If this folder is new, run /reload-skills.",
                    source: Docs.skills
                )
            }
            return SessionPickup(.live, "Claude Code watches skills folders and picks up added, edited and removed skills without a restart.", source: Docs.skills)

        case .command:
            return SessionPickup(.unknown, "The Claude Code docs don't say whether a running session picks up changes to .claude/commands.", source: Docs.skills)

        case .agent:
            if item.scope == .plugin {
                return SessionPickup(.reloadPlugins, "Plugin subagents change with their plugin. Run /reload-plugins, or start a new session.", source: Docs.plugins)
            }
            guard [.user, .project].contains(item.scope) else {
                return SessionPickup(.unknown, "The Claude Code docs only describe live updates for ~/.claude/agents and the project's .claude/agents.", source: Docs.agents)
            }
            if kind == .created, isFirst(item, in: agentsRoot, old: old) {
                return SessionPickup(
                    .nextSession,
                    "Claude Code only watches agents folders that existed when the session started. If this folder is new, restart to load it.",
                    source: Docs.agents
                )
            }
            return SessionPickup(.live, "Claude Code detects subagent changes within a few seconds; the next delegation uses them.", source: Docs.agents)

        case .setting:
            if item.name == "enabledPlugins" {
                return SessionPickup(.reloadPlugins, "Turning plugins on or off applies after /reload-plugins, or in a new session.", source: Docs.plugins)
            }
            if startupOnlySettings.contains(item.name) {
                return SessionPickup(.nextSession, "Claude Code reads \(item.name) only at session start. /model or /effort change it in a running session.", source: Docs.settings)
            }
            return SessionPickup(.live, "Claude Code reloads settings files when they change, including permissions and hooks.", source: Docs.settings)

        case .plugin:
            return SessionPickup(.reloadPlugins, "Plugin changes apply after /reload-plugins, or in a new session.", source: Docs.plugins)

        case .mcpServer:
            if item.scope == .plugin {
                return SessionPickup(.reloadPlugins, "A plugin's MCP servers connect or disconnect when plugin changes apply, after /reload-plugins.", source: Docs.mcp)
            }
            return SessionPickup(
                .unknown,
                "The Claude Code docs don't say whether a running session picks up edits to MCP configuration. A new session is the safe choice.",
                source: Docs.mcp
            )

        case .instruction:
            switch item.loadTiming {
            case .atLaunch:
                return SessionPickup(.nextSession, "Loaded at session start. The project-root CLAUDE.md is also re-read after /compact.", source: Docs.memory)
            case .onDemand, .pathGated:
                return SessionPickup(.onDemand, "Loads the next time Claude works in that folder or touches a matching file.", source: Docs.memory)
            case .whenInvoked, .unknown:
                return SessionPickup(.unknown, "The Claude Code docs don't say when this instruction file is re-read.", source: Docs.memory)
            }
        }
    }

    /// The `skills` folder a skill lives in: `…/skills/<name>/SKILL.md` → `…/skills`.
    static func skillsRoot(_ item: ConfigItem) -> String {
        item.source.url.deletingLastPathComponent().deletingLastPathComponent().path
    }

    /// The `agents` folder a subagent lives in.
    static func agentsRoot(_ item: ConfigItem) -> String {
        item.source.url.deletingLastPathComponent().path
    }

    /// True when the previous scan had nothing of this kind in the item's folder, so the folder may be new.
    private static func isFirst(_ item: ConfigItem, in root: (ConfigItem) -> String, old: InspectionReport) -> Bool {
        let folder = root(item)
        return !old.items.contains { $0.kind == item.kind && root($0) == folder }
    }
}

private extension ConfigChange.Reach {
    var order: Int {
        switch self {
        case .global: 0
        case .shared: 1
        case .repository: 2
        }
    }
}

private extension ItemKind {
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
