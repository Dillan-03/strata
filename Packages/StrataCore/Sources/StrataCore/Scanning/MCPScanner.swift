import Foundation

/// Finds MCP server definitions in every documented location. Never runs a command or contacts a server.
struct MCPScanner {
    struct Definition {
        let name: String
        let raw: [String: Any]
        let file: URL
        let keyPath: String
    }

    let context: ScanContext
    let layers: [SettingsLayer]
    let plugins: [PluginRecord]

    func scan() -> [ConfigItem] {
        var items: [ConfigItem] = []
        let globalConfig = context.readJSON(context.environment.globalConfigFile, label: "Global config (~/.claude.json)") ?? [:]
        let projectEntry = Self.projectEntry(in: globalConfig, repository: context.repository, reader: context.reader)

        if let managed = context.managedDirectory {
            let file = managed.appendingPathComponent("managed-mcp.json")
            if context.reader.isFile(file), let root = context.readJSON(file, label: "Managed MCP servers") {
                items += definitions(in: root["mcpServers"], file: file, keyPrefix: "mcpServers").map { item(for: $0, scope: .managed) }
            }
        }

        if let entry = projectEntry {
            items += definitions(in: entry.value["mcpServers"], file: context.environment.globalConfigFile, keyPrefix: "projects[\(entry.key)].mcpServers")
                .map { item(for: $0, scope: .local) }
        }

        let projectFile = context.repository.appendingPathComponent(".mcp.json")
        if let root = context.readJSON(projectFile, label: "Project MCP servers (.mcp.json)") {
            items += definitions(in: root["mcpServers"], file: projectFile, keyPrefix: "mcpServers").map { definition in
                var item = item(for: definition, scope: .project)
                applyProjectApproval(to: &item, projectEntry: projectEntry?.value)
                return item
            }
        }

        items += definitions(in: globalConfig["mcpServers"], file: context.environment.globalConfigFile, keyPrefix: "mcpServers")
            .map { item(for: $0, scope: .user) }

        for plugin in plugins {
            guard let root = plugin.root else { continue }
            let manifest = context.readJSON(root.appendingPathComponent(".claude-plugin/plugin.json"), label: "Plugin manifest") ?? [:]
            for definition in Self.pluginServerDefinitions(root: root, manifest: manifest, reader: context.reader) {
                var item = item(for: definition, scope: .plugin, plugin: plugin)
                if plugin.enabled == false {
                    item.inactiveReason = "The plugin \(plugin.id) is turned off, so Claude Code doesn't start its servers."
                } else if plugin.needsTrust {
                    item.condition = "This plugin is enabled by the repository, so its servers need the same one-time approval as `.mcp.json` servers."
                }
                items.append(item)
            }
        }

        let toggledOff = Set(JSONValue.strings(projectEntry?.value["disabledMcpServers"]) ?? [])
        for index in items.indices where toggledOff.contains(items[index].name) && items[index].inactiveReason == nil {
            items[index].inactiveReason = "Turned off in `/mcp` for this project (recorded in ~/.claude.json)."
        }
        return items
    }

    // MARK: - Locating definitions

    private func definitions(in value: Any?, file: URL, keyPrefix: String) -> [Definition] {
        guard let servers = value as? [String: Any] else { return [] }
        return servers.keys.sorted().compactMap { name in
            guard let raw = servers[name] as? [String: Any] else { return nil }
            return Definition(name: name, raw: raw, file: file, keyPath: "\(keyPrefix).\(name)")
        }
    }

    static func pluginServerDefinitions(root: URL, manifest: [String: Any], reader: FileReader) -> [Definition] {
        var results: [Definition] = []
        func collect(_ value: Any?, file: URL, prefix: String) {
            guard let servers = value as? [String: Any] else { return }
            for name in servers.keys.sorted() {
                if let raw = servers[name] as? [String: Any] {
                    results.append(Definition(name: name, raw: raw, file: file, keyPath: "\(prefix).\(name)"))
                }
            }
        }

        let mcpFile = root.appendingPathComponent(".mcp.json")
        if case .success(let object) = reader.jsonObject(at: mcpFile) {
            collect(object["mcpServers"] ?? object, file: mcpFile, prefix: object["mcpServers"] == nil ? "" : "mcpServers")
        }
        let manifestFile = root.appendingPathComponent(".claude-plugin/plugin.json")
        if let inline = manifest["mcpServers"] as? [String: Any] {
            collect(inline, file: manifestFile, prefix: "mcpServers")
        } else if let path = manifest["mcpServers"] as? String {
            let referenced = root.appendingPathComponent(path).standardizedFileURL
            if referenced.path.hasPrefix(root.standardizedFileURL.path), case .success(let object) = reader.jsonObject(at: referenced) {
                collect(object["mcpServers"] ?? object, file: referenced, prefix: object["mcpServers"] == nil ? "" : "mcpServers")
            }
        }
        return results
    }

