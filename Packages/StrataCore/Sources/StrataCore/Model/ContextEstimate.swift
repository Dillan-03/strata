import Foundation

/// A rough estimate of how much context a repository's configuration takes before the first message: the instruction
/// files that load at launch, the skill listing, and subagent descriptions. It's characters divided by four, because
/// Claude Code doesn't document its tokenizer.
public struct ContextEstimate: Hashable, Sendable {
    public struct Entry: Hashable, Sendable, Identifiable {
        public let itemID: ConfigItem.ID
        public let kind: ItemKind
        public let name: String
        public let characters: Int
        public var id: ConfigItem.ID { itemID }
        public var tokens: Int { ContextEstimate.tokens(characters) }
    }

    public struct Warning: Hashable, Sendable {
        public let text: String
        public let source: URL?
    }

    /// Largest first.
    public let entries: [Entry]
    public let warnings: [Warning]

    // ponytail: four characters per token is the usual rule of thumb for English; code and other languages differ.
    public static let charactersPerToken = 4
    /// Claude Code warns at startup when subagent descriptions, other than the built-in ones, pass this many tokens.
    static let subagentWarningTokens = 15_000
    /// Claude Code's guidance: aim to keep each CLAUDE.md under 200 lines.
    static let claudeMDLineGuidance = 200

    /// What the estimate leaves out, for the UI to say plainly.
    public static let notCounted = [
        "MCP tools: Claude Code defers them by default and loads only their names, and Strata never runs a server to list them.",
        "Claude Code's own system prompt, tools and environment details.",
        "Auto memory (MEMORY.md), which Claude Code writes itself.",
        "HTML comments in instruction files, which Claude Code strips, are counted, so instruction sizes run slightly high.",
    ]

    public static func tokens(_ characters: Int) -> Int {
        (characters + charactersPerToken - 1) / charactersPerToken
    }

    public var totalTokens: Int { Self.tokens(entries.map(\.characters).reduce(0, +)) }

    public func tokens(for kinds: Set<ItemKind>) -> Int {
        Self.tokens(entries.filter { kinds.contains($0.kind) }.map(\.characters).reduce(0, +))
    }

    public init(report: InspectionReport, fileManager: FileManager = .default) {
        var entries: [Entry] = []
        var warnings: [Warning] = []
        for item in report.items {
            guard let characters = Self.characters(of: item, fileManager: fileManager) else { continue }
            entries.append(Entry(itemID: item.id, kind: item.kind, name: item.invocation ?? item.name, characters: characters))
            if item.kind == .instruction, ["CLAUDE.md", "CLAUDE.local.md"].contains(item.source.url.lastPathComponent),
               let lines = Self.text(at: item.source.path)?.split(separator: "\n", omittingEmptySubsequences: false).count,
               lines > Self.claudeMDLineGuidance {
                warnings.append(Warning(
                    text: "\(item.name) is \(lines) lines. Claude Code's guidance is to keep each CLAUDE.md under \(Self.claudeMDLineGuidance): longer files use more context and are followed less closely.",
                    source: URL(string: "https://code.claude.com/docs/en/memory")
                ))
            }
        }
        let subagentTokens = Self.tokens(entries.filter { $0.kind == .agent }.map(\.characters).reduce(0, +))
        if subagentTokens > Self.subagentWarningTokens {
            warnings.append(Warning(
                text: "Subagent descriptions come to about \(subagentTokens) tokens. Claude Code warns at startup above \(Self.subagentWarningTokens), "
                    + "and still loads them all.",
                source: URL(string: "https://code.claude.com/docs/en/sub-agents#understand-automatic-delegation")
            ))
        }
        self.entries = entries.sorted { $0.characters > $1.characters }
        self.warnings = warnings
    }

    /// The characters an item adds at launch, or nil when it adds none.
    public static func characters(of item: ConfigItem, fileManager: FileManager = .default) -> Int? {
        guard item.applicability.isApplied else { return nil }
        switch item.kind {
        case .instruction:
            // Subdirectory CLAUDE.md files and path-scoped rules load later, when Claude touches a matching file.
            guard item.loadTiming == .atLaunch else { return nil }
            return text(at: item.source.path)?.count
        case .skill, .command:
            // The listing holds each skill's name and description; one only you can start isn't listed for Claude.
            guard item.metadataValue("Started by")?.hasPrefix("Only you") != true else { return nil }
            return (item.invocation ?? item.name).count + (item.summary?.count ?? 0) + (item.metadataValue("When to use")?.count ?? 0)
        case .agent:
            return item.name.count + (item.summary?.count ?? 0)
        default:
            return nil
        }
    }

    private static func text(at path: String) -> String? {
        try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }
}
