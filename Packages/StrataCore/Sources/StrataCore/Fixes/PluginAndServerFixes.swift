import Foundation

/// Turning plugins off and on, and removing MCP servers. Both edit one entry in a JSON file and leave the rest as it was.
extension FixPlanner {
    /// The single files outside `allowedRoots` Strata may edit: `~/.claude.json` and the repository's `.mcp.json`.
    public static func allowedFiles(repositoryPath: String, environment: ScanEnvironment) -> [URL] {
        [
            environment.globalConfigFile.standardizedFileURL,
            URL(fileURLWithPath: repositoryPath, isDirectory: true).appendingPathComponent(".mcp.json").standardizedFileURL,
        ]
    }

    /// Everything Strata can change about an item: uninstall a skill, command or subagent, toggle a plugin, or remove an MCP server.
    public static func change(
        for item: ConfigItem,
        in report: InspectionReport,
        environment: ScanEnvironment,
        fileManager: FileManager = .default
    ) -> FixOffer {
        switch item.kind {
        case .skill, .command, .agent: uninstall(item, in: report, environment: environment, fileManager: fileManager)
        case .plugin: toggle(item, in: report, environment: environment, fileManager: fileManager)
        case .mcpServer: removeServer(item, in: report, environment: environment, fileManager: fileManager)
        default: .none
        }
    }

    /// Turns a plugin off, or back on, by flipping its `enabledPlugins` entry in the settings file that decides it.
    public static func toggle(
        _ plugin: ConfigItem,
        in report: InspectionReport,
        environment: ScanEnvironment,
        fileManager: FileManager = .default
    ) -> FixOffer {
        guard plugin.kind == .plugin else { return .none }
        guard plugin.source.keyPath == "enabledPlugins.\(plugin.name)" else {
            return .unavailable(
                "No settings file turns \(plugin.name) on or off, so there's no entry for Strata to change. "
                    + "Run \(command("disable", plugin: plugin.name)) in Terminal instead."
            )
        }
        guard plugin.scope != .managed else {
            return .unavailable("Your organisation sets this plugin in managed settings, so Strata won't change it.")
        }
        let path = ["enabledPlugins", plugin.name]
        let roots = allowedRoots(repositoryPath: report.repositoryPath, environment: environment)
        switch editableFile(plugin.source.url, path: path, roots: roots, files: [], fileManager: fileManager) {
        case .failure(let refusal):
            return .unavailable(refusal.reason)
        case .success(let file):
            guard file.value == "true" || file.value == "false" else {
                return .unavailable("Its enabledPlugins entry is \(file.value), not true or false, so Strata won't guess what to write.")
            }
            let disabling = file.value == "true"
            return .available([ConfigFix(
                action: disabling ? .disablePlugin : .enablePlugin, target: plugin, winner: nil, overridden: [],
                pickup: ChangeDetector.pickup(.updated, plugin, old: report), targetURL: file.url, sourceURL: nil,
                targetFingerprint: file.fingerprint, sourceFingerprint: nil, jsonPath: path, newValue: disabling ? "false" : "true"
            )])
        }
    }