    static func projectEntry(in globalConfig: [String: Any], repository: URL, reader: FileReader) -> (key: String, value: [String: Any])? {
        guard let projects = globalConfig["projects"] as? [String: Any] else { return nil }
        let targets = [repository.standardizedFileURL.path, reader.canonical(repository).path]
        for (key, value) in projects {
            guard let entry = value as? [String: Any] else { continue }
            let candidate = URL(fileURLWithPath: key).standardizedFileURL.path
            if targets.contains(candidate) || targets.contains(reader.canonical(URL(fileURLWithPath: key)).path) {
                return (key, entry)
            }
        }
        return nil
    }

    // MARK: - Building items

    private func item(for definition: Definition, scope: Scope, plugin: PluginRecord? = nil) -> ConfigItem {
        let raw = definition.raw
        let source = SourceLocation(path: definition.file.path, keyPath: definition.keyPath)
        let itemID = ConfigItem.makeID(kind: .mcpServer, scope: scope, source: source, name: definition.name)
        var metadata: [Metadatum] = []
        var blocker: String?
        let declaredType = (raw["type"] as? String)?.lowercased()
        let url = raw["url"] as? String
        let command = raw["command"] as? String

        let transport: String
        switch declaredType {
        case nil:
            transport = "stdio"
            if url != nil {
                blocker = "It has a `url` but no `type`, so Claude Code reads it as a stdio server and skips it. Add `\"type\": \"http\"` (or `sse` / `ws`)."
                report(.mcpURLWithoutType, "\(definition.name) has a url but no type", blocker, definition, itemID)
            }
        case "streamable-http":
            transport = "http"
        case "sdk":
            transport = "sdk"
            blocker = "`sdk` servers can only be registered by an SDK host application, so Claude Code skips this entry."
            report(.mcpUnsupportedType, "\(definition.name) uses the sdk type", blocker, definition, itemID)
        case let other?:
            transport = other
        }
        metadata.append(Metadatum("Transport", transport))
        if let plugin { metadata.append(Metadatum("Plugin", plugin.id)) }

        var matchSource = ""
        if transport == "stdio" {
            if let command {
                metadata.append(Metadatum("Command", SecretRedactor.redactText(command)))
                let arguments = JSONValue.strings(raw["args"]) ?? []
                if !arguments.isEmpty {
                    metadata.append(Metadatum("Arguments", SecretRedactor.redactArguments(arguments).joined(separator: " ")))
                }
                matchSource = ([command] + arguments).joined(separator: "\u{0}")
                if blocker == nil { checkExecutable(command, definition: definition, pluginRoot: plugin?.root, itemID: itemID) }
            } else if blocker == nil {
                blocker = "A stdio server needs a `command`."
                report(.missingRequiredField, "\(definition.name) has no command", blocker, definition, itemID)
            }
        } else if let url {
            metadata.append(Metadatum("URL", SecretRedactor.redactURL(url)))
            matchSource = Self.normalisedEndpoint(url)
        }

        if let headers = JSONValue.stringMap(raw["headers"]), !headers.isEmpty {
            metadata.append(Metadatum("Headers", SecretRedactor.redactMap(headers, maskAllValues: true).map { "\($0.key): \($0.value)" }.joined(separator: ", ")))
        }
        if let environment = JSONValue.stringMap(raw["env"]), !environment.isEmpty {
            metadata.append(Metadatum("Environment", SecretRedactor.redactMap(environment, maskAllValues: true).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))
        }
        if let helper = raw["headersHelper"] as? String {
            metadata.append(Metadatum("Headers helper", SecretRedactor.redactText(helper)))
        }
        if raw["oauth"] != nil {
            metadata.append(Metadatum("OAuth", "Configured"))
        }
        if let timeout = raw["timeout"] as? NSNumber, !JSONValue.isBoolean(timeout) {
            metadata.append(Metadatum("Timeout", "\(timeout.intValue) ms"))
        }
        metadata.append(Metadatum("Defined in", context.displayPath(definition.file)))

        return ConfigItem(
            kind: .mcpServer,
            name: definition.name,
            summary: metadata.first { $0.label == "URL" || $0.label == "Command" }?.value,
            scope: scope,
            source: source,
            origin: plugin?.id,
            metadata: metadata,
            stage: .discovered,
            loadTiming: .atLaunch,
            loadBlocker: blocker,
            matchKey: matchSource.isEmpty ? nil : Self.fingerprint(matchSource)
        )
    }

