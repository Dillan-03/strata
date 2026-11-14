import Foundation

/// A plugin Strata found, with the folder its components live in.
struct PluginRecord {
    enum Origin: String {
        case marketplace
        case skillsDirectory = "skills-dir"
        case synced
    }

    let id: String
    /// What the plugin's components are namespaced under: the manifest `name`, falling back to the entry name.
    let namespace: String
    let origin: Origin
    let root: URL?
    /// Resolved enablement. `nil` when nothing on disk decides it.
    let enabled: Bool?
    let decidedBy: SettingsLayer?
    /// True when a project-scope source is involved and Claude Code waits for workspace trust.
    let needsTrust: Bool
    var item: ConfigItem
}

struct PluginScanner {
    let context: ScanContext
    let layers: [SettingsLayer]

    func scan() -> [PluginRecord] {
        let pluginsDirectory = context.claudeDirectory.appendingPathComponent("plugins")
        let installs = installRecords(pluginsDirectory: pluginsDirectory)
        var records: [PluginRecord] = []
        var seen: Set<String> = []

        let mentioned = Set(layers.flatMap { ($0.dictionary("enabledPlugins") ?? [:]).keys })
        let marketplaceIDs = Set(installs.keys).union(mentioned.filter { !Self.isReservedOrigin($0) })

        for id in marketplaceIDs.sorted() {
            seen.insert(id)
            records.append(marketplacePlugin(id: id, installs: installs[id] ?? []))
        }
        for record in directoryPlugins(in: [context.claudeDirectory.appendingPathComponent("skills")], scope: .user, origin: .skillsDirectory)
            + directoryPlugins(in: [context.repositoryClaudeDirectory.appendingPathComponent("skills")], scope: .project, origin: .skillsDirectory)
            + directoryPlugins(in: [pluginsDirectory.appendingPathComponent("synced")], scope: .synced, origin: .synced)
        where seen.insert(record.id).inserted {
            records.append(record)
        }
        return records
    }

    // MARK: - Marketplace plugins

    private struct InstallRecord {
        let scope: String?
        let installPath: String?
        let version: String?
        let projectPath: String?
    }

    private func installRecords(pluginsDirectory: URL) -> [String: [InstallRecord]] {
        let file = pluginsDirectory.appendingPathComponent("installed_plugins.json")
        guard let root = context.readJSON(file, label: "Installed plugins") else { return [:] }
        guard let plugins = root["plugins"] as? [String: Any] else {
            if !root.isEmpty {
                context.report(Diagnostic(
                    severity: .info,
                    code: .unrecognisedFormat,
                    title: "Plugin install records use a format Strata doesn't recognise",
                    detail: "`installed_plugins.json` has no `plugins` object. Its layout isn't documented, so Strata shows plugins from settings only.",
                    paths: [file.path]
                ))
            }
            return [:]
        }
        var result: [String: [InstallRecord]] = [:]
        for (id, value) in plugins {
            let entries: [[String: Any]] = (value as? [[String: Any]]) ?? ((value as? [String: Any]).map { [$0] } ?? [])
            result[id] = entries.map {
                InstallRecord(
                    scope: $0["scope"] as? String,
                    installPath: $0["installPath"] as? String,
                    version: $0["version"] as? String,
                    projectPath: $0["projectPath"] as? String
                )
            }
        }
        return result
    }

    private func marketplacePlugin(id: String, installs: [InstallRecord]) -> PluginRecord {
        let parts = id.split(separator: "@", maxSplits: 1).map(String.init)
        let entryName = parts.first ?? id
        let marketplace = parts.count > 1 ? parts[1] : nil

        let applicable = installs.first { install in
            guard let projectPath = install.projectPath else { return true }
            return URL(fileURLWithPath: projectPath).standardizedFileURL.path == context.repository.path
        } ?? installs.first
        let root = applicable?.installPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let rootExists = root.map(context.reader.isDirectory) ?? false
        let manifest = rootExists ? readManifest(root: root) : [:]
        let namespace = (manifest["name"] as? String) ?? entryName

        let (enabled, decidedBy) = enablement(for: id, defaultEnabled: JSONValue.bool(manifest["defaultEnabled"]) ?? true, installed: rootExists)
        var metadata: [Metadatum] = [Metadatum("Plugin ID", id)]
        if let marketplace { metadata.append(Metadatum("Marketplace", marketplace)) }
        if let version = (manifest["version"] as? String) ?? applicable?.version { metadata.append(Metadatum("Version", version)) }
        if let scope = applicable?.scope { metadata.append(Metadatum("Install scope", scope)) }
        if let root { metadata.append(Metadatum("Install path", context.displayPath(root))) }
        if let decidedBy { metadata.append(Metadatum("Decided by", "\(decidedBy.label) (\(context.displayPath(decidedBy.url)))")) }
        metadata.append(contentsOf: mentions(of: id))
        if rootExists, let root { metadata.append(contentsOf: componentSummary(root: root, manifest: manifest)) }

        let stage: Stage
        if rootExists {
            stage = enabled == true ? .enabled : .installed
        } else {
            stage = .declared
        }

        let item = ConfigItem(
            kind: .plugin,
            name: id,
            summary: manifest["description"] as? String,
            scope: decidedBy?.scope ?? Self.scope(fromInstallScope: applicable?.scope),
            source: SourceLocation(path: (decidedBy?.url ?? root ?? context.claudeDirectory).path, keyPath: decidedBy.map { _ in "enabledPlugins.\(id)" }),
            origin: marketplace,
            metadata: metadata,
            stage: stage,
            loadTiming: .atLaunch
        )

        if !installs.isEmpty, !rootExists {
            context.report(Diagnostic(
                severity: .warning,
                code: .pluginInstallMissing,
                title: "\(entryName) is recorded as installed but its files are missing",
                detail: "`installed_plugins.json` points at \(root.map(context.displayPath) ?? "no folder"), which doesn't exist.",
                suggestion: "Reinstall it with `claude plugin install \(id)`.",
                paths: root.map { [$0.path] } ?? [],
                itemIDs: [item.id]
            ))
        }

        return PluginRecord(
            id: id,
            namespace: namespace,
            origin: .marketplace,
            root: rootExists ? root : nil,
            enabled: enabled,
            decidedBy: decidedBy,
            needsTrust: decidedBy?.scope == .project,
            item: item
        )
    }

