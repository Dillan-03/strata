import Foundation

/// A change Strata can make to a skill, command or subagent, but only when the user asks and approves it.
public struct ConfigFix: Hashable, Sendable, Identifiable {
    public enum Action: String, Hashable, Codable, Sendable {
        /// Moves the overridden copy into Strata's backups.
        case removeCopy
        /// Overwrites the overridden copy with the copy that runs, keeping the old one in Strata's backups.
        case replaceWithWinner
        /// Moves a copy nothing overrides into Strata's backups. Overridden copies get `removeCopy` instead.
        case uninstall
        /// Sets a plugin's `enabledPlugins` entry to `false` in the settings file that decides it.
        case disablePlugin
        /// Sets that entry back to `true`.
        case enablePlugin
        /// Removes an MCP server's entry from `.mcp.json` or `~/.claude.json`, leaving the rest of the file as it was.
        case removeServer

        /// Edits one entry inside a JSON file, rather than moving files.
        public var editsJSON: Bool { [.disablePlugin, .enablePlugin, .removeServer].contains(self) }
    }

    public let action: Action
    /// The copy the fix changes.
    public let target: ConfigItem
    /// The copy that runs instead of the target. Nil when the target is the copy that runs.
    public let winner: ConfigItem?
    /// For an uninstall: the copies the target overrides. One of them runs once it's gone.
    public let overridden: [ConfigItem]
    /// When a Claude Code session that's already running stops seeing the target, as the docs describe it.
    public let pickup: SessionPickup
    /// What the fix moves or overwrites: a skill's folder, or a command's or subagent's file.
    public let targetURL: URL
    /// What a replacement copies from: the winner's folder or file.
    public let sourceURL: URL?
    /// Taken when the fix was offered. Applying refuses if either side has changed since.
    let targetFingerprint: String
    let sourceFingerprint: String?
    /// For an edit inside a JSON file: the keys from the root to the entry.
    public internal(set) var jsonPath: [String]?
    /// For a plugin toggle: the JSON value written.
    public internal(set) var newValue: String?

    public var id: String { "\(action.rawValue):\(target.id)" }
}

/// What Strata can do about an item.
public enum FixOffer: Hashable, Sendable {
    /// The item isn't an overridden skill, command or subagent, so there's nothing to fix.
    case none
    /// It is, but Strata won't change it, for the reason given.
    case unavailable(String)
    /// The fixes Strata can make, each still needing the user's approval.
    case available([ConfigFix])
}

/// Works out which fixes Strata offers. It only ever offers to change files in the user's Claude directory or the
/// inspected repository's `.claude` folder, and never through a symbolic link.
public enum FixPlanner {
    public static let fixableKinds: Set<ItemKind> = [.skill, .command, .agent]
    public static let writableScopes: Set<Scope> = [.user, .project]

    public static func offer(
        for item: ConfigItem,
        in report: InspectionReport,
        environment: ScanEnvironment,
        fileManager: FileManager = .default
    ) -> FixOffer {
        guard case .shadowed(let winnerID) = item.applicability,
              fixableKinds.contains(item.kind),
              let winner = report.item(withID: winnerID) else { return .none }

        let roots = allowedRoots(repositoryPath: report.repositoryPath, environment: environment)
        let target: (url: URL, fingerprint: String)
        switch writableUnit(for: item, roots: roots, fileManager: fileManager) {
        case .success(let unit): target = unit
        case .failure(let refusal): return .unavailable(refusal.reason)
        }
        let pickup = ChangeDetector.pickup(.deleted, item, old: report)

        var fixes = [ConfigFix(
            action: .removeCopy, target: item, winner: winner, overridden: [], pickup: pickup, targetURL: target.url,
            sourceURL: nil, targetFingerprint: target.fingerprint, sourceFingerprint: nil
        )]
        if winner.kind == item.kind,
           writableScopes.contains(winner.scope),
           let source = unit(for: winner),
           let sourceRoot = roots.first(where: { contains($0, source) }),
           symbolicLink(between: sourceRoot, and: source, fileManager: fileManager) == nil,
           let sourceFingerprint = try? Fingerprint.ofTree(source, fileManager: fileManager) {
            fixes.append(ConfigFix(
                action: .replaceWithWinner, target: item, winner: winner, overridden: [], pickup: pickup, targetURL: target.url,
                sourceURL: source, targetFingerprint: target.fingerprint, sourceFingerprint: sourceFingerprint
            ))
        }
        return .available(fixes)
    }

    /// Offers to uninstall a skill, command or subagent. An overridden copy gets the Remove fix, which does the same.
    public static func uninstall(
        _ item: ConfigItem,
        in report: InspectionReport,
        environment: ScanEnvironment,
        fileManager: FileManager = .default
    ) -> FixOffer {
        guard fixableKinds.contains(item.kind) else { return .none }
        if case .shadowed = item.applicability {
            guard case .available(let fixes) = offer(for: item, in: report, environment: environment, fileManager: fileManager) else {
                return offer(for: item, in: report, environment: environment, fileManager: fileManager)
            }
            return .available(fixes.filter { $0.action == .removeCopy })
        }
        let roots = allowedRoots(repositoryPath: report.repositoryPath, environment: environment)
        switch writableUnit(for: item, roots: roots, fileManager: fileManager) {
        case .failure(let refusal):
            return .unavailable(refusal.reason)
        case .success(let target):
            let overridden = report.items.filter { $0.applicability == .shadowed(by: item.id) }
            return .available([ConfigFix(
                action: .uninstall, target: item, winner: nil, overridden: overridden,
                pickup: ChangeDetector.pickup(.deleted, item, old: report), targetURL: target.url,
                sourceURL: nil, targetFingerprint: target.fingerprint, sourceFingerprint: nil
            )])
        }
    }

