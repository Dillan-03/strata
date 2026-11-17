import Foundation

/// Lists every hook handler from the settings files and enabled plugins: what event it runs on, what it runs, and
/// where it's declared. Hooks merge across files rather than overriding, so the work here is spotting what turns them off.
/// Skill and subagent frontmatter hooks aren't listed: they only run while that skill or subagent is in use.
struct HookScanner {
    let context: ScanContext
    let layers: [SettingsLayer]
    let plugins: [PluginRecord]

    static let trustCondition = "Runs once this folder is trusted. In an interactive session Claude Code holds back hooks "
        + "from every settings file until you accept the workspace trust dialog, and Strata can't read whether you have."

    private struct Handler {
        let event: String
        let matcher: String
        let index: Int
        let value: [String: Any]
        /// The same handler in two settings files runs once, so this compares event, matcher and handler.
        let identity: String
    }

    func scan() -> [ConfigItem] {
        let ordered = layers.sorted { $0.precedence < $1.precedence }
        let disabledBy = ordered.first { $0.bool("disableAllHooks") != nil }.flatMap { $0.bool("disableAllHooks") == true ? $0 : nil }
        let managed = ordered.first { $0.scope == .managed }
        let managedOnly = managed?.bool("allowManagedHooksOnly") == true
        let forceEnabled = Set((managed?.dictionary("enabledPlugins") ?? [:]).compactMap { JSONValue.bool($0.value) == true ? $0.key : nil })

        var items: [ConfigItem] = []
        var firstFile: [String: String] = [:]
        for layer in ordered {
            for handler in handlers(in: layer.values["hooks"]) {
                var item = makeItem(handler, scope: layer.scope, file: layer.url, origin: nil)
                if let disabledBy, layer.scope != .managed || disabledBy.scope == .managed {
                    item.inactiveReason = "`disableAllHooks` is true in \(disabledBy.label), so Claude Code doesn't run it."
                } else if managedOnly, layer.scope != .managed {
                    item.inactiveReason = "Managed settings set `allowManagedHooksOnly`, so only your organisation's hooks run."
                } else if let first = firstFile[handler.identity] {
                    item.inactiveReason = "The same handler is in \(first). Claude Code runs a handler defined in more than one settings file once."
                } else {
                    firstFile[handler.identity] = layer.label
                    item.condition = Self.trustCondition
                }
                items.append(item)
            }
        }

        for plugin in plugins {
            guard let root = plugin.root else { continue }
            for (file, value) in pluginHookSources(root: root) {
                for handler in handlers(in: value) {
                    var item = makeItem(handler, scope: .plugin, file: file, origin: plugin.id)
                    let exempt = forceEnabled.contains(plugin.id)
                    if plugin.enabled != true {
                        item.inactiveReason = "The plugin \(plugin.id) is turned off, so its hooks don't run."
                    } else if let disabledBy, disabledBy.scope == .managed || !exempt {
                        item.inactiveReason = "`disableAllHooks` is true in \(disabledBy.label), so Claude Code doesn't run it."
                    } else if managedOnly, !exempt {
                        item.inactiveReason = "Managed settings set `allowManagedHooksOnly`, and they don't force-enable \(plugin.id)."
                    } else if plugin.needsTrust {
                        item.condition = "The repository enables \(plugin.id), so the plugin, and its hooks, load only after you accept the workspace trust prompt."
                    }
                    items.append(item)
                }
            }
        }
        return items
    }

    // MARK: - Reading

    /// `{ event: [ { matcher, hooks: [handler] } ] }`, the shape settings files, `hooks/hooks.json` and inline plugin hooks share.
    private func handlers(in value: Any?) -> [Handler] {
        guard let events = value as? [String: Any] else { return [] }
        var result: [Handler] = []
        for event in events.keys.sorted() {
            guard let groups = events[event] as? [Any] else { continue }
            var index = 0
            for case let group as [String: Any] in groups {
                let matcher = (group["matcher"] as? String) ?? ""
                for case let handler as [String: Any] in (group["hooks"] as? [Any]) ?? [] {
                    let canonical = (try? JSONSerialization.data(withJSONObject: handler, options: [.sortedKeys])).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
                    result.append(Handler(event: event, matcher: matcher, index: index, value: handler, identity: "\(event)\u{1F}\(matcher)\u{1F}\(canonical)"))
                    index += 1
                }
            }
        }
        return result
    }

