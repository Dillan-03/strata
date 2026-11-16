import Foundation

/// A change Strata can make to a copy that another copy overrides, but only when the user asks and approves it.
public struct ConfigFix: Hashable, Sendable, Identifiable {
    public enum Action: String, Hashable, Codable, Sendable {
        /// Moves the overridden copy into Strata's backups.
        case removeCopy
        /// Overwrites the overridden copy with the copy that runs, keeping the old one in Strata's backups.
        case replaceWithWinner
    }

    public let action: Action
    /// The overridden copy the fix changes.
    public let target: ConfigItem
    /// The copy that runs.
    public let winner: ConfigItem
    /// What the fix moves or overwrites: a skill's folder, or a command's or subagent's file.
    public let targetURL: URL
    /// What a replacement copies from: the winner's folder or file.
    public let sourceURL: URL?
    /// Taken when the fix was offered. Applying refuses if either side has changed since.
    let targetFingerprint: String
    let sourceFingerprint: String?

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
    static let fixableKinds: Set<ItemKind> = [.skill, .command, .agent]
    static let writableScopes: Set<Scope> = [.user, .project]

    public static func offer(
        for item: ConfigItem,
        in report: InspectionReport,
        environment: ScanEnvironment,
        fileManager: FileManager = .default
    ) -> FixOffer {
        guard case .shadowed(let winnerID) = item.applicability,
              fixableKinds.contains(item.kind),
              let winner = report.item(withID: winnerID) else { return .none }

        guard writableScopes.contains(item.scope) else {
            return .unavailable("Strata only changes copies in ~/.claude or this repository's .claude folder. This one is \(item.scope.title.lowercased()).")
        }
        let roots = allowedRoots(repositoryPath: report.repositoryPath, environment: environment)
        guard let target = unit(for: item), let targetRoot = roots.first(where: { contains($0, target) }) else {
            return .unavailable("Strata couldn't place this copy inside ~/.claude or the repository's .claude folder.")
        }
        if let link = symbolicLink(between: targetRoot, and: target, fileManager: fileManager) {
            return .unavailable("\(link.lastPathComponent) is a symbolic link. Change the copy where it points instead.")
        }
        guard let targetFingerprint = try? Fingerprint.ofTree(target, fileManager: fileManager) else {
            return .unavailable("Strata couldn't read this copy.")
        }

        var fixes = [ConfigFix(
            action: .removeCopy, target: item, winner: winner, targetURL: target,
            sourceURL: nil, targetFingerprint: targetFingerprint, sourceFingerprint: nil
        )]
        if winner.kind == item.kind,
           writableScopes.contains(winner.scope),
           let source = unit(for: winner),
           let sourceRoot = roots.first(where: { contains($0, source) }),
           symbolicLink(between: sourceRoot, and: source, fileManager: fileManager) == nil,
           let sourceFingerprint = try? Fingerprint.ofTree(source, fileManager: fileManager) {
            fixes.append(ConfigFix(
                action: .replaceWithWinner, target: item, winner: winner, targetURL: target,
                sourceURL: source, targetFingerprint: targetFingerprint, sourceFingerprint: sourceFingerprint
            ))
        }
        return .available(fixes)
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
        targetFiles = Self.files(in: fix.targetURL, fileManager: fileManager)
        sourceFiles = fix.sourceURL.map { Self.files(in: $0, fileManager: fileManager) } ?? []
        let before = Self.mainText(fix.targetURL, kind: fix.target.kind).map(ItemContent.document)
        let after = fix.sourceURL.flatMap { Self.mainText($0, kind: fix.winner.kind) }.map(ItemContent.document)
        diff = ConfigDiff(before: before, after: fix.action == .removeCopy ? nil : after)
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
