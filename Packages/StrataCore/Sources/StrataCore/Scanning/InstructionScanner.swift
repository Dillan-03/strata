import Foundation

/// Finds CLAUDE.md, CLAUDE.local.md, rules, AGENTS.md and their `@imports`, in the order Claude Code reads them.
struct InstructionScanner {
    /// The documented values of the "Project instructions" setting.
    enum InstructionMode: String {
        case claudeMDOrAgentsMD = "claude-md-or-agents-md"
        case claudeMDAndAgentsMD = "claude-md-and-agents-md"
        case claudeMDOnly = "claude-md"
        case managedOnly = "managed-only"
    }

    static let maximumImportHops = 4

    let context: ScanContext
    let layers: [SettingsLayer]

    private struct Candidate {
        enum Role {
            case claudeMD
            case localNotes
            case rule
            case agentsMD
        }

        let url: URL
        let scope: Scope
        let role: Role
        let timing: LoadTiming
        let directory: URL
    }

    func scan() -> [ConfigItem] {
        let mode = instructionMode()
        let excludes = exclusionPatterns()
        let candidates = discoverCandidates().filter { context.reader.isFile($0.url) }

        let directoriesWithClaudeMD = Set(candidates.filter { $0.role != .rule && $0.role != .agentsMD }.map { $0.directory.path })
        let launchHasClaudeMD = candidates.contains {
            ($0.role == .claudeMD || $0.role == .localNotes) && ($0.scope == .project || $0.scope == .local || $0.scope == .ancestor)
        }

        var items: [ConfigItem] = []
        var order = 0
        var importedPaths: Set<String> = []

        for candidate in candidates {
            let document = context.readDocument(candidate.url, label: Self.label(for: candidate.role))
            let frontmatter = document?.frontmatter ?? .empty
            var timing = candidate.timing
            var metadata = [Metadatum("Type", Self.label(for: candidate.role))]
            if candidate.role == .rule, let paths = frontmatter.list("paths"), !paths.isEmpty {
                timing = .pathGated
                metadata.append(Metadatum("Applies to", paths.joined(separator: ", ")))
            }
            if let body = document?.body {
                metadata.append(Metadatum("Lines", "\(body.components(separatedBy: "\n").count)"))
            }

            var item = ConfigItem(
                kind: .instruction,
                name: context.displayPath(candidate.url),
                summary: Self.firstHeading(in: document?.body),
                scope: candidate.scope,
                source: SourceLocation(path: candidate.url.path),
                metadata: metadata,
                loadTiming: timing,
                loadOrder: order
            )
            order += 1

            applyMode(mode, to: &item, candidate: candidate, launchHasClaudeMD: launchHasClaudeMD, directoriesWithClaudeMD: directoriesWithClaudeMD)
            if item.inactiveReason == nil, candidate.scope != .managed, let pattern = excludes.first(where: { $0.matches(candidate.url, reader: context.reader) }) {
                item.inactiveReason = "Excluded by the `claudeMdExcludes` pattern `\(pattern.text)` in \(pattern.layer)."
            }
            if timing == .onDemand, item.inactiveReason == nil, item.condition == nil {
                item.condition = "Loads once Claude reads or edits a file in \(context.displayPath(candidate.directory))/."
            }
            if timing == .pathGated, item.inactiveReason == nil {
                item.condition = "Loads when Claude works with files matching its `paths`."
            }

            items.append(item)
            if item.inactiveReason == nil, let body = document?.body {
                let step = ImportStep(file: candidate.url, parent: item, hop: 1, chain: [context.reader.canonical(candidate.url).path])
                items += imports(in: body, step: step, order: &order, seen: &importedPaths)
            }
        }
        return items
    }

    // MARK: - Discovery