    /// A plugin's hooks: `hooks/hooks.json`, plus whatever its manifest's `hooks` names: a file, an inline event map,
    /// or a list mixing both. Files need the `{"hooks": …}` wrapper; Claude Code won't load one without it.
    private func pluginHookSources(root: URL) -> [(URL, Any?)] {
        var sources: [(URL, Any?)] = []
        var seenFiles = Set<String>()
        func addFile(_ url: URL) {
            let url = url.standardizedFileURL
            guard url.path.hasPrefix(root.standardizedFileURL.path + "/"), seenFiles.insert(url.path).inserted,
                  context.reader.isFile(url), case .success(let object) = context.reader.jsonObject(at: url) else { return }
            sources.append((url, object["hooks"]))
        }
        addFile(root.appendingPathComponent("hooks/hooks.json"))
        let manifestURL = root.appendingPathComponent(".claude-plugin/plugin.json")
        guard case .success(let manifest) = context.reader.jsonObject(at: manifestURL) else { return sources }
        let declared = manifest["hooks"]
        for entry in (declared as? [Any]) ?? (declared.map { [$0] } ?? []) {
            if let path = entry as? String {
                addFile(root.appendingPathComponent(path))
            } else if entry is [String: Any] {
                sources.append((manifestURL, entry))
            }
        }
        return sources
    }

    // MARK: - Items

    private func makeItem(_ handler: Handler, scope: Scope, file: URL, origin: String?) -> ConfigItem {
        let type = (handler.value["type"] as? String) ?? "command"
        let matcher = handler.matcher.isEmpty || handler.matcher == "*" ? "all" : handler.matcher
        let action = Self.action(of: handler.value, type: type)
        var metadata = [
            Metadatum("Event", handler.event),
            Metadatum("Matcher", matcher == "all" ? "Everything (no matcher)" : handler.matcher),
            Metadatum("Type", type),
            Metadatum(Self.actionLabel(type), action),
        ]
        if let timeout = handler.value["timeout"] as? NSNumber, !JSONValue.isBoolean(timeout) {
            metadata.append(Metadatum("Timeout", "\(timeout.stringValue) s"))
        }
        if let condition = handler.value["if"] as? String { metadata.append(Metadatum("Only if", SecretRedactor.redactText(condition))) }
        metadata.append(Metadatum("File", context.displayPath(file)))
        if let origin { metadata.append(Metadatum("Plugin", origin)) }

        var item = ConfigItem(
            kind: .hook,
            name: matcher == "all" ? handler.event : "\(handler.event): \(handler.matcher)",
            summary: action,
            scope: scope,
            source: SourceLocation(path: file.path, keyPath: "hooks.\(handler.event).\(handler.index)"),
            origin: origin,
            metadata: metadata,
            loadTiming: .atLaunch
        )
        item.fingerprint = Fingerprint.of(json: handler.value)
        context.capture(handler.value, root: item.name, for: item.id)
        return item
    }

    private static func actionLabel(_ type: String) -> String {
        switch type {
        case "http": "URL"
        case "mcp_tool": "MCP tool"
        case "prompt", "agent": "Prompt"
        default: "Command"
        }
    }

    /// What the handler runs, with anything that looks like a secret masked.
    private static func action(of handler: [String: Any], type: String) -> String {
        switch type {
        case "http":
            return SecretRedactor.redactText((handler["url"] as? String) ?? "No URL")
        case "mcp_tool":
            return "\((handler["server"] as? String) ?? "?") / \((handler["tool"] as? String) ?? "?")"
        case "prompt", "agent":
            let prompt = (handler["prompt"] as? String) ?? ""
            return SecretRedactor.redactText(prompt.split(separator: "\n").first.map(String.init) ?? prompt)
        default:
            let command = (handler["command"] as? String) ?? ""
            let args = ((handler["args"] as? [Any]) ?? []).compactMap { $0 as? String }
            return SecretRedactor.redactText(([command] + args).filter { !$0.isEmpty }.joined(separator: " "))
        }
    }
}
