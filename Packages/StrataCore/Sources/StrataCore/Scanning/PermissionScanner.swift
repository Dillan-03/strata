import Foundation

/// Lists each permission rule, extra directory and permission mode from the settings files. Rules from every file
/// combine; the resolver works out which allow and ask rules a deny or ask rule certainly beats.
struct PermissionScanner {
    let context: ScanContext
    let layers: [SettingsLayer]

    enum List: String, CaseIterable {
        case deny, ask, allow

        var title: String {
            switch self {
            case .deny: "Deny"
            case .ask: "Ask"
            case .allow: "Allow"
            }
        }
    }

    static let trustCondition = "Claude Code applies allow rules and extra directories from a repository's settings only "
        + "after you accept the workspace trust dialog for it, and Strata can't read whether you have."

    func scan() -> [ConfigItem] {
        let ordered = layers.sorted { $0.precedence < $1.precedence }
        let managedOnly = JSONValue.bool(ordered.first { $0.scope == .managed }?.dictionary("permissions")?["allowManagedPermissionRulesOnly"])
            ?? ordered.first { $0.scope == .managed }?.bool("allowManagedPermissionRulesOnly") ?? false
        let linkedClaudeFolder = (try? FileManager.default.destinationOfSymbolicLink(atPath: context.repositoryClaudeDirectory.path)) != nil

        var items: [ConfigItem] = []
        for layer in ordered {
            guard let permissions = layer.dictionary("permissions") else { continue }
            for list in List.allCases {
                let rules = ((permissions[list.rawValue] as? [Any]) ?? []).compactMap { $0 as? String }
                for (index, rule) in rules.enumerated() {
                    var item = ruleItem(rule, list: list, index: index, layer: layer)
                    if managedOnly, layer.scope != .managed {
                        item.inactiveReason = "Managed settings set `allowManagedPermissionRulesOnly`, so only your organisation's rules apply."
                    } else if list == .allow {
                        item.condition = trustCondition(for: layer, linked: linkedClaudeFolder)
                    }
                    items.append(item)
                }
            }
            let directories = ((permissions["additionalDirectories"] as? [Any]) ?? []).compactMap { $0 as? String }
            for (index, directory) in directories.enumerated() {
                var item = makeItem(
                    name: SecretRedactor.redactText(directory), summary: "Extra directory Claude can read and edit", layer: layer,
                    keyPath: "permissions.additionalDirectories.\(index)", details: [Metadatum("List", "Additional directory")]
                )
                item.condition = trustCondition(for: layer, linked: linkedClaudeFolder)
                items.append(item)
            }
            if let mode = permissions["defaultMode"] as? String {
                var item = makeItem(
                    name: "defaultMode", summary: "Sessions start in \(mode) mode", layer: layer,
                    keyPath: "permissions.defaultMode", details: [Metadatum("List", "Default mode"), Metadatum("Mode", mode)]
                )
                if mode == "bypassPermissions", [.project, .local].contains(layer.scope) {
                    item.inactiveReason = "Claude Code 2.1.257 and later ignore bypassPermissions in project and local settings. Earlier versions skip every permission prompt."
                }
                items.append(item)
            }
        }
        return items
    }

    /// Project allow rules always wait for trust. A local settings file is the user's own, unless `.claude` is a symbolic
    /// link; whether it's tracked in git needs git, which Strata never runs, so the explanation says so instead.
    private func trustCondition(for layer: SettingsLayer, linked: Bool) -> String? {
        switch layer.scope {
        case .project: Self.trustCondition
        case .local where linked: "`.claude` is a symbolic link, so Claude Code treats settings.local.json as the repository's and waits for workspace trust."
        default: nil
        }
    }

    private func ruleItem(_ rule: String, list: List, index: Int, layer: SettingsLayer) -> ConfigItem {
        let (tool, specifier) = Self.parse(rule)
        let action: String
        switch list {
        case .deny: action = "Blocks"
        case .ask: action = "Asks before"
        case .allow: action = "Allows without asking"
        }
        let what = specifier.map { "\(tool) \($0)" } ?? "every use of \(tool)"
        var details = [Metadatum("List", list.title), Metadatum("Tool", tool), Metadatum("Specifier", specifier.map(SecretRedactor.redactText) ?? "Every use")]
        if list == .allow, layer.scope == .local {
            details.append(Metadatum("Note", "If settings.local.json is tracked in git, Claude Code waits for workspace trust before using it."))
        }
        return makeItem(
            name: SecretRedactor.redactText(rule), summary: SecretRedactor.redactText("\(action) \(what)"), layer: layer,
            keyPath: "permissions.\(list.rawValue).\(index)", details: details
        )
    }

    private func makeItem(name: String, summary: String, layer: SettingsLayer, keyPath: String, details: [Metadatum]) -> ConfigItem {
        var item = ConfigItem(
            kind: .permission,
            name: name,
            summary: summary,
            scope: layer.scope,
            source: SourceLocation(path: layer.url.path, keyPath: keyPath),
            metadata: details + [Metadatum("File", context.displayPath(layer.url))],
            loadTiming: .atLaunch
        )
        item.fingerprint = Fingerprint.of(json: [keyPath, name])
        context.capture([keyPath: name], for: item.id)
        return item
    }

    /// `Tool` or `Tool(specifier)`. Parentheses inside the specifier are literal, so it runs to the last `)`.
    /// `Tool(*)` means every use, like `Tool`.
    static func parse(_ rule: String) -> (tool: String, specifier: String?) {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else { return (trimmed, nil) }
        let tool = String(trimmed[..<open])
        let specifier = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
        return (tool, specifier.isEmpty || specifier == "*" ? nil : specifier)
    }
}