    private func discoverCandidates() -> [Candidate] {
        var candidates: [Candidate] = []
        let home = context.environment.homeDirectory.standardizedFileURL.path

        if let managed = context.managedDirectory {
            candidates.append(Candidate(url: managed.appendingPathComponent("CLAUDE.md"), scope: .managed, role: .claudeMD, timing: .atLaunch, directory: managed))
        }
        let claude = context.claudeDirectory
        candidates.append(Candidate(url: claude.appendingPathComponent("CLAUDE.md"), scope: .user, role: .claudeMD, timing: .atLaunch, directory: claude))
        candidates += rules(in: claude.appendingPathComponent("rules"), scope: .user, directory: claude)

        for directory in ancestors(of: context.repository) {
            candidates.append(Candidate(url: directory.appendingPathComponent("CLAUDE.md"), scope: .ancestor, role: .claudeMD, timing: .atLaunch, directory: directory))
            if directory.standardizedFileURL.path != home {
                candidates.append(Candidate(url: directory.appendingPathComponent(".claude/CLAUDE.md"), scope: .ancestor, role: .claudeMD, timing: .atLaunch, directory: directory))
            }
            candidates.append(Candidate(url: directory.appendingPathComponent("CLAUDE.local.md"), scope: .ancestor, role: .localNotes, timing: .atLaunch, directory: directory))
            candidates.append(Candidate(url: directory.appendingPathComponent("AGENTS.md"), scope: .ancestor, role: .agentsMD, timing: .atLaunch, directory: directory))
            if directory.standardizedFileURL.path != home {
                candidates.append(Candidate(url: directory.appendingPathComponent(".claude/AGENTS.md"), scope: .ancestor, role: .agentsMD, timing: .atLaunch, directory: directory))
            }
        }

        let repository = context.repository
        candidates.append(Candidate(url: repository.appendingPathComponent("CLAUDE.md"), scope: .project, role: .claudeMD, timing: .atLaunch, directory: repository))
        candidates.append(Candidate(url: repository.appendingPathComponent(".claude/CLAUDE.md"), scope: .project, role: .claudeMD, timing: .atLaunch, directory: repository))
        candidates.append(Candidate(url: repository.appendingPathComponent("CLAUDE.local.md"), scope: .local, role: .localNotes, timing: .atLaunch, directory: repository))
        candidates += rules(in: repository.appendingPathComponent(".claude/rules"), scope: .project, directory: repository)
        candidates.append(Candidate(url: repository.appendingPathComponent("AGENTS.md"), scope: .project, role: .agentsMD, timing: .atLaunch, directory: repository))
        candidates.append(Candidate(url: repository.appendingPathComponent(".claude/AGENTS.md"), scope: .project, role: .agentsMD, timing: .atLaunch, directory: repository))

        let depth = context.environment.nestedSearchDepth
        let nestedFiles = context.walker.nestedFiles(named: ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md"], under: repository, maxDepth: depth)
        let nestedClaudeFolders = context.walker.directories(named: ".claude", under: repository, maxDepth: depth)
        var nested: [Candidate] = nestedFiles.map { file in
            let role: Candidate.Role = switch file.lastPathComponent {
            case "CLAUDE.local.md": .localNotes
            case "AGENTS.md": .agentsMD
            default: .claudeMD
            }
            return Candidate(url: file, scope: .nested, role: role, timing: .onDemand, directory: file.deletingLastPathComponent())
        }
        for folder in nestedClaudeFolders {
            let owner = folder.deletingLastPathComponent()
            nested.append(Candidate(url: folder.appendingPathComponent("CLAUDE.md"), scope: .nested, role: .claudeMD, timing: .onDemand, directory: owner))
            nested += rules(in: folder.appendingPathComponent("rules"), scope: .nested, directory: owner).map {
                Candidate(url: $0.url, scope: .nested, role: .rule, timing: .onDemand, directory: owner)
            }
        }
        candidates += nested.sorted { $0.url.path < $1.url.path }
        return candidates
    }

    private func rules(in directory: URL, scope: Scope, directory owner: URL) -> [Candidate] {
        guard context.reader.isDirectory(directory) else { return [] }
        context.record("\(scope.title) rules", directory, .found)
        return context.walker.files(under: directory) { $0.pathExtension.lowercased() == "md" }.map {
            Candidate(url: $0, scope: scope, role: .rule, timing: .atLaunch, directory: owner)
        }
    }

    /// Directories above the repository, from the filesystem root down.
    private func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL.deletingLastPathComponent()
        while true {
            result.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path || current.path == "/" { break }
            current = parent
        }
        return result.reversed()
    }

    // MARK: - Modes and exclusions

