import Foundation

/// Applies Claude Code's documented precedence rules to discovered items.
///
/// Every rule here is written up, with links to the official docs, in docs/configuration-resolution.md. Where the docs
/// are silent, the item is marked `.unknown` with an explanation rather than guessed.
struct Resolver {
    let displayPath: (String) -> String

    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        var items = items
        for index in items.indices {
            if let blocker = items[index].loadBlocker {
                items[index].applicability = .invalid
                items[index].explanation = [blocker]
            } else if let reason = items[index].inactiveReason {
                items[index].applicability = .inactive
                items[index].explanation = [reason]
            }
        }

        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        func update(_ item: ConfigItem) { byID[item.id] = item }

        SkillRules(displayPath: displayPath).resolve(items.filter { $0.kind == .skill || $0.kind == .command }).forEach(update)
        AgentRules(displayPath: displayPath).resolve(items.filter { $0.kind == .agent }).forEach(update)
        MCPRules(displayPath: displayPath).resolve(items.filter { $0.kind == .mcpServer }).forEach(update)
        PluginRules().resolve(items.filter { $0.kind == .plugin }).forEach(update)
        HookRules().resolve(items.filter { $0.kind == .hook }).forEach(update)
        InstructionRules().resolve(items.filter { $0.kind == .instruction }).forEach(update)
        SettingRules(displayPath: displayPath).resolve(items.filter { $0.kind == .setting }).forEach(update)

        return items.compactMap { byID[$0.id] }.sorted(by: Self.order)
    }

    static func order(_ lhs: ConfigItem, _ rhs: ConfigItem) -> Bool {
        let kinds = ItemKind.allCases
        if lhs.kind != rhs.kind {
            return (kinds.firstIndex(of: lhs.kind) ?? 0) < (kinds.firstIndex(of: rhs.kind) ?? 0)
        }
        if lhs.kind == .instruction, let left = lhs.loadOrder, let right = rhs.loadOrder, left != right {
            return left < right
        }
        if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if lhs.precedenceRank != rhs.precedenceRank {
            return (lhs.precedenceRank ?? .max) < (rhs.precedenceRank ?? .max)
        }
        return lhs.id < rhs.id
    }
}

/// Shared helpers for name-based precedence.
private enum Precedence {
    /// True when nothing has already ruled the item out.
    static func isCandidate(_ item: ConfigItem) -> Bool {
        item.loadBlocker == nil && item.inactiveReason == nil
    }

    /// Marks a group that shares a name, ranking by `rank` (lower wins). Returns the winner when one exists.
    static func rankGroup(
        _ group: [ConfigItem],
        rank: (ConfigItem) -> Int?,
        winner: (inout ConfigItem, [ConfigItem]) -> Void,
        loser: (inout ConfigItem, ConfigItem) -> Void,
        tie: (inout ConfigItem, [ConfigItem]) -> Void
    ) -> [ConfigItem] {
        let ranked = group.filter { isCandidate($0) && rank($0) != nil }.sorted { (rank($0) ?? .max, $0.id) < (rank($1) ?? .max, $1.id) }
        guard let top = ranked.first, let topRank = rank(top) else { return group }
        let tied = ranked.filter { rank($0) == topRank }
        var results: [ConfigItem] = []
        for var item in group {
            guard isCandidate(item), let itemRank = rank(item) else {
                results.append(item)
                continue
            }
            item.precedenceRank = (ranked.firstIndex { $0.id == item.id } ?? 0) + 1
            if tied.count > 1, itemRank == topRank {
                tie(&item, tied)
            } else if item.id == top.id {
                winner(&item, ranked.filter { $0.id != item.id })
            } else {
                loser(&item, top)
            }
            results.append(item)
        }
        return results
    }

    static func applyCondition(_ item: inout ConfigItem) {
        if let condition = item.condition {
            item.applicability = .conditional
            item.explanation.append(condition)
        }
    }
}

// MARK: - Skills and commands

private struct SkillRules {
    let displayPath: (String) -> String

