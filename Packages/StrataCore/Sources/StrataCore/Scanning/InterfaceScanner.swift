import Foundation

/// Output styles, the status line and keybindings: configuration that changes how a session looks and behaves rather than
/// what Claude can do. Each item gets its status here, because none of them compete with other kinds.
struct InterfaceScanner {
    let context: ScanContext
    let layers: [SettingsLayer]
    let plugins: [PluginRecord]

    private enum Docs {
        static let outputStyles = "https://code.claude.com/docs/en/output-styles"
        static let statusLine = "https://code.claude.com/docs/en/statusline"
        static let keybindings = "https://code.claude.com/docs/en/keybindings"
    }

    static let builtInStyles = ["Default", "default", "Proactive", "Concise", "Explanatory", "Learning"]
    /// Claude Code won't let these be rebound.
    static let reservedKeys: Set<String> = ["ctrl+c", "ctrl+d", "ctrl+m", "ctrl+[", "ctrl+i", "ctrl+h", "capslock", "caps lock"]

    func scan() -> [ConfigItem] {
        outputStyles() + statusLines() + keybindings()
    }

    // MARK: - Output styles

    private struct StyleFolder {
        let directory: URL
        let scope: Scope
        var plugin: String?
        var enabled = true
    }

    private func outputStyles() -> [ConfigItem] {
        var sources: [StyleFolder] = []
        if let managed = context.managedDirectory { sources.append(StyleFolder(directory: managed.appendingPathComponent(".claude/output-styles"), scope: .managed)) }
        sources.append(StyleFolder(directory: context.repositoryClaudeDirectory.appendingPathComponent("output-styles"), scope: .project))
        sources.append(StyleFolder(directory: context.claudeDirectory.appendingPathComponent("output-styles"), scope: .user))
        for plugin in plugins {
            guard let root = plugin.root else { continue }
            sources.append(StyleFolder(directory: root.appendingPathComponent("output-styles"), scope: .plugin, plugin: plugin.id, enabled: plugin.enabled == true))
        }

        var items: [ConfigItem] = []
        for folder in sources {
            let (directory, scope, origin, enabled) = (folder.directory, folder.scope, folder.plugin, folder.enabled)
            for file in context.walker.files(under: directory, maxDepth: 1, include: { $0.pathExtension.lowercased() == "md" }) {
                let frontmatter = context.readDocument(file, label: "Output style")?.frontmatter ?? .empty
                let name = frontmatter.string("name") ?? file.deletingPathExtension().lastPathComponent
                var metadata = [Metadatum("File", context.displayPath(file))]
                if let description = frontmatter.string("description") { metadata.append(Metadatum("Description", description)) }
                if frontmatter.bool("keep-coding-instructions") == true { metadata.append(Metadatum("Keeps coding instructions", "Yes")) }
                let forced = scope == .plugin && frontmatter.bool("force-for-plugin") == true
                if forced { metadata.append(Metadatum("Forced by plugin", "Yes")) }
                var item = ConfigItem(
                    kind: .outputStyle, name: name, summary: frontmatter.string("description"), scope: scope,
                    source: SourceLocation(path: file.path), origin: origin, metadata: metadata, loadTiming: .atLaunch
                )
                if !enabled { item.inactiveReason = "The plugin \(origin ?? "") is turned off, so its output styles aren't available." }
                items.append(item)
            }
        }

        // The highest-precedence settings file that sets outputStyle picks the style; a forced plugin style overrides it.
        let chooser = layers.sorted { $0.precedence < $1.precedence }.first { $0.values["outputStyle"] is String }
        let requested = chooser?.values["outputStyle"] as? String
        let forced = items.first { $0.metadataValue("Forced by plugin") == "Yes" && $0.inactiveReason == nil }
        let selectedName = forced?.name ?? requested
        let available = items.filter { $0.inactiveReason == nil }

        if let requested, forced == nil, !Self.builtInStyles.contains(requested), !available.contains(where: { $0.name == requested }),
           let chooser {
            context.report(Diagnostic(
                severity: .warning,
                code: .unknownOutputStyle,
                title: "outputStyle \"\(requested)\" doesn't match any style",
                detail: "Style names are case-sensitive. A value that doesn't match one exactly gives you the Default style.",
                suggestion: "Use the exact name of a built-in or custom style.",
                paths: [chooser.url.path]
            ))
        }

        let sameName = Dictionary(grouping: available, by: \.name).filter { $0.value.count > 1 }
        return items.map { item in
            var item = item
            guard item.inactiveReason == nil else { return item }
            if sameName[item.name] != nil {
                item.applicability = .unknown
                item.explanation = ["Another output style is also called \(item.name), and the Claude Code docs don't say which one wins between these folders."]
            } else if item.name == selectedName {
                item.applicability = .effective
                item.explanation = [forced?.id == item.id
                    ? "Its plugin sets force-for-plugin, which overrides your outputStyle setting."
                    : "Selected by outputStyle in \(chooser?.label ?? "settings")."]
            } else {
                item.applicability = .inactive
                item.explanation = ["Available, but not the selected style. Choose it with /output-style or outputStyle in settings."]
            }
            item.explanation.append("Claude Code reads style files when it starts, so edits need a restart. (\(Docs.outputStyles))")
            return item
        }
    }

