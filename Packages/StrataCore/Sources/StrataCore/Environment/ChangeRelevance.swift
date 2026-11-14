import Foundation

/// Decides which file-system changes can affect an inspection, so busy folders don't trigger constant rescans.
///
/// `~/.claude` also holds data Claude Code writes while it works (transcripts, todos, shell snapshots, logs), which
/// changes many times a minute during a session and never affects configuration.
public struct ChangeRelevance: Sendable {
    public enum Affected: Equatable, Sendable {
        /// Nothing Strata reads.
        case none
        /// Something that affects every repository, such as `~/.claude/settings.json`.
        case global
        /// Something inside this repository.
        case repository(String)
    }

    static let globalEntries: Set<String> = [
        "settings.json", "CLAUDE.md", "skills", "agents", "commands", "rules", "plugins",
    ]
    static let ignoredPluginEntries: Set<String> = ["data", "repos", "marketplaces"]
    static let repositoryFileNames: Set<String> = ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", ".mcp.json"]

    public let environment: ScanEnvironment
    public let repositoryPaths: [String]

    public init(environment: ScanEnvironment, repositoryPaths: [String]) {
        self.environment = environment
        self.repositoryPaths = repositoryPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    public func classify(_ path: String) -> Affected {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path

        if path == environment.globalConfigFile.path { return .global }
        if let managed = environment.managedDirectory?.path, path == managed || path.hasPrefix(managed + "/") { return .global }

        let claude = environment.claudeDirectory.path
        if path.hasPrefix(claude + "/") {
            let components = path.dropFirst(claude.count + 1).split(separator: "/").map(String.init)
            guard let first = components.first, Self.globalEntries.contains(first) else { return .none }
            if first == "plugins", components.count > 1, Self.ignoredPluginEntries.contains(components[1]) { return .none }
            return .global
        }

        for repository in repositoryPaths.sorted(by: { $0.count > $1.count }) where path == repository || path.hasPrefix(repository + "/") {
            return isRelevantInsideRepository(String(path.dropFirst(repository.count))) ? .repository(repository) : .none
        }

        if repositoryPaths.contains(where: { $0.hasPrefix(path + "/") }) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return Self.repositoryFileNames.contains(name) || name == ".claude" ? .global : .none
        }
        if repositoryPaths.contains(where: { $0.hasPrefix(URL(fileURLWithPath: path).deletingLastPathComponent().path + "/") }) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if Self.repositoryFileNames.contains(name) { return .global }
        }
        return .none
    }

    private func isRelevantInsideRepository(_ relative: String) -> Bool {
        let components = relative.split(separator: "/").map(String.init)
        guard let last = components.last else { return true }
        if components.contains(where: { DirectoryWalker.skippedDirectoryNames.contains($0) }) { return false }
        if components.contains(".claude") { return true }
        return Self.repositoryFileNames.contains(last)
    }
}
