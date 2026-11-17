import Foundation

// MARK: - Permissions

/// Claude Code checks deny rules, then ask, then allow, across every settings file, and the first match decides; a more
/// specific rule doesn't change the order. A rule is marked overridden only when another rule certainly matches every
/// call it does: the same tool with no specifier, or the same specifier. Glob overlaps aren't worked out.
struct PermissionRules {
    private static let rank: [Scope: Int] = [.managed: 1, .local: 3, .project: 4, .user: 5]

    func resolve(_ items: [ConfigItem]) -> [ConfigItem] {
        let active = items.filter { Precedence.isCandidate($0) }
        let rules = active.filter { ["Deny", "Ask"].contains($0.metadataValue("List") ?? "") }
        let modes = active.filter { $0.metadataValue("List") == "Default mode" }.sorted { (Self.rank[$0.scope] ?? 9) < (Self.rank[$1.scope] ?? 9) }
        return items.map { item in
            var item = item
            guard Precedence.isCandidate(item) else { return item }
            let list = item.metadataValue("List") ?? ""
            if list == "Default mode" {
                if let winner = modes.first, winner.id != item.id {
                    item.applicability = .shadowed(by: winner.id)
                    item.explanation = ["\(winner.scope.title) settings also set defaultMode, and the higher-precedence file's value wins."]
                } else {
                    item.applicability = .effective
                    item.explanation = ["The highest-precedence defaultMode, so sessions start in this mode unless `--permission-mode` says otherwise."]
                }
                return item
            }
            let beaters = list == "Allow" ? ["Deny", "Ask"] : list == "Ask" ? ["Deny"] : []
            let winner = rules.first { rule in
                rule.id != item.id && beaters.contains(rule.metadataValue("List") ?? "") && rule.metadataValue("Tool") == item.metadataValue("Tool")
                    && (rule.metadataValue("Specifier") == "Every use" || rule.metadataValue("Specifier") == item.metadataValue("Specifier"))
            }
            if let winner {
                item.applicability = .shadowed(by: winner.id)
                item.explanation = [
                    "The \((winner.metadataValue("List") ?? "").lowercased()) rule \(winner.name) in \(winner.scope.title) settings matches every call this one does, "
                        + "and Claude Code checks deny, then ask, then allow, so this rule never decides anything.",
                ]
                return item
            }
            item.applicability = item.condition == nil ? .effective : .conditional
            item.explanation = item.condition.map { [$0] } ?? []
            switch list {
            case "Deny": item.explanation.append("Claude Code checks deny rules first, from every settings file, so no allow rule anywhere can undo this.")
            case "Ask": item.explanation.append("Claude Code asks before matching calls, even when a more specific allow rule also matches.")
            case "Allow":
                item.explanation.append(
                    "Matching calls run without asking unless a deny or ask rule from any settings file also matches. "
                        + "Strata only flags overlaps it's certain of: the same tool with no specifier, or the same specifier."
                )
            default: item.explanation.append("Gives Claude file access to this directory. It doesn't load any configuration from it.")
            }
            return item
        }
    }
}

// MARK: - Hooks

/// Hooks from every settings file and enabled plugin run together, so none overrides another. The scanner has already
/// marked hooks that are turned off, duplicated, or waiting for workspace trust.
struct HookRules {
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
