import Foundation

/// The locations Strata reads Claude Code configuration from. Tests point these at fixture folders.
public struct ScanEnvironment: Sendable {
    public var homeDirectory: URL
    /// `~/.claude`, or `CLAUDE_CONFIG_DIR` when set.
    public var claudeDirectory: URL
    /// `~/.claude.json`: user and local-scope MCP servers and per-project state.
    public var globalConfigFile: URL
    /// The managed settings directory, such as `/Library/Application Support/ClaudeCode` on macOS.
    public var managedDirectory: URL?
    /// Folders searched when checking whether a bare MCP `command` exists.
    public var executableSearchPaths: [URL]
    /// How deep to look for nested `.claude` folders and instruction files below the repository root.
    public var nestedSearchDepth: Int

    public init(
        homeDirectory: URL,
        claudeDirectory: URL? = nil,
        globalConfigFile: URL? = nil,
        managedDirectory: URL? = nil,
        executableSearchPaths: [URL] = [],
        nestedSearchDepth: Int = 6
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        let claudeDirectory = (claudeDirectory ?? homeDirectory.appendingPathComponent(".claude")).standardizedFileURL
        self.claudeDirectory = claudeDirectory
        self.globalConfigFile = (globalConfigFile ?? homeDirectory.appendingPathComponent(".claude.json")).standardizedFileURL
        self.managedDirectory = managedDirectory?.standardizedFileURL
        self.executableSearchPaths = executableSearchPaths
        self.nestedSearchDepth = nestedSearchDepth
    }

    /// The environment of the current user on this machine.
    public static func current(processInfo: ProcessInfo = .processInfo) -> ScanEnvironment {
        current(environment: processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// The locations implied by a set of environment variables and a home folder.
    public static func current(environment: [String: String], home: URL) -> ScanEnvironment {
        var claudeDirectory: URL?
        var globalConfigFile: URL?
        if let override = environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            let expanded = override == "~" ? home.path : override.hasPrefix("~/") ? home.path + override.dropFirst() : override
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            claudeDirectory = url
            globalConfigFile = url.appendingPathComponent(".claude.json")
        }

        #if os(macOS)
        let managed = URL(fileURLWithPath: "/Library/Application Support/ClaudeCode", isDirectory: true)
        #else
        let managed = URL(fileURLWithPath: "/etc/claude-code", isDirectory: true)
        #endif

        var searchPaths = (environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let standard = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .map { URL(fileURLWithPath: $0) }
        for path in standard + [home.appendingPathComponent(".local/bin")] where !searchPaths.contains(path) {
            searchPaths.append(path)
        }

        return ScanEnvironment(
            homeDirectory: home,
            claudeDirectory: claudeDirectory,
            globalConfigFile: globalConfigFile,
            managedDirectory: managed,
            executableSearchPaths: searchPaths
        )
    }
}
