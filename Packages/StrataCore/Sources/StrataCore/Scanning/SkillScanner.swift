import Foundation

/// Finds skills (`skills/<name>/SKILL.md`) and legacy command files (`commands/**/*.md`).
struct SkillScanner {
    let context: ScanContext
    let plugins: [PluginRecord]

    func scan() -> [ConfigItem] {
        var items: [ConfigItem] = []
        if let managed = context.managedDirectory {
            items += skills(in: managed.appendingPathComponent(".claude/skills"), scope: .managed, label: "Managed skills")
        }
        items += skills(in: context.claudeDirectory.appendingPathComponent("skills"), scope: .user, label: "Personal skills")
        items += syncedSkills(in: context.claudeDirectory.appendingPathComponent("skills/synced"))
        items += skills(in: context.repositoryClaudeDirectory.appendingPathComponent("skills"), scope: .project, label: "Project skills")

        for nested in context.walker.directories(named: ".claude", under: context.repository, maxDepth: context.environment.nestedSearchDepth) {
            let subdirectory = context.displayPath(nested.deletingLastPathComponent())
            items += skills(in: nested.appendingPathComponent("skills"), scope: .nested, label: "Nested skills", nestedIn: subdirectory)
        }

        items += commands(in: context.claudeDirectory.appendingPathComponent("commands"), scope: .user)
        items += commands(in: context.repositoryClaudeDirectory.appendingPathComponent("commands"), scope: .project)

        for plugin in plugins {
            guard let root = plugin.root else { continue }
            var pluginItems = skills(in: root.appendingPathComponent("skills"), scope: .plugin, label: "Plugin skills", plugin: plugin)
            let rootSkill = root.appendingPathComponent("SKILL.md")
            if context.reader.isFile(rootSkill) {
                pluginItems += [skill(file: rootSkill, folderName: root.lastPathComponent, scope: .plugin, plugin: plugin)]
            }
            pluginItems += commands(in: root.appendingPathComponent("commands"), scope: .plugin, plugin: plugin)
            items += pluginItems.map { applyPluginState(plugin, to: $0) }
        }
        return items
    }

    // MARK: - Skills

    private func skills(in directory: URL, scope: Scope, label: String, nestedIn subdirectory: String? = nil, plugin: PluginRecord? = nil) -> [ConfigItem] {
        guard context.reader.isDirectory(directory) else { return [] }
        context.record(label, directory, .found)

        return context.walker.children(of: directory).compactMap { entry -> ConfigItem? in
            let name = entry.lastPathComponent
            if scope == .user, name == "synced" { return nil }
            if name.hasPrefix(".") { return nil }

            if context.reader.isDirectory(entry) {
                let file = entry.appendingPathComponent("SKILL.md")
                guard context.reader.isFile(file) else {
                    let item = ConfigItem(
                        kind: .skill,
                        name: name,
                        invocation: "/\(name)",
                        scope: scope,
                        source: SourceLocation(path: entry.path),
                        origin: plugin?.id ?? subdirectory,
                        loadBlocker: "The folder has no SKILL.md, so Claude Code doesn't load it."
                    )
                    context.report(Diagnostic(
                        severity: .warning,
                        code: .skillMissingDefinition,
                        title: "\(name) has no SKILL.md",
                        detail: "Every skill folder needs a `SKILL.md` file. Without it Claude Code skips the folder.",
                        suggestion: "Add `\(context.displayPath(entry))/SKILL.md`, or remove the folder.",
                        paths: [entry.path],
                        itemIDs: [item.id]
                    ))
                    return item
                }
                return skill(file: file, folderName: name, scope: scope, nestedIn: subdirectory, plugin: plugin)
            }

            guard entry.pathExtension.lowercased() == "md" else { return nil }
            let bareName = entry.deletingPathExtension().lastPathComponent
            let item = ConfigItem(
                kind: .skill,
                name: bareName,
                invocation: "/\(bareName)",
                scope: scope,
                source: SourceLocation(path: entry.path),
                origin: plugin?.id ?? subdirectory,
                loadBlocker: "Skills must be a folder containing SKILL.md. A bare .md file in skills/ doesn't load."
            )
            context.report(Diagnostic(
                severity: .warning,
                code: .skillNotInFolder,
                title: "\(entry.lastPathComponent) won't load as a skill",
                detail: "Claude Code only loads skills from `skills/<name>/SKILL.md`. This file sits directly in `skills/`.",
                suggestion: "Move it to `\(context.displayPath(directory))/\(bareName)/SKILL.md`, or to `commands/\(entry.lastPathComponent)` to keep it as a command.",
                paths: [entry.path],
                itemIDs: [item.id]
            ))
            return item
        }
    }

    /// claude.ai skills are downloaded one folder deeper than personal skills, so look for SKILL.md files directly.
    private func syncedSkills(in directory: URL) -> [ConfigItem] {
        guard context.reader.isDirectory(directory) else { return [] }
        context.record("Skills synced from claude.ai", directory, .found)
        return context.walker.files(under: directory, maxDepth: 3) { $0.lastPathComponent == "SKILL.md" }.map { file in
            skill(file: file, folderName: file.deletingLastPathComponent().lastPathComponent, scope: .synced)
        }
    }