    // MARK: - Skills-directory and synced plugins

    private func directoryPlugins(in directories: [URL], scope: Scope, origin: PluginRecord.Origin) -> [PluginRecord] {
        directories.flatMap { directory in
            context.walker.children(of: directory).compactMap { folder -> PluginRecord? in
                guard context.reader.isDirectory(folder) else { return nil }
                let manifestURL = folder.appendingPathComponent(".claude-plugin/plugin.json")
                guard context.reader.isFile(manifestURL) else { return nil }
                let manifest = readManifest(root: folder)
                let name = (manifest["name"] as? String) ?? folder.lastPathComponent
                let id = "\(name)@\(origin.rawValue)"
                let (enabled, decidedBy) = enablement(for: id, defaultEnabled: JSONValue.bool(manifest["defaultEnabled"]) ?? true, installed: true)

                var metadata = [Metadatum("Plugin ID", id), Metadatum("Folder", context.displayPath(folder))]
                if let version = manifest["version"] as? String { metadata.append(Metadatum("Version", version)) }
                if let decidedBy { metadata.append(Metadatum("Decided by", "\(decidedBy.label) (\(context.displayPath(decidedBy.url)))")) }
                metadata.append(contentsOf: componentSummary(root: folder, manifest: manifest))

                let item = ConfigItem(
                    kind: .plugin,
                    name: id,
                    summary: manifest["description"] as? String,
                    scope: scope,
                    source: SourceLocation(path: manifestURL.path),
                    origin: origin.rawValue,
                    metadata: metadata,
                    stage: enabled == false ? .installed : .enabled,
                    loadTiming: .atLaunch
                )
                return PluginRecord(
                    id: id,
                    namespace: name,
                    origin: origin,
                    root: folder,
                    enabled: enabled,
                    decidedBy: decidedBy,
                    needsTrust: scope == .project,
                    item: item
                )
            }
        }
    }

    // MARK: - Helpers

    /// Every settings file that mentions the plugin id, highest precedence first, for the "also set in" explanation.
    private func mentions(of id: String) -> [Metadatum] {
        let values = layers.sorted { $0.precedence < $1.precedence }.compactMap { layer -> String? in
            guard let value = JSONValue.bool(layer.dictionary("enabledPlugins")?[id]) else { return nil }
            return "\(layer.label): \(value ? "on" : "off")"
        }
        return values.count > 1 ? [Metadatum("Set in", values.joined(separator: "; "))] : []
    }

    /// The documented rule: each plugin id takes its value from the highest-precedence settings file that mentions it.
    private func enablement(for id: String, defaultEnabled: Bool, installed: Bool) -> (Bool?, SettingsLayer?) {
        for layer in layers.sorted(by: { $0.precedence < $1.precedence }) {
            if let value = JSONValue.bool(layer.dictionary("enabledPlugins")?[id]) {
                return (value, layer)
            }
        }
        return (installed ? defaultEnabled : nil, nil)
    }

    private func readManifest(root: URL?) -> [String: Any] {
        guard let root else { return [:] }
        let url = root.appendingPathComponent(".claude-plugin/plugin.json")
        guard context.reader.isFile(url) else { return [:] }
        return context.readJSON(url, label: "Plugin manifest") ?? [:]
    }

    private func componentSummary(root: URL, manifest: [String: Any]) -> [Metadatum] {
        let skills = context.walker.children(of: root.appendingPathComponent("skills"))
            .filter { context.reader.isFile($0.appendingPathComponent("SKILL.md")) }.count
            + (context.reader.isFile(root.appendingPathComponent("SKILL.md")) ? 1 : 0)
        let agents = context.walker.files(under: root.appendingPathComponent("agents")) { $0.pathExtension == "md" }.count
        let commands = context.walker.files(under: root.appendingPathComponent("commands")) { $0.pathExtension == "md" }.count
        let hasHooks = context.reader.isFile(root.appendingPathComponent("hooks/hooks.json")) || manifest["hooks"] != nil
        let servers = MCPScanner.pluginServerDefinitions(root: root, manifest: manifest, reader: context.reader).count

        var parts: [String] = []
        if skills > 0 { parts.append("\(skills) skill\(skills == 1 ? "" : "s")") }
        if commands > 0 { parts.append("\(commands) command\(commands == 1 ? "" : "s")") }
        if agents > 0 { parts.append("\(agents) agent\(agents == 1 ? "" : "s")") }
        if servers > 0 { parts.append("\(servers) MCP server\(servers == 1 ? "" : "s")") }
        if hasHooks { parts.append("hooks") }
        return [Metadatum("Contributes", parts.isEmpty ? "Nothing Strata recognises" : parts.joined(separator: ", "))]
    }

    private static func isReservedOrigin(_ id: String) -> Bool {
        id.hasSuffix("@inline") || id.hasSuffix("@skills-dir") || id.hasSuffix("@synced")
    }

    private static func scope(fromInstallScope scope: String?) -> Scope {
        switch scope {
        case "project": .project
        case "local": .local
        case "managed": .managed
        default: .user
        }
    }
}
