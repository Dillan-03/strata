import Foundation

/// LSP servers and monitors that plugins add. Strata lists their commands, masked, and never starts them.
struct PluginComponentScanner {
    let context: ScanContext
    let plugins: [PluginRecord]

    private static let docs = "https://code.claude.com/docs/en/plugins-reference"

    func scan() -> [ConfigItem] {
        plugins.flatMap { plugin -> [ConfigItem] in
            guard let root = plugin.root else { return [] }
            let manifestURL = root.appendingPathComponent(".claude-plugin/plugin.json")
            let manifest: [String: Any]
            if case .success(let object) = context.reader.jsonObject(at: manifestURL) { manifest = object } else { manifest = [:] }
            var items = lspServers(plugin: plugin, root: root, manifest: manifest, manifestURL: manifestURL)
                + monitors(plugin: plugin, root: root, manifest: manifest, manifestURL: manifestURL)
            if plugin.enabled != true {
                for index in items.indices { items[index].inactiveReason = "The plugin \(plugin.id) is turned off." }
            }
            return items
        }
    }

    // MARK: - LSP servers

    /// `.lsp.json` at the plugin root first, then each config the manifest's `lspServers` declares, in order. A later
    /// server with the same name replaces an earlier one.
    private func lspServers(plugin: PluginRecord, root: URL, manifest: [String: Any], manifestURL: URL) -> [ConfigItem] {
        var configs: [(URL, [String: Any])] = []
        if case .success(let object) = context.reader.jsonObject(at: root.appendingPathComponent(".lsp.json")) {
            configs.append((root.appendingPathComponent(".lsp.json"), object))
        }
        let declared = manifest["lspServers"]
        for entry in (declared as? [Any]) ?? (declared.map { [$0] } ?? []) {
            if let path = entry as? String {
                let url = root.appendingPathComponent(path).standardizedFileURL
                if url.path.hasPrefix(root.standardizedFileURL.path + "/"), case .success(let object) = context.reader.jsonObject(at: url) {
                    configs.append((url, object))
                }
            } else if let inline = entry as? [String: Any] {
                configs.append((manifestURL, inline))
            }
        }

        var items: [ConfigItem] = []
        var latest: [String: Int] = [:]
        for (file, servers) in configs {
            for name in servers.keys.sorted() {
                guard let server = servers[name] as? [String: Any] else { continue }
                let command = ([(server["command"] as? String) ?? ""] + ((server["args"] as? [Any]) ?? []).compactMap { $0 as? String })
                    .filter { !$0.isEmpty }.joined(separator: " ")
                let languages = ((server["extensionToLanguage"] as? [String: Any]) ?? [:]).keys.sorted().joined(separator: ", ")
                var item = ConfigItem(
                    kind: .lspServer, name: name, summary: SecretRedactor.redactText(command), scope: .plugin,
                    source: SourceLocation(path: file.path, keyPath: name), origin: plugin.id,
                    metadata: [
                        Metadatum("Command", SecretRedactor.redactText(command)),
                        Metadatum("File types", languages.isEmpty ? "None listed" : languages),
                        Metadatum("Plugin", plugin.id),
                        Metadatum("File", context.displayPath(file)),
                    ],
                    loadTiming: .atLaunch
                )
                item.applicability = .effective
                item.explanation = ["Gives Claude code intelligence for these file types. Strata shows the command and never runs it. (\(Self.docs)#lspservers)"]
                if let earlier = latest[name] {
                    items[earlier].applicability = .shadowed(by: item.id)
                    items[earlier].explanation = ["A config the plugin loads later declares a server with the same name, and the later one replaces it."]
                }
                latest[name] = items.count
                items.append(item)
            }
        }
        return items
    }

    // MARK: - Monitors

    /// `monitors/monitors.json`, or what the manifest's `experimental.monitors` (or older top-level `monitors`) names.
    private func monitors(plugin: PluginRecord, root: URL, manifest: [String: Any], manifestURL: URL) -> [ConfigItem] {
        let declared = (manifest["experimental"] as? [String: Any])?["monitors"] ?? manifest["monitors"]
        var file = root.appendingPathComponent("monitors/monitors.json")
        var list: [Any] = []
        if let path = declared as? String {
            file = root.appendingPathComponent(path).standardizedFileURL
            guard file.path.hasPrefix(root.standardizedFileURL.path + "/") else { return [] }
        } else if let inline = declared as? [Any] {
            file = manifestURL
            list = inline
        }
        if list.isEmpty, let data = try? Data(contentsOf: file), let parsed = try? JSONSerialization.jsonObject(with: data) {
            list = (parsed as? [Any]) ?? ((parsed as? [String: Any])?["monitors"] as? [Any]) ?? []
        }
        return list.compactMap { $0 as? [String: Any] }.compactMap { monitor in
            guard let name = monitor["name"] as? String else { return nil }
            let command = SecretRedactor.redactText((monitor["command"] as? String) ?? "")
            let when = (monitor["when"] as? String) ?? "always"
            let starts = when.hasPrefix("on-skill-invoke:") ? "The first time /\(when.dropFirst("on-skill-invoke:".count)) runs" : "At session start"
            var item = ConfigItem(
                kind: .monitor, name: name, summary: monitor["description"] as? String, scope: .plugin,
                source: SourceLocation(path: file.path, keyPath: name), origin: plugin.id,
                metadata: [
                    Metadatum("Command", command), Metadatum("Starts", starts),
                    Metadatum("Plugin", plugin.id), Metadatum("File", context.displayPath(file)),
                ],
                loadTiming: when == "always" ? .atLaunch : .whenInvoked
            )
            item.applicability = .effective
            item.explanation = [
                "Claude Code runs this command as a background process in the session's folder. Strata shows it and never runs it.",
                "Monitors don't start in `claude -p` sessions. (\(Self.docs)#monitors)",
            ]
            return item
        }
    }
}