    /// Enterprise over personal, personal over project; a skill beats a command of the same name.
    private func rank(_ item: ConfigItem) -> Int? {
        let base: Int
        switch item.scope {
        case .managed: base = 1
        case .user: base = 2
        case .project: base = 3
        default: return nil
        }
        return item.kind == .skill ? base : base + 10
    }

    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        var output: [ConfigItem] = []
        let topLevelNames = Set(items.filter { Precedence.isCandidate($0) && rank($0) != nil }.map(\.name))

        for (_, group) in Dictionary(grouping: items, by: \.name) {
            let ranked = Precedence.rankGroup(
                group,
                rank: rank,
                winner: { item, others in
                    item.applicability = .effective
                    let invocation = item.invocation ?? "/\(item.name)"
                    if others.isEmpty {
                        item.explanation = ["Runs when you type \(invocation), or when Claude decides it's relevant."]
                    } else {
                        let beaten = others.map { "the \(describe($0)) at \(displayPath($0.source.path))" }.joined(separator: " and ")
                        item.explanation = ["Runs when you type \(invocation), instead of \(beaten): \(reason(winner: item, loser: others[0]))."]
                    }
                    Precedence.applyCondition(&item)
                },
                loser: { item, winner in
                    item.applicability = .shadowed(by: winner.id)
                    item.explanation = [
                        "Overridden by the \(describe(winner)) at \(displayPath(winner.source.path)). \(reason(winner: winner, loser: item).prefix(1).uppercased() + reason(winner: winner, loser: item).dropFirst()), so \(winner.invocation ?? "/\(winner.name)") runs that one.",
                    ]
                },
                tie: { item, tied in
                    item.applicability = .unknown
                    item.explanation = [
                        "\(tied.count) \(item.scope.title.lowercased()) \(item.kind == .skill ? "skills" : "commands") share this name. The docs don't say which one runs.",
                    ]
                }
            )

            for var item in ranked {
                guard Precedence.isCandidate(item), rank(item) == nil else {
                    output.append(item)
                    continue
                }
                switch item.scope {
                case .nested:
                    if topLevelNames.contains(item.name), let origin = item.origin {
                        item.invocation = "/\(origin):\(item.name)"
                        item.explanation = ["Another skill already uses /\(item.name), so this one is listed as \(item.invocation ?? "") and Claude is told to use it for work in \(origin)/. Both stay available."]
                    } else {
                        item.explanation = ["Available as /\(item.name) once it loads."]
                    }
                    item.applicability = .conditional
                    if let condition = item.condition { item.explanation.append(condition) }
                case .synced:
                    if topLevelNames.contains(item.name) {
                        let winner = group.first { rank($0) != nil && Precedence.isCandidate($0) }
                        item.applicability = winner.map { .shadowed(by: $0.id) } ?? .effective
                        item.explanation = ["A local skill or command already uses /\(item.name), so this claude.ai skill runs only under its full name."]
                    } else {
                        item.applicability = .effective
                        item.explanation = ["Synced from your claude.ai account. Runs when you type /\(item.name) in sessions signed in with that account."]
                    }
                case .plugin:
                    item.applicability = .combined
                    item.explanation = ["Plugin skills are namespaced, so \(item.invocation ?? item.name) never competes with your own skills."]
                    Precedence.applyCondition(&item)
                default:
                    item.applicability = .unknown
                    item.explanation = ["Strata doesn't know how Claude Code ranks this location."]
                }
                output.append(item)
            }
        }
        return output
    }

    private func describe(_ item: ConfigItem) -> String {
        let kind = item.kind == .skill ? "skill" : "command"
        switch item.scope {
        case .managed: return "managed \(kind)"
        case .user: return "personal \(kind)"
        case .project: return "repo \(kind)"
        default: return kind
        }
    }

    private func reason(winner: ConfigItem, loser: ConfigItem) -> String {
        if winner.kind == .skill, loser.kind == .command {
            return "a skill wins over a command file with the same name"
        }
        switch (winner.scope, loser.scope) {
        case (.managed, _): return "managed skills take precedence over personal and project skills"
        case (.user, .project): return "personal skills (~/.claude/skills) take precedence over project skills"
        default: return "of the documented order: managed, then personal, then project"
        }
    }
}

// MARK: - Subagents

private struct AgentRules {
    let displayPath: (String) -> String