    private func applyMode(_ mode: InstructionMode, to item: inout ConfigItem, candidate: Candidate, launchHasClaudeMD: Bool, directoriesWithClaudeMD: Set<String>) {
        if mode == .managedOnly, candidate.scope != .managed, candidate.timing == .atLaunch, candidate.role != .rule || item.loadTiming != .pathGated {
            item.inactiveReason = "The Project instructions setting is `managed-only`, so only your organisation's CLAUDE.md loads at launch."
            return
        }
        guard candidate.role == .agentsMD else { return }

        switch mode {
        case .claudeMDOnly:
            item.inactiveReason = "The Project instructions setting is `claude-md`, so AGENTS.md files are ignored."
        case .claudeMDAndAgentsMD:
            item.metadata.append(Metadatum("Why it loads", "Project instructions is set to `claude-md-and-agents-md`"))
        case .claudeMDOrAgentsMD:
            if candidate.scope == .nested {
                if directoriesWithClaudeMD.contains(candidate.directory.path) {
                    item.inactiveReason = "This folder also has a CLAUDE.md, which Claude Code reads instead."
                } else if launchHasClaudeMD {
                    item.inactiveReason = "A CLAUDE.md exists at or above the repository root, so Claude Code reads CLAUDE.md files instead of AGENTS.md."
                }
            } else if launchHasClaudeMD {
                item.inactiveReason = "A CLAUDE.md or CLAUDE.local.md exists at or above the repository root, so Claude Code reads that instead of AGENTS.md."
                context.report(Diagnostic(
                    severity: .info,
                    code: .agentsMDIgnored,
                    title: "\(item.name) is ignored",
                    detail: "By default Claude Code reads AGENTS.md only when there's no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in the working directory or above it.",
                    suggestion: "Import it from CLAUDE.md with `@AGENTS.md`, or set Project instructions to `claude-md-and-agents-md` in `/config`.",
                    paths: [candidate.url.path],
                    itemIDs: [item.id]
                ))
            }
        case .managedOnly:
            item.inactiveReason = "The Project instructions setting is `managed-only`, so every AGENTS.md is left out."
        }
    }

    /// The Project instructions setting. Claude Code reads it from user and managed settings only.
    private func instructionMode() -> InstructionMode {
        for layer in layers.sorted(by: { $0.precedence < $1.precedence }) where layer.scope == .managed || layer.scope == .user {
            let configs = layer.dictionary("pluginConfigs")
            for id in ["cc-plugin-agents-md@builtin", "agents-md@builtin"] {
                let options = (configs?[id] as? [String: Any])?["options"] as? [String: Any]
                if let raw = options?["instructionFiles"] as? String, let mode = InstructionMode(rawValue: raw) {
                    return mode
                }
            }
        }
        return .claudeMDOrAgentsMD
    }

    private struct ExclusionPattern {
        let text: String
        let layer: String
        let expression: NSRegularExpression

        func matches(_ url: URL, reader: FileReader) -> Bool {
            [url.standardizedFileURL.path, reader.canonical(url).path].contains { path in
                expression.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
            }
        }
    }

    private func exclusionPatterns() -> [ExclusionPattern] {
        layers.flatMap { layer in
            (layer.strings("claudeMdExcludes") ?? []).compactMap { pattern in
                guard let expression = Self.globExpression(pattern, home: context.environment.homeDirectory.path) else { return nil }
                return ExclusionPattern(text: pattern, layer: layer.label, expression: expression)
            }
        }
    }