    // MARK: - Status line

    private func statusLines() -> [ConfigItem] {
        let ordered = layers.sorted { $0.precedence < $1.precedence }
        let disabledBy = ordered.first { $0.bool("disableAllHooks") != nil }.flatMap { $0.bool("disableAllHooks") == true ? $0 : nil }
        let managedOnly = ordered.first { $0.scope == .managed }?.bool("allowManagedHooksOnly") == true
        var winner: ConfigItem.ID?
        return ordered.compactMap { layer in
            guard let line = layer.dictionary("statusLine") else { return nil }
            let command = SecretRedactor.redactText((line["command"] as? String) ?? "")
            var metadata = [Metadatum("Command", command), Metadatum("File", context.displayPath(layer.url))]
            if let padding = line["padding"] as? NSNumber { metadata.append(Metadatum("Padding", padding.stringValue)) }
            if let interval = line["refreshInterval"] as? NSNumber { metadata.append(Metadatum("Refresh interval", "\(interval.stringValue) s")) }
            var item = ConfigItem(
                kind: .statusLine, name: "Status line", summary: command, scope: layer.scope,
                source: SourceLocation(path: layer.url.path, keyPath: "statusLine"), metadata: metadata, loadTiming: .atLaunch
            )
            if layer.scope != .managed, let disabledBy {
                item.inactiveReason = "`disableAllHooks` is true in \(disabledBy.label), so Claude Code runs only a status line from managed settings."
            } else if layer.scope != .managed, managedOnly {
                item.inactiveReason = "Managed settings set `allowManagedHooksOnly`, so only a status line from managed settings runs."
            } else if let winner {
                item.applicability = .shadowed(by: winner)
                item.explanation = ["A higher-precedence settings file sets statusLine too, and its value wins."]
            } else {
                winner = item.id
                item.applicability = .conditional
                item.explanation = [
                    "Until you accept the workspace trust dialog, the status line stays blank, and Strata can't read whether you have.",
                    "Claude Code reloads settings and runs the new command as soon as you save. (\(Docs.statusLine))",
                ]
            }
            return item
        }
    }

    // MARK: - Keybindings

    private func keybindings() -> [ConfigItem] {
        let file = context.claudeDirectory.appendingPathComponent("keybindings.json")
        guard context.reader.isFile(file), let object = context.readJSON(file, label: "Keybindings") else { return [] }
        var items: [ConfigItem] = []
        for (blockIndex, block) in ((object["bindings"] as? [Any]) ?? []).enumerated() {
            guard let block = block as? [String: Any], let bindings = block["bindings"] as? [String: Any] else { continue }
            let contextName = (block["context"] as? String) ?? "Global"
            for key in bindings.keys.sorted() {
                let action = bindings[key] as? String
                var item = ConfigItem(
                    kind: .keybinding, name: "\(contextName): \(key)",
                    summary: action ?? "Unbinds the default shortcut", scope: .user,
                    source: SourceLocation(path: file.path, keyPath: "bindings.\(blockIndex).\(key)"),
                    metadata: [Metadatum("Context", contextName), Metadatum("Keys", key), Metadatum("Action", action ?? "None (unbound)"),
                               Metadatum("File", context.displayPath(file))],
                    loadTiming: .atLaunch
                )
                if Self.reservedKeys.contains(key.lowercased()) {
                    item.loadBlocker = "Claude Code reserves \(key) and won't let it be rebound."
                } else {
                    item.applicability = .effective
                    item.explanation = ["Claude Code detects changes to keybindings.json and applies them without a restart. (\(Docs.keybindings))"]
                }
                items.append(item)
            }
        }
        return items
    }
}