    /// Managed (1) > --agents flag (2) > project (3) > user (4) > plugin (5).
    private func rank(_ item: ConfigItem) -> Int? {
        switch item.scope {
        case .managed: 1
        case .project: 3
        case .user: 4
        case .plugin: 5
        default: nil
        }
    }

    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        Dictionary(grouping: items, by: \.name).values.flatMap { group in
            Precedence.rankGroup(
                group,
                rank: rank,
                winner: { item, others in
                    item.applicability = .effective
                    if others.isEmpty {
                        item.explanation = ["Claude can delegate to it by name (\(item.invocation ?? item.name))."]
                    } else {
                        item.explanation = [
                            "Used for \"\(item.name)\". It beats \(others.map { "the \(label($0.scope)) one" }.joined(separator: " and ")) because subagents rank managed, then project, then user, then plugin.",
                            "This is the opposite of skills, where your personal copy beats the repo's.",
                        ]
                    }
                },
                loser: { item, winner in
                    item.applicability = .shadowed(by: winner.id)
                    var explanation = ["Overridden by the \(label(winner.scope)) subagent at \(displayPath(winner.source.path)). Subagents rank managed, then project, then user, then plugin."]
                    if item.scope == .plugin, let scoped = item.invocation {
                        explanation.append("It may still be reachable by its scoped name, \(scoped).")
                    }
                    item.explanation = explanation
                },
                tie: { item, tied in
                    item.applicability = .unknown
                    item.explanation = [
                        "\(tied.count) files in the same \(label(item.scope)) agents folder declare the name \"\(item.name)\". Claude Code loads one of them by filesystem order, which isn't documented.",
                    ]
                }
            )
        }
    }

    private func label(_ scope: Scope) -> String {
        switch scope {
        case .managed: "managed"
        case .project: "repo"
        case .user: "user"
        case .plugin: "plugin"
        default: scope.title.lowercased()
        }
    }
}

// MARK: - MCP servers

private struct MCPRules {
    let displayPath: (String) -> String

    /// Managed first, then local (1), project (2), user (3). Plugin servers are compared by endpoint instead of name.
    private func rank(_ item: ConfigItem) -> Int? {
        switch item.scope {
        case .managed: 0
        case .local: 1
        case .project: 2
        case .user: 3
        default: nil
        }
    }

    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        let named = Dictionary(grouping: items.filter { $0.scope != .plugin }, by: \.name).values.flatMap { group in
            Precedence.rankGroup(
                group,
                rank: rank,
                winner: { item, others in
                    item.applicability = .effective
                    if others.isEmpty {
                        item.explanation = ["Claude Code connects to this server in this repository."]
                    } else {
                        item.explanation = [
                            "Used for \"\(item.name)\". It beats \(others.map { "the \($0.scope.title.lowercased()) definition" }.joined(separator: " and ")), because MCP scopes rank local, then project, then user.",
                            "Claude Code uses this whole entry. Fields from the other definitions aren't merged in.",
                        ]
                    }
                    Precedence.applyCondition(&item)
                },
                loser: { item, winner in
                    item.applicability = .shadowed(by: winner.id)
                    item.explanation = [
                        "Not used: the \(winner.scope.title.lowercased()) definition in \(displayPath(winner.source.path)) wins, and Claude Code doesn't merge fields across scopes.",
                    ]
                },
                tie: { item, _ in
                    item.applicability = .unknown
                    item.explanation = ["More than one definition at the same scope uses this name."]
                }
            )
        }

        let activeEndpoints = Dictionary(
            named.filter { $0.applicability == .effective || $0.applicability == .conditional }.compactMap { item in item.matchKey.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        let pluginItems = items.filter { $0.scope == .plugin }.map { item -> ConfigItem in
            var item = item
            guard Precedence.isCandidate(item) else { return item }
            if let key = item.matchKey, let duplicate = activeEndpoints[key] {
                item.applicability = .shadowed(by: duplicate.id)
                item.explanation = [
                    "Points at the same endpoint as your \(duplicate.scope.title.lowercased()) server \"\(duplicate.name)\", so Claude Code connects once, using that definition.",
                ]
            } else {
                item.applicability = .effective
                item.explanation = ["Started automatically because its plugin is enabled."]
                Precedence.applyCondition(&item)
            }
            return item
        }
        return named + pluginItems
    }
}

// MARK: - Hooks

/// Hooks from every settings file and enabled plugin run together, so none overrides another. The scanner has already
/// marked hooks that are turned off, duplicated, or waiting for workspace trust.
private struct HookRules {
    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        items.map { item in
            var item = item
            guard Precedence.isCandidate(item) else { return item }
            item.applicability = item.condition == nil ? .effective : .conditional
            item.explanation = item.condition.map { [$0] } ?? []
            item.explanation.append("Hooks from every settings file and enabled plugin all run; a higher-precedence file adds to them rather than replacing them.")
            return item
        }
    }
}

