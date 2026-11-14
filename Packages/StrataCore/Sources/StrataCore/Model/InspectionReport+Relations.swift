import Foundation

/// How items in a report relate to each other, for the per-kind inspector sections.
extension InspectionReport {
    /// Every definition competing for the same name, best first. Skills and commands share one namespace.
    public func definitions(competingWith item: ConfigItem) -> [ConfigItem] {
        let kinds: Set<ItemKind> = item.kind == .skill || item.kind == .command ? [.skill, .command] : [item.kind]
        return items
            .filter { kinds.contains($0.kind) && $0.name == item.name }
            .sorted { ($0.precedenceRank ?? .max, $0.id) < ($1.precedenceRank ?? .max, $1.id) }
    }

    /// Items a plugin contributes: its skills, commands, subagents and MCP servers.
    public func components(ofPlugin plugin: ConfigItem) -> [ConfigItem] {
        guard plugin.kind == .plugin else { return [] }
        return items.filter { $0.scope == .plugin && $0.origin == plugin.name }
    }

    /// The plugin an item came from, when it came from one.
    public func plugin(providing item: ConfigItem) -> ConfigItem? {
        guard item.scope == .plugin, let origin = item.origin else { return nil }
        return items.first { $0.kind == .plugin && $0.name == origin }
    }

    /// Files an instruction file imports directly.
    public func imports(of instruction: ConfigItem) -> [ConfigItem] {
        guard instruction.kind == .instruction else { return [] }
        return items.filter { $0.kind == .instruction && $0.metadataValue("Imported by") == instruction.name && $0.scope == instruction.scope }
    }

    /// Instruction files read at session start, in the order Claude Code reads them.
    public var launchInstructions: [ConfigItem] {
        items
            .filter { $0.kind == .instruction && $0.loadTiming == .atLaunch && $0.applicability.isApplied }
            .sorted { ($0.loadOrder ?? 0) < ($1.loadOrder ?? 0) }
    }

    /// Items that this item overrides.
    public func items(shadowedBy item: ConfigItem) -> [ConfigItem] {
        items.filter { other in
            if case .shadowed(let winner) = other.applicability { return winner == item.id }
            return false
        }
    }
}