    struct Refusal: Error {
        let reason: String
    }

    /// The file or folder Strata would change for an item, checked against everything it refuses.
    static func writableUnit(for item: ConfigItem, roots: [URL], fileManager: FileManager) -> Result<(url: URL, fingerprint: String), Refusal> {
        switch item.scope {
        case .user, .project:
            break
        case .plugin:
            let plugin = item.origin.map { "the \($0) plugin" } ?? "its plugin"
            return .failure(Refusal(reason: "This comes from \(plugin). Uninstall or disable the plugin instead."))
        case .managed:
            return .failure(Refusal(reason: "Your organisation deploys this through managed settings, so Strata won't change it."))
        case .synced:
            return .failure(Refusal(reason: "This is synced from your claude.ai account. Remove it there."))
        case .local, .nested, .ancestor:
            return .failure(Refusal(
                reason: "Strata only changes copies in ~/.claude or this repository's .claude folder. This one is \(item.scope.title.lowercased())."
            ))
        }
        guard let target = unit(for: item), let root = roots.first(where: { contains($0, target) }) else {
            return .failure(Refusal(reason: "Strata couldn't place this copy inside ~/.claude or the repository's .claude folder."))
        }
        if let link = symbolicLink(between: root, and: target, fileManager: fileManager) {
            return .failure(Refusal(reason: "\(link.lastPathComponent) is a symbolic link. Change the copy where it points instead."))
        }
        guard let fingerprint = try? Fingerprint.ofTree(target, fileManager: fileManager) else {
            return .failure(Refusal(reason: "Strata couldn't read this copy."))
        }
        return .success((target, fingerprint))
    }

    /// The only folders Strata writes in: the user's Claude directory and the inspected repository's `.claude`.
    public static func allowedRoots(repositoryPath: String, environment: ScanEnvironment) -> [URL] {
        [
            environment.claudeDirectory.standardizedFileURL,
            URL(fileURLWithPath: repositoryPath, isDirectory: true).appendingPathComponent(".claude").standardizedFileURL,
        ]
    }

    /// What one item is on disk: a skill is its whole folder, because scripts and references sit beside SKILL.md.
    static func unit(for item: ConfigItem) -> URL? {
        let file = item.source.url.standardizedFileURL
        switch item.kind {
        case .skill: return file.lastPathComponent == "SKILL.md" ? file.deletingLastPathComponent() : nil
        case .command, .agent: return file
        default: return nil
        }
    }

    static func contains(_ root: URL, _ url: URL) -> Bool {
        url.path.hasPrefix(root.path + "/")
    }

    /// The first symbolic link from just below `root` down to `url`, if there is one.
    static func symbolicLink(between root: URL, and url: URL, fileManager: FileManager) -> URL? {
        var current = root
        for component in url.path.dropFirst(root.path.count + 1).split(separator: "/") {
            current = current.appendingPathComponent(String(component))
            if (try? fileManager.destinationOfSymbolicLink(atPath: current.path)) != nil {
                return current
            }
        }
        return nil
    }
}

/// What the approval screen shows before a fix runs: the files involved and a masked diff of the main file.
public struct FixPreview: Hashable, Sendable {
    /// Files in the copy being changed, relative to it.
    public let targetFiles: [String]
    /// Files a replacement brings in, relative to the copy that runs.
    public let sourceFiles: [String]
    /// The main file before and after: everything removed for a removal, or the change for a replacement.
    public let diff: ConfigDiff

    public init(_ fix: ConfigFix, fileManager: FileManager = .default) {
        if fix.action.editsJSON, let path = fix.jsonPath, let key = path.last {
            // Only the entry, masked: the file may be ~/.claude.json, which holds far more than this change.
            targetFiles = [fix.targetURL.lastPathComponent]
            sourceFiles = []
            let text = (try? String(contentsOf: fix.targetURL, encoding: .utf8)) ?? ""
            let before = JSONTextEdit.valueText(at: path, in: text).flatMap(Self.jsonValue)
            let after = fix.action == .removeServer ? nil : fix.newValue.flatMap(Self.jsonValue)
            diff = ConfigDiff(before: before.map { ItemContent.keyed($0, root: key) }, after: after.map { ItemContent.keyed($0, root: key) })
            return
        }
        targetFiles = Self.files(in: fix.targetURL, fileManager: fileManager)
        sourceFiles = fix.sourceURL.map { Self.files(in: $0, fileManager: fileManager) } ?? []
        let before = Self.mainText(fix.targetURL, kind: fix.target.kind).map(ItemContent.document)
        let after = fix.sourceURL.flatMap { Self.mainText($0, kind: fix.winner?.kind ?? fix.target.kind) }.map(ItemContent.document)
        diff = ConfigDiff(before: before, after: fix.action == .replaceWithWinner ? after : nil)
    }

    private static func jsonValue(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    private static func files(in url: URL, fileManager: FileManager) -> [String] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url.lastPathComponent] }
        return ((try? fileManager.subpathsOfDirectory(atPath: url.path)) ?? []).filter { path in
            var isFolder: ObjCBool = false
            return fileManager.fileExists(atPath: url.appendingPathComponent(path).path, isDirectory: &isFolder) && !isFolder.boolValue
        }
        .sorted()
    }

    private static func mainText(_ url: URL, kind: ItemKind) -> String? {
        let file = kind == .skill ? url.appendingPathComponent("SKILL.md") : url
        return try? String(contentsOf: file, encoding: .utf8)
    }
}