    private func skill(file: URL, folderName: String, scope: Scope, nestedIn subdirectory: String? = nil, plugin: PluginRecord? = nil) -> ConfigItem {
        let document = context.readDocument(file, label: "Skill")
        let frontmatter = document?.frontmatter ?? .empty
        let declaredName = frontmatter.string("name")
        let baseName = declaredName ?? folderName

        let identity: String
        if let plugin {
            let prefix = plugin.namespace + ":"
            identity = baseName.hasPrefix(prefix) ? baseName : prefix + baseName
        } else {
            identity = baseName
        }

        var metadata = Self.commonMetadata(frontmatter)
        if declaredName != nil, declaredName != folderName, plugin == nil {
            metadata.insert(Metadatum("Folder name", "\(folderName) (also invokes the skill)"), at: 0)
        }
        let folder = file.deletingLastPathComponent()
        let canonicalFolder = context.reader.canonical(folder)
        if canonicalFolder.path != folder.standardizedFileURL.path {
            metadata.append(Metadatum("Linked from", canonicalFolder.path))
        }
        if context.reader.isFile(folder.appendingPathComponent(".claude-plugin/plugin.json")) {
            metadata.append(Metadatum("Also a plugin", "This folder has a plugin manifest, so it also loads as a plugin"))
        }

        var blocker: String?
        if plugin == nil {
            if folderName.lowercased() == "synced", scope != .synced {
                blocker = "`synced` is reserved for skills downloaded from claude.ai, so Claude Code skips a skill folder with that name."
            } else if folderName == "anthropic-skills" || folderName.hasPrefix("anthropic-skills:") {
                blocker = "Names starting with `anthropic-skills` are reserved, so this skill doesn't load."
            } else if folderName.unicodeScalars.contains(where: Self.isDisallowed) {
                blocker = "The folder name contains a character Claude Code doesn't allow in skill names."
            }
        }

        let item = ConfigItem(
            kind: .skill,
            name: identity,
            invocation: "/\(identity)",
            summary: frontmatter.string("description"),
            scope: scope,
            source: SourceLocation(path: file.path),
            origin: plugin?.id ?? subdirectory,
            metadata: metadata,
            loadTiming: scope == .nested ? .onDemand : .whenInvoked,
            loadBlocker: blocker,
            condition: subdirectory.map { "Loads the first time Claude reads or edits a file in \($0)/, or straight away if you run `/add-dir \($0)`." },
            matchKey: canonicalFolder.path
        )
        if let blocker {
            context.report(Diagnostic(
                severity: .warning,
                code: .reservedName,
                title: "\(folderName) uses a reserved or invalid name",
                detail: blocker,
                suggestion: "Rename the folder.",
                paths: [folder.path],
                itemIDs: [item.id]
            ))
        }
        return item
    }

    // MARK: - Commands

    private func commands(in directory: URL, scope: Scope, plugin: PluginRecord? = nil) -> [ConfigItem] {
        guard context.reader.isDirectory(directory) else { return [] }
        context.record(scope == .plugin ? "Plugin commands" : "\(scope.title) commands", directory, .found)
        let root = directory.standardizedFileURL.path
        return context.walker.files(under: directory) { $0.pathExtension.lowercased() == "md" }.map { file in
            let relative = String(file.standardizedFileURL.path.dropFirst(root.count + 1))
            let commandName = (relative as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: ":")
            let identity = plugin.map { "\($0.namespace):\(commandName)" } ?? commandName
            let frontmatter = context.readDocument(file, label: "Command")?.frontmatter ?? .empty
            return ConfigItem(
                kind: .command,
                name: identity,
                invocation: "/\(identity)",
                summary: frontmatter.string("description"),
                scope: scope,
                source: SourceLocation(path: file.path),
                origin: plugin?.id,
                metadata: Self.commonMetadata(frontmatter),
                loadTiming: .whenInvoked
            )
        }
    }

    // MARK: - Helpers

    private func applyPluginState(_ plugin: PluginRecord, to item: ConfigItem) -> ConfigItem {
        var item = item
        if plugin.enabled == false {
            item.inactiveReason = "The plugin \(plugin.id) is turned off."
        } else if plugin.needsTrust, item.condition == nil {
            item.condition = "Enabled by the repository, so it loads only after you accept the workspace trust prompt."
        }
        return item
    }

    static func commonMetadata(_ frontmatter: Frontmatter) -> [Metadatum] {
        var metadata: [Metadatum] = []
        if let value = frontmatter.string("when_to_use") { metadata.append(Metadatum("When to use", value)) }
        if let value = frontmatter.string("argument-hint") { metadata.append(Metadatum("Arguments", value)) }
        if let value = frontmatter.string("model") { metadata.append(Metadatum("Model", value)) }
        if let value = frontmatter.string("effort") { metadata.append(Metadatum("Effort", value)) }
        if let value = frontmatter.list("allowed-tools") { metadata.append(Metadatum("Allowed tools", value.joined(separator: ", "))) }
        if let value = frontmatter.list("disallowed-tools") { metadata.append(Metadatum("Disallowed tools", value.joined(separator: ", "))) }
        if let value = frontmatter.list("paths") { metadata.append(Metadatum("Activates for paths", value.joined(separator: ", "))) }
        if let value = frontmatter.string("context") { metadata.append(Metadatum("Context", value)) }
        if let value = frontmatter.string("agent") { metadata.append(Metadatum("Runs as agent", value)) }
        if frontmatter.bool("disable-model-invocation") == true {
            metadata.append(Metadatum("Started by", "Only you (Claude won't invoke it on its own)"))
        } else if frontmatter.bool("user-invocable") == false {
            metadata.append(Metadatum("Started by", "Only Claude (hidden from the / menu)"))
        } else {
            metadata.append(Metadatum("Started by", "You or Claude"))
        }
        return metadata
    }

    private static func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "<" || scalar == ">" || scalar.properties.generalCategory == .format || scalar.properties.generalCategory == .control
    }
}
