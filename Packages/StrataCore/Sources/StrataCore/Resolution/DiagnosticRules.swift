import Foundation

/// Diagnostics that need the resolved picture: overrides, ambiguous duplicates and endpoint clashes.
/// Scan-time problems (broken JSON, files that won't load, missing imports) are reported by the scanners.
struct DiagnosticRules {
    let displayPath: (String) -> String

    func diagnose(_ items: [ConfigItem]) -> [Diagnostic] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var diagnostics: [Diagnostic] = []

        for item in items {
            guard case .shadowed(let winnerID) = item.applicability, let winner = byID[winnerID] else { continue }
            switch item.kind {
            case .skill, .command, .agent:
                diagnostics.append(shadowed(item, by: winner))
            case .mcpServer where item.scope == .plugin:
                diagnostics.append(Diagnostic(
                    severity: .info,
                    code: .duplicateMCPEndpoint,
                    title: "\(item.origin ?? "A plugin")'s \(item.name) points at the same endpoint as \(winner.name)",
                    detail: "Claude Code connects to that endpoint once, using your \(winner.scope.title.lowercased()) definition.",
                    paths: [item.source.path, winner.source.path],
                    itemIDs: [item.id, winner.id]
                ))
            default:
                break
            }
        }

        diagnostics += ambiguousAgents(items)
        diagnostics += conflictingServers(items)
        diagnostics += missingPlugins(items)
        diagnostics += linkedSkills(items)
        return diagnostics
    }

    private func shadowed(_ item: ConfigItem, by winner: ConfigItem) -> Diagnostic {
        let noun = item.kind == .agent ? "subagent" : item.kind == .command ? "command" : "skill"
        let title = "\(winner.scope.title) \(winner.kind == .command ? "command" : noun) \(winner.name) hides the \(item.scope.title.lowercased()) copy"
        return Diagnostic(
            severity: .warning,
            code: .shadowedDefinition,
            title: title,
            detail: item.explanation.first ?? "Another definition with the same name wins.",
            suggestion: "Rename one of them, or delete the copy you don't want. Editing \(displayPath(item.source.path)) has no effect while the other exists.",
            paths: [winner.source.path, item.source.path],
            itemIDs: [winner.id, item.id]
        )
    }

    private func ambiguousAgents(_ items: [ConfigItem]) -> [Diagnostic] {
        let ties = items.filter { $0.kind == .agent && $0.applicability == .unknown && $0.loadBlocker == nil }
        return Dictionary(grouping: ties) { "\($0.scope.rawValue)|\($0.name)" }.values.compactMap { group in
            guard group.count > 1, let first = group.first else { return nil }
            return Diagnostic(
                severity: .conflict,
                code: .duplicateNameInDirectory,
                title: "\(group.count) \(first.scope.title.lowercased()) subagents are named \(first.name)",
                detail: "Claude Code loads only one of them, chosen by filesystem order rather than a documented rule.",
                suggestion: "Give each a unique `name`. `/doctor` in Claude Code reports the same problem.",
                paths: group.map(\.source.path).sorted(),
                itemIDs: group.map(\.id).sorted()
            )
        }
    }

    /// Same server name in more than one scope with different endpoints: Claude Code warns about this in `claude mcp list`.
    private func conflictingServers(_ items: [ConfigItem]) -> [Diagnostic] {
        let servers = items.filter { $0.kind == .mcpServer && $0.scope != .plugin && $0.loadBlocker == nil }
        return Dictionary(grouping: servers, by: \.name).values.compactMap { group in
            let endpoints = Set(group.compactMap(\.matchKey))
            guard group.count > 1, endpoints.count > 1, let name = group.first?.name else { return nil }
            let scopes = group.map { $0.scope.title.lowercased() }.sorted().joined(separator: ", ")
            return Diagnostic(
                severity: .warning,
                code: .conflictingMCPEndpoints,
                title: "MCP server \(name) is defined differently in \(group.count) scopes",
                detail: "The \(scopes) definitions point at different endpoints. Only the highest-precedence one connects here, "
                    + "and OAuth sign-ins are stored per endpoint, so other projects may use a different server under the same name.",
                suggestion: "Keep the endpoint you want and remove the others with `claude mcp remove \(name) --scope <scope>`.",
                paths: group.map(\.source.path).sorted(),
                itemIDs: group.map(\.id).sorted()
            )
        }
    }

    private func missingPlugins(_ items: [ConfigItem]) -> [Diagnostic] {
        items.filter { $0.kind == .plugin && $0.stage == .declared && $0.metadataValue("Decided by") != nil }.map { plugin in
            Diagnostic(
                severity: .warning,
                code: .pluginEnabledButNotInstalled,
                title: "\(plugin.name) is enabled but not installed",
                detail: "\(plugin.metadataValue("Decided by") ?? "A settings file") turns it on, but it isn't on this Mac. "
                    + "Committing an `enabledPlugins` entry doesn't download the plugin for collaborators.",
                suggestion: "Run `claude plugin install \(plugin.name)`.",
                paths: [plugin.source.path],
                itemIDs: [plugin.id]
            )
        }
    }

    /// Symlinked skill folders pointing at the same target load once.
    private func linkedSkills(_ items: [ConfigItem]) -> [Diagnostic] {
        let skills = items.filter { $0.kind == .skill && $0.matchKey != nil }
        return Dictionary(grouping: skills) { $0.matchKey ?? "" }.values.compactMap { group in
            guard group.count > 1, Set(group.map(\.scope)).count > 1, let first = group.first else { return nil }
            return Diagnostic(
                severity: .info,
                code: .symlinkDuplicate,
                title: "\(first.name) is linked from \(group.count) places",
                detail: "These skill folders point at the same files, so Claude Code loads the skill once.",
                paths: group.map(\.source.path).sorted(),
                itemIDs: group.map(\.id).sorted()
            )
        }
    }
}