    /// Converts a glob matched against absolute paths into a regular expression.
    static func globExpression(_ glob: String, home: String) -> NSRegularExpression? {
        var pattern = glob.hasPrefix("~/") ? home + glob.dropFirst(1) : glob
        if !pattern.hasPrefix("/") && !pattern.hasPrefix("**") {
            pattern = "**/" + pattern
        }
        var regex = "^"
        var characters = Array(pattern)[...]
        while let character = characters.popFirst() {
            switch character {
            case "*":
                if characters.first == "*" {
                    characters.removeFirst()
                    if characters.first == "/" {
                        characters.removeFirst()
                        regex += "(?:.*/)?"
                    } else {
                        regex += ".*"
                    }
                } else {
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return try? NSRegularExpression(pattern: regex + "$")
    }

    // MARK: - Imports

    /// Where an import walk is: the importing file, its item, how many hops deep, and the files already on this chain.
    private struct ImportStep {
        let file: URL
        let parent: ConfigItem
        let hop: Int
        let chain: [String]
    }

    private func imports(in body: String, step: ImportStep, order: inout Int, seen: inout Set<String>) -> [ConfigItem] {
        let (file, parent, hop, chain) = (step.file, step.parent, step.hop, step.chain)
        var results: [ConfigItem] = []
        for path in ImportParser.imports(in: body) {
            let target = ImportParser.resolve(path, from: file, home: context.environment.homeDirectory)
            let canonical = context.reader.canonical(target).path
            guard !chain.contains(canonical) else { continue }

            guard context.reader.isFile(target) else {
                let isPath = ImportParser.looksLikeFilePath(path)
                context.report(Diagnostic(
                    severity: isPath ? .warning : .info,
                    code: .missingImport,
                    title: "\(parent.name) imports @\(path), which doesn't exist",
                    detail: isPath
                        ? "The import resolves to \(context.displayPath(target)), relative to the file that contains it."
                        : "`@\(path)` reads as an import. If it's a mention rather than a file, wrap it in backticks to keep it literal.",
                    suggestion: isPath ? "Fix the path or remove the import." : "Write `` `@\(path)` `` to stop Claude Code treating it as an import.",
                    paths: [file.path],
                    itemIDs: [parent.id]
                ))
                continue
            }
            guard hop <= Self.maximumImportHops else {
                context.report(Diagnostic(
                    severity: .warning,
                    code: .importDepthExceeded,
                    title: "@\(path) is more than \(Self.maximumImportHops) imports deep",
                    detail: "Claude Code follows imports at most \(Self.maximumImportHops) hops, so \(context.displayPath(target)) isn't loaded through this chain.",
                    suggestion: "Import it from a file closer to the top-level CLAUDE.md.",
                    paths: [file.path, target.path],
                    itemIDs: [parent.id]
                ))
                continue
            }
            guard seen.insert(canonical + "|" + parent.scope.rawValue).inserted else { continue }

            let document = context.readDocument(target, label: "Imported instructions")
            var item = ConfigItem(
                kind: .instruction,
                name: context.displayPath(target),
                summary: Self.firstHeading(in: document?.body),
                scope: parent.scope,
                source: SourceLocation(path: target.path, keyPath: "import from \(parent.source.path)"),
                origin: parent.name,
                metadata: [Metadatum("Type", "Import"), Metadatum("Imported by", parent.name), Metadatum("Import depth", "\(hop)")],
                loadTiming: parent.loadTiming,
                loadOrder: order
            )
            order += 1

            let externalScopes: Set<Scope> = [.project, .local, .nested, .ancestor]
            if externalScopes.contains(parent.scope), !context.isInsideRepository(target) {
                item.condition = "This import points outside the repository. "
                    + "Claude Code asks you to approve external imports the first time it sees them, and skips them if you decline."
                context.report(Diagnostic(
                    severity: .info,
                    code: .externalImport,
                    title: "\(parent.name) imports a file outside the repository",
                    detail: "@\(path) resolves to \(context.displayPath(target)). Claude Code shows a one-time approval dialog for external imports in project files.",
                    paths: [file.path, target.path],
                    itemIDs: [item.id]
                ))
            } else {
                item.condition = parent.condition
            }
            results.append(item)
            if let body = document?.body {
                let next = ImportStep(file: target, parent: item, hop: hop + 1, chain: chain + [canonical])
                results += imports(in: body, step: next, order: &order, seen: &seen)
            }
        }
        return results
    }

    // MARK: - Helpers

    private static func label(for role: Candidate.Role) -> String {
        switch role {
        case .claudeMD: "CLAUDE.md"
        case .localNotes: "CLAUDE.local.md (personal)"
        case .rule: "Rule"
        case .agentsMD: "AGENTS.md"
        }
    }

    private static func firstHeading(in body: String?) -> String? {
        guard let body else { return nil }
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { return heading }
            }
        }
        return nil
    }
}