// MARK: - Plugins

private struct PluginRules {
    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        items.map { item in
            var item = item
            guard Precedence.isCandidate(item) else { return item }
            let decidedBy = item.metadataValue("Decided by")
            let setIn = item.metadataValue("Set in").map { " Values: \($0)." } ?? ""
            switch item.stage {
            case .enabled:
                item.applicability = .effective
                if let decidedBy {
                    item.explanation = ["Enabled by \(decidedBy). For each plugin, the highest-precedence settings file that mentions it decides: managed, then local, then project, then user.\(setIn)"]
                } else {
                    item.explanation = ["Installed, and no settings file turns it off, so it starts enabled by default."]
                }
                if item.scope == .project {
                    item.applicability = .conditional
                    item.explanation.append("Because the repository enables it, it loads only after you accept the workspace trust prompt.")
                }
                item.explanation.append("Strata can't see a running session: changes reach it after `/reload-plugins` or a restart.")
            case .installed:
                item.applicability = .inactive
                item.explanation = [decidedBy.map { "Installed but turned off by \($0).\(setIn)" } ?? "Installed but turned off by default (its manifest sets defaultEnabled to false)."]
            case .declared:
                item.applicability = .inactive
                item.explanation = [
                    decidedBy.map { "Enabled in \($0), but not installed on this Mac, so it can't load." } ?? "Recorded as installed, but its files are missing.",
                    "Run `claude plugin install \(item.name)` to fetch it.",
                ]
            case .discovered:
                item.applicability = .unknown
                item.explanation = ["Found on disk, but Strata can't tell whether it's enabled."]
            }
            return item
        }
    }
}

// MARK: - Instructions

private struct InstructionRules {
    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        let launch = items.filter { Precedence.isCandidate($0) && $0.condition == nil && $0.loadTiming == .atLaunch }
            .sorted { ($0.loadOrder ?? 0) < ($1.loadOrder ?? 0) }

        return items.map { item in
            var item = item
            guard Precedence.isCandidate(item) else { return item }
            if let condition = item.condition {
                item.applicability = .conditional
                item.explanation = [condition, "Instruction files are added to Claude's context, never overridden."]
                return item
            }
            item.applicability = .combined
            if let position = launch.firstIndex(where: { $0.id == item.id }) {
                var sentence = "Read at session start, \(ordinal(position + 1)) of \(launch.count) instruction files."
                if position + 1 < launch.count {
                    sentence += " Files read later, such as \(launch[position + 1].name), sit closer to the end of the context."
                }
                item.explanation = [sentence, "Claude Code concatenates every instruction file instead of letting one replace another."]
            } else {
                item.explanation = ["Added to Claude's context alongside the other instruction files."]
            }
            if item.metadataValue("Type") == "Import", let importer = item.metadataValue("Imported by") {
                item.explanation.insert("Imported by \(importer) with an @ reference.", at: 0)
            }
            return item
        }
    }

    private func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 10, number % 100) {
        case (1, let tens) where tens != 11: suffix = "st"
        case (2, let tens) where tens != 12: suffix = "nd"
        case (3, let tens) where tens != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}

// MARK: - Settings

private struct SettingRules {
    let displayPath: (String) -> String

    private enum Merge {
        case highestWins
        case lists
        case documentedCombination(String)
        case managedOrUserOnly
        case managedReplaces
        case undocumented

        var isProjectIgnored: Bool {
            if case .managedOrUserOnly = self { return true }
            return false
        }
    }