    private func applyProjectApproval(to item: inout ConfigItem, projectEntry: [String: Any]?) {
        let name = item.name
        let personal = layers.filter { $0.scope != .project }
        if let rejecting = layers.first(where: { ($0.strings("disabledMcpjsonServers") ?? []).contains(name) }) {
            item.inactiveReason = "Rejected by `disabledMcpjsonServers` in \(rejecting.label)."
            return
        }
        if (JSONValue.strings(projectEntry?["disabledMcpjsonServers"]) ?? []).contains(name) {
            item.inactiveReason = "You rejected it for this project (recorded in ~/.claude.json)."
            return
        }
        if let approving = personal.first(where: { ($0.strings("enabledMcpjsonServers") ?? []).contains(name) || $0.bool("enableAllProjectMcpServers") == true }) {
            item.metadata.append(Metadatum("Approval", "Approved in \(approving.label)"))
            return
        }
        if (JSONValue.strings(projectEntry?["enabledMcpjsonServers"]) ?? []).contains(name)
            || JSONValue.bool(projectEntry?["enableAllProjectMcpServers"]) == true {
            item.metadata.append(Metadatum("Approval", "Approved for this project (recorded in ~/.claude.json)"))
            return
        }
        if let shared = layers.first(where: { $0.scope == .project && (($0.strings("enabledMcpjsonServers") ?? []).contains(name) || $0.bool("enableAllProjectMcpServers") == true) }) {
            item.condition = "Approved in \(shared.label), which is committed to the repository. Claude Code only honours that after you trust the workspace."
            return
        }
        item.condition = "Claude Code asks you to approve servers from `.mcp.json` the first time an interactive session starts here. `claude -p` runs load them without asking."
    }

    private func checkExecutable(_ command: String, definition: Definition, pluginRoot: URL?, itemID: ConfigItem.ID) {
        var expanded = command
        if let pluginRoot {
            expanded = expanded.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}", with: pluginRoot.path)
        }
        guard !expanded.contains("$") else { return }
        if expanded.hasPrefix("~/") {
            expanded = context.environment.homeDirectory.appendingPathComponent(String(expanded.dropFirst(2))).path
        }

        if expanded.hasPrefix("/") {
            if !context.reader.isExecutable(URL(fileURLWithPath: expanded)) {
                context.report(Diagnostic(
                    severity: .warning,
                    code: .mcpMissingExecutable,
                    title: "\(definition.name): command not found",
                    detail: "`\(SecretRedactor.redactText(command))` doesn't exist or isn't executable, so the server will fail to start.",
                    suggestion: "Fix the path in \(context.displayPath(definition.file)), or reinstall the server.",
                    paths: [definition.file.path],
                    itemIDs: [itemID]
                ))
            }
        } else if expanded.contains("/") {
            context.report(Diagnostic(
                severity: .warning,
                code: .mcpRelativeExecutable,
                title: "\(definition.name) uses a relative command path",
                detail: "Relative paths in `command` resolve against the folder you launch Claude Code from, not the config file, so the server fails when you start elsewhere.",
                suggestion: "Use an absolute path, or a command that's on your PATH.",
                paths: [definition.file.path],
                itemIDs: [itemID]
            ))
        } else {
            let found = context.environment.executableSearchPaths.contains {
                context.reader.isExecutable($0.appendingPathComponent(expanded))
            }
            if !found {
                context.report(Diagnostic(
                    severity: .info,
                    code: .mcpExecutableNotOnStandardPath,
                    title: "\(definition.name): `\(expanded)` wasn't found in the usual places",
                    detail: "Strata checked your PATH and the standard install folders. Apps launched from the Dock don't see your shell's PATH, so this may still work from a terminal.",
                    paths: [definition.file.path],
                    itemIDs: [itemID]
                ))
            }
        }
    }

    private func report(_ code: Diagnostic.Code, _ title: String, _ detail: String?, _ definition: Definition, _ itemID: ConfigItem.ID) {
        context.report(Diagnostic(
            severity: .conflict,
            code: code,
            title: title,
            detail: detail ?? "",
            paths: [definition.file.path],
            itemIDs: [itemID]
        ))
    }

    /// Endpoint comparison as documented: case-insensitive scheme and host, default ports and trailing slashes ignored.
    static func normalisedEndpoint(_ text: String) -> String {
        guard var components = URLComponents(string: text) else { return text }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.string ?? text
    }

    /// FNV-1a, so endpoints can be compared without storing them.
    static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
