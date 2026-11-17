import Foundation

/// What kind of Claude Code configuration an item is.
public enum ItemKind: String, CaseIterable, Codable, Hashable, Sendable {
    case skill
    case command
    case agent
    case mcpServer
    case plugin
    case hook
    case instruction
    case setting

    public var title: String {
        switch self {
        case .skill: "Skill"
        case .command: "Command"
        case .agent: "Subagent"
        case .mcpServer: "MCP Server"
        case .plugin: "Plugin"
        case .hook: "Hook"
        case .instruction: "Instruction File"
        case .setting: "Setting"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .skill: "Skills"
        case .command: "Commands"
        case .agent: "Subagents"
        case .mcpServer: "MCP Servers"
        case .plugin: "Plugins"
        case .hook: "Hooks"
        case .instruction: "Instructions"
        case .setting: "Settings"
        }
    }
}

/// Where an item comes from, in Claude Code's own terms.
public enum Scope: String, CaseIterable, Codable, Hashable, Sendable {
    /// Deployed by an organisation through managed settings.
    case managed
    /// The user's own configuration under `~/.claude` or `~/.claude.json`.
    case user
    /// Committed to the repository root.
    case project
    /// Personal to this repository: `settings.local.json`, `CLAUDE.local.md`, local-scope MCP servers.
    case local
    /// A `.claude/` folder or instruction file below the repository root.
    case nested
    /// An instruction file in a directory above the repository.
    case ancestor
    /// Contributed by a plugin.
    case plugin
    /// Downloaded from the user's claude.ai account.
    case synced

    public var title: String {
        switch self {
        case .managed: "Managed"
        case .user: "Global"
        case .project: "Repo"
        case .local: "Local"
        case .nested: "Nested"
        case .ancestor: "Parent folder"
        case .plugin: "Plugin"
        case .synced: "claude.ai"
        }
    }
}

/// How far along the path to being used an item has got, as far as files on disk can show.
public enum Stage: Int, CaseIterable, Codable, Comparable, Sendable {
    /// Mentioned somewhere, but not present on disk (for example, a plugin enabled in settings but never installed).
    case declared
    /// The file or folder exists.
    case discovered
    /// A plugin's files are installed.
    case installed
    /// Turned on by settings or by default.
    case enabled

    public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .declared: "Declared"
        case .discovered: "Discovered"
        case .installed: "Installed"
        case .enabled: "Enabled"
        }
    }
}

/// When Claude Code reads an item into a session.
public enum LoadTiming: String, Codable, Hashable, Sendable {
    case atLaunch
    case onDemand
    case pathGated
    case whenInvoked
    case unknown

    public var title: String {
        switch self {
        case .atLaunch: "At session start"
        case .onDemand: "When Claude works in that folder"
        case .pathGated: "When Claude touches matching files"
        case .whenInvoked: "When invoked"
        case .unknown: "Unknown"
        }
    }
}

/// The outcome of resolution for one item.
public enum Applicability: Codable, Hashable, Sendable {
    /// Applies to the repository and wins any name clash.
    case effective
    /// Applies too, alongside other definitions of the same thing (instructions are concatenated, plugin skills are namespaced).
    case combined
    /// Another definition with the same name wins.
    case shadowed(by: ConfigItem.ID)
    /// Applies only under a condition, described in the explanation.
    case conditional
    /// Present but turned off, excluded, or not installed.
    case inactive
    /// Claude Code won't load it because of an error.
    case invalid
    /// Static inspection can't tell.
    case unknown

    public var title: String {
        switch self {
        case .effective: "Applies"
        case .combined: "Applies (combined)"
        case .shadowed: "Overridden"
        case .conditional: "Conditional"
        case .inactive: "Inactive"
        case .invalid: "Won't load"
        case .unknown: "Unknown"
        }
    }

    public var isApplied: Bool {
        switch self {
        case .effective, .combined: true
        case .shadowed, .conditional, .inactive, .invalid, .unknown: false
        }
    }
}

public struct Metadatum: Hashable, Codable, Sendable {
    public let label: String
    public let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

public struct SourceLocation: Hashable, Codable, Sendable {
    /// Absolute path of the file that defines the item.
    public let path: String
    /// Location inside the file, such as `mcpServers.github`, when the file defines several items.
    public let keyPath: String?

    public init(path: String, keyPath: String? = nil) {
        self.path = path
        self.keyPath = keyPath
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// One piece of Claude Code configuration and everything Strata knows about where it came from.
public struct ConfigItem: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = String

    public let id: ID
    public let kind: ItemKind
    /// The identity Claude Code uses when comparing definitions: a command name, agent name, server name, plugin id or file name.
    public let name: String
    /// What the user types, for skills and commands.
    public var invocation: String?
    public let summary: String?
    public let scope: Scope
    public let source: SourceLocation
    /// The plugin id or subdirectory an item belongs to, when that matters for its identity.
    public let origin: String?
    public var metadata: [Metadatum]
    public var stage: Stage
    public var loadTiming: LoadTiming
    /// Set when the scanner found a reason Claude Code won't load the item.
    public var loadBlocker: String?
    /// Set when the item is present but turned off, excluded or not installed.
    public var inactiveReason: String?
    /// Set when the item only applies under a condition, such as on-demand loading or an approval prompt.
    public var condition: String?
    /// A secret-free key for matching definitions by what they point at, such as a hashed MCP endpoint.
    public var matchKey: String?
    /// Order instruction files are read in, lowest first.
    public var loadOrder: Int?
    /// A hash of what defines the item (its file, or its entry in a JSON file), used to notice edits between scans.
    public var fingerprint: String?

    public var applicability: Applicability
    /// 1 is the highest-precedence definition among items that share `name`.
    public var precedenceRank: Int?
    public var explanation: [String]

    public init(
        kind: ItemKind,
        name: String,
        invocation: String? = nil,
        summary: String? = nil,
        scope: Scope,
        source: SourceLocation,
        origin: String? = nil,
        metadata: [Metadatum] = [],
        stage: Stage = .discovered,
        loadTiming: LoadTiming = .atLaunch,
        loadBlocker: String? = nil,
        inactiveReason: String? = nil,
        condition: String? = nil,
        matchKey: String? = nil,
        loadOrder: Int? = nil
    ) {
        self.id = Self.makeID(kind: kind, scope: scope, source: source, name: name)
        self.kind = kind
        self.name = name
        self.invocation = invocation
        self.summary = summary
        self.scope = scope
        self.source = source
        self.origin = origin
        self.metadata = metadata
        self.stage = stage
        self.loadTiming = loadTiming
        self.loadBlocker = loadBlocker
        self.inactiveReason = inactiveReason
        self.condition = condition
        self.matchKey = matchKey
        self.loadOrder = loadOrder
        self.applicability = .unknown
        self.precedenceRank = nil
        self.explanation = []
    }

    public static func makeID(kind: ItemKind, scope: Scope, source: SourceLocation, name: String) -> ID {
        [kind.rawValue, scope.rawValue, source.path, source.keyPath ?? "", name].joined(separator: "|")
    }

    public func metadataValue(_ label: String) -> String? {
        metadata.first { $0.label == label }?.value
    }
}