    /// Managed (1) > local (3) > project (4) > user (5).
    private func rank(_ item: ConfigItem) -> Int? {
        switch item.scope {
        case .managed: 1
        case .local: 3
        case .project: 4
        case .user: 5
        default: nil
        }
    }

    private func merge(for item: ConfigItem) -> Merge {
        switch item.name {
        case "permissions": return .documentedCombination("Permission rules from every settings file combine.")
        case "hooks": return .documentedCombination("Hooks from every settings file apply.")
        case "enabledPlugins": return .documentedCombination("Merged plugin by plugin. See Plugins for the result of each one.")
        case "fallbackModel": return .highestWins
        case "modelPicker": return .managedOrUserOnly
        case "availableModels": return .managedReplaces
        case "modelSettings": return .undocumented
        default: break
        }
        switch item.metadataValue("Value type") {
        case "list": return .lists
        case "object": return .undocumented
        default: return .highestWins
        }
    }

    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        Dictionary(grouping: items, by: \.name).values.flatMap { group -> [ConfigItem] in
            let candidates = group.filter(Precedence.isCandidate)
            guard let first = candidates.first else { return group }

            if candidates.count == 1 {
                return group.map { item in
                    var item = item
                    guard Precedence.isCandidate(item) else { return item }
                    if merge(for: item).isProjectIgnored, item.scope == .project || item.scope == .local {
                        item.applicability = .inactive
                        item.explanation = ["Claude Code ignores `\(item.name)` in project and local settings."]
                    } else {
                        item.applicability = .effective
                        item.explanation = ["Only \(displayPath(item.source.path)) sets `\(item.name)`, so its value applies."]
                    }
                    item.precedenceRank = 1
                    return item
                }
            }

            switch merge(for: first) {
            case .lists:
                return combine(group, "Lists merge across settings files, so every file's entries apply.")
            case .documentedCombination(let sentence):
                return combine(group, sentence)
            case .undocumented:
                return group.map { item in
                    var item = item
                    guard Precedence.isCandidate(item) else { return item }
                    item.applicability = .unknown
                    item.explanation = ["\(candidates.count) settings files set `\(item.name)`. The docs don't say whether its keys merge or the highest file replaces the rest."]
                    return item
                }
            case .managedReplaces where candidates.contains { $0.scope == .managed }:
                return highestWins(group, why: "A managed `availableModels` list applies as-is; entries in other files are ignored.")
            case .managedReplaces:
                return combine(group, "Without a managed list, `availableModels` entries merge across files.")
            case .managedOrUserOnly:
                let allowed = group.map { item -> ConfigItem in
                    var item = item
                    if Precedence.isCandidate(item), item.scope == .project || item.scope == .local {
                        item.inactiveReason = "Claude Code ignores `modelPicker` in project and local settings."
                        item.applicability = .inactive
                        item.explanation = [item.inactiveReason ?? ""]
                    }
                    return item
                }
                return highestWins(allowed, why: "`modelPicker` comes whole from the highest of managed and user settings.")
            case .highestWins:
                return highestWins(group, why: "Claude Code uses the value from the highest-precedence file: managed, then local, then project, then user.")
            }
        }
    }

    private func combine(_ group: [ConfigItem], _ sentence: String) -> [ConfigItem] {
        group.map { item in
            var item = item
            guard Precedence.isCandidate(item) else { return item }
            item.applicability = .combined
            item.precedenceRank = rank(item)
            item.explanation = [sentence]
            return item
        }
    }

    private func highestWins(_ group: [ConfigItem], why: String) -> [ConfigItem] {
        Precedence.rankGroup(
            group,
            rank: rank,
            winner: { item, others in
                item.applicability = .effective
                item.explanation = ["This value applies. It overrides \(others.map { displayPath($0.source.path) }.joined(separator: " and ")).", why]
                if item.scope == .managed {
                    item.explanation.append("A few security settings honour a stricter value from a lower file even over managed settings.")
                }
            },
            loser: { item, winner in
                item.applicability = .shadowed(by: winner.id)
                item.explanation = ["Overridden by \(displayPath(winner.source.path)).", why]
            },
            tie: { item, _ in
                item.applicability = .unknown
                item.explanation = ["Set more than once at the same level."]
            }
        )
    }
}