    /// Removes an MCP server's entry from `.mcp.json` or `~/.claude.json`. Strata never starts or contacts the server.
    public static func removeServer(
        _ server: ConfigItem,
        in report: InspectionReport,
        environment: ScanEnvironment,
        fileManager: FileManager = .default
    ) -> FixOffer {
        guard server.kind == .mcpServer else { return .none }
        let file = server.source.url.standardizedFileURL
        let path: [String]
        switch server.scope {
        case .user, .project:
            path = ["mcpServers", server.name]
        case .local:
            guard let key = projectKey(in: file, repositoryPath: report.repositoryPath) else {
                return .unavailable("Strata couldn't find this repository's entry in \(file.lastPathComponent).")
            }
            path = ["projects", key, "mcpServers", server.name]
        case .plugin:
            let plugin = server.origin.map { "the \($0) plugin" } ?? "a plugin"
            return .unavailable("This server comes from \(plugin). Turn the plugin off or uninstall it instead.")
        case .managed:
            return .unavailable("Your organisation deploys this server through managed settings, so Strata won't change it.")
        case .nested, .ancestor, .synced:
            return .unavailable("Strata only removes servers from .mcp.json and ~/.claude.json.")
        }
        let files = allowedFiles(repositoryPath: report.repositoryPath, environment: environment)
        switch editableFile(file, path: path, roots: [], files: files, fileManager: fileManager) {
        case .failure(let refusal):
            return .unavailable(refusal.reason)
        case .success(let editable):
            return .available([ConfigFix(
                action: .removeServer, target: server, winner: nil, overridden: [],
                pickup: ChangeDetector.pickup(.deleted, server, old: report), targetURL: editable.url, sourceURL: nil,
                targetFingerprint: editable.fingerprint, sourceFingerprint: nil, jsonPath: path, newValue: nil
            )])
        }
    }

    /// The documented command that uninstalls a plugin, for the user to run in Terminal. Strata never runs it.
    public static func uninstallCommand(for plugin: ConfigItem) -> String? {
        guard plugin.kind == .plugin, plugin.stage != .declared else { return nil }
        let scope = plugin.metadataValue("Install scope") ?? "user"
        guard ["user", "project", "local"].contains(scope) else { return nil }
        return command("uninstall", plugin: plugin.name) + " --scope \(scope)"
    }

    static func command(_ verb: String, plugin id: String) -> String {
        "claude plugin \(verb) \(shellQuoted(id))"
    }

    /// Plugin IDs come from files a repository controls, so anything beyond plain ID characters is quoted for the shell.
    static func shellQuoted(_ text: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._-/")
        if !text.isEmpty, text.unicodeScalars.allSatisfy(plain.contains) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    // MARK: - Pieces

    private struct EditableFile {
        let url: URL
        let fingerprint: String
        let value: String
    }

    /// A JSON file Strata may edit, with the entry at `path` present.
    private static func editableFile(_ url: URL, path: [String], roots: [URL], files: [URL], fileManager: FileManager) -> Result<EditableFile, Refusal> {
        let url = url.standardizedFileURL
        if files.contains(url) {
            if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
                return .failure(Refusal(reason: "\(url.lastPathComponent) is a symbolic link. Change the file where it points instead."))
            }
        } else if let root = roots.first(where: { contains($0, url) }) {
            if let link = symbolicLink(between: root, and: url, fileManager: fileManager) {
                return .failure(Refusal(reason: "\(link.lastPathComponent) is a symbolic link. Change the file where it points instead."))
            }
        } else {
            return .failure(Refusal(reason: "Strata only edits settings in ~/.claude or this repository's .claude folder, not \(url.path)."))
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8), let fingerprint = try? Fingerprint.ofTree(url, fileManager: fileManager) else {
            return .failure(Refusal(reason: "Strata couldn't read \(url.lastPathComponent)."))
        }
        guard let value = JSONTextEdit.valueText(at: path, in: text) else {
            return .failure(Refusal(reason: "Strata couldn't find this entry in \(url.lastPathComponent). Rescan and try again."))
        }
        return .success(EditableFile(url: url, fingerprint: fingerprint, value: value))
    }

    /// The key `~/.claude.json` uses for this repository under `projects`, which may be written differently from its path.
    private static func projectKey(in file: URL, repositoryPath: String) -> String? {
        guard let data = try? Data(contentsOf: file),
              let projects = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["projects"] as? [String: Any]
        else { return nil }
        let repository = URL(fileURLWithPath: repositoryPath)
        let targets = [repository.standardizedFileURL.path, repository.resolvingSymlinksInPath().path]
        return projects.keys.sorted().first { key in
            let candidate = URL(fileURLWithPath: key)
            return targets.contains(candidate.standardizedFileURL.path) || targets.contains(candidate.resolvingSymlinksInPath().path)
        }
    }
}
