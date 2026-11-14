import Foundation

/// Finds subagent definitions (`agents/**/*.md`). Identity comes from the frontmatter `name`, not the file name.
struct AgentScanner {
    let context: ScanContext
    let plugins: [PluginRecord]

    func scan() -> [ConfigItem] {
        var items: [ConfigItem] = []
        if let managed = context.managedDirectory {
            items += agents(in: managed.appendingPathComponent(".claude/agents"), scope: .managed, label: "Managed subagents")
        }
        items += agents(in: context.repositoryClaudeDirectory.appendingPathComponent("agents"), scope: .project, label: "Project subagents")
        items += agents(in: context.claudeDirectory.appendingPathComponent("agents"), scope: .user, label: "User subagents")
        for plugin in plugins {
            guard let root = plugin.root else { continue }
            items += agents(in: root.appendingPathComponent("agents"), scope: .plugin, label: "Plugin subagents", plugin: plugin)
        }
        return items
    }

    private func agents(in directory: URL, scope: Scope, label: String, plugin: PluginRecord? = nil) -> [ConfigItem] {
        guard context.reader.isDirectory(directory) else { return [] }
        context.record(label, directory, .found)
        let root = directory.standardizedFileURL.path

        return context.walker.files(under: directory) { $0.pathExtension.lowercased() == "md" }.map { file in
            let frontmatter = context.readDocument(file, label: "Subagent")?.frontmatter ?? .empty
            let fileName = file.deletingPathExtension().lastPathComponent
            let declaredName = frontmatter.string("name")
            let name = declaredName ?? fileName

            var invocation: String?
            if let plugin {
                let relative = String(file.deletingLastPathComponent().standardizedFileURL.path.dropFirst(root.count))
                let folders = relative.split(separator: "/").map(String.init)
                invocation = ([plugin.namespace] + folders + [name]).joined(separator: ":")
            }

            var metadata: [Metadatum] = []
            if let invocation { metadata.append(Metadatum("Scoped name", invocation)) }
            if let tools = frontmatter.list("tools") { metadata.append(Metadatum("Tools", tools.joined(separator: ", "))) }
            if let tools = frontmatter.list("disallowedTools") { metadata.append(Metadatum("Disallowed tools", tools.joined(separator: ", "))) }
            if let model = frontmatter.string("model") { metadata.append(Metadatum("Model", model)) }
            if let mode = frontmatter.string("permissionMode") { metadata.append(Metadatum("Permission mode", mode)) }
            if let skills = frontmatter.list("skills") { metadata.append(Metadatum("Skills", skills.joined(separator: ", "))) }
            if let memory = frontmatter.string("memory") { metadata.append(Metadatum("Memory", memory)) }
            if let isolation = frontmatter.string("isolation") { metadata.append(Metadatum("Isolation", isolation)) }
            if let color = frontmatter.string("color") { metadata.append(Metadatum("Colour", color)) }
            if frontmatter.bool("omitClaudeMd") == true { metadata.append(Metadatum("CLAUDE.md", "Not loaded for this agent")) }

            var blocker: String?
            var code: Diagnostic.Code = .missingRequiredField
            if declaredName == nil {
                blocker = "No `name` in the frontmatter. Claude Code identifies subagents by `name`, so this file isn't registered."
            } else if frontmatter.string("description") == nil {
                blocker = "No `description` in the frontmatter. It's required so Claude knows when to delegate."
            } else if name.contains(":") {
                blocker = "Names can't contain `:`, which is reserved for plugin-scoped names."
                code = .invalidName
            }

            var item = ConfigItem(
                kind: .agent,
                name: name,
                invocation: invocation,
                summary: frontmatter.string("description"),
                scope: scope,
                source: SourceLocation(path: file.path),
                origin: plugin?.id,
                metadata: metadata,
                loadTiming: .whenInvoked,
                loadBlocker: blocker
            )
            if let plugin, plugin.enabled == false {
                item.inactiveReason = "The plugin \(plugin.id) is turned off."
            }
            if let blocker {
                context.report(Diagnostic(
                    severity: .warning,
                    code: code,
                    title: "\(context.displayPath(file)) isn't a valid subagent",
                    detail: blocker,
                    suggestion: "Add the missing frontmatter field.",
                    paths: [file.path],
                    itemIDs: [item.id]
                ))
            }
            return item
        }
    }
}
