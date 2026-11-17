import Foundation

public struct Diagnostic: Identifiable, Hashable, Codable, Sendable {
    public enum Severity: Int, CaseIterable, Codable, Comparable, Sendable {
        /// Two definitions compete, or something Claude Code won't load.
        case conflict = 0
        /// Probably not what the user intended.
        case warning = 1
        /// Worth knowing; nothing is wrong.
        case info = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .conflict: "Conflict"
            case .warning: "Warning"
            case .info: "Info"
            }
        }
    }

    public enum Code: String, Codable, Hashable, Sendable {
        case malformedJSON
        case malformedFrontmatter
        case unreadableFile
        case unrecognisedFormat
        case shadowedDefinition
        case duplicateNameInDirectory
        case conflictingMCPEndpoints
        case duplicateMCPEndpoint
        case mcpURLWithoutType
        case mcpUnsupportedType
        case mcpMissingExecutable
        case mcpRelativeExecutable
        case mcpExecutableNotOnStandardPath
        case skillNotInFolder
        case skillMissingDefinition
        case reservedName
        case missingRequiredField
        case invalidName
        case missingImport
        case importDepthExceeded
        case externalImport
        case pluginEnabledButNotInstalled
        case pluginInstallMissing
        case agentsMDIgnored
        case symlinkDuplicate
        case unknownOutputStyle
    }

    public let id: String
    public let severity: Severity
    public let code: Code
    public let title: String
    public let detail: String
    public let suggestion: String?
    public let paths: [String]
    public let itemIDs: [ConfigItem.ID]

    public init(
        severity: Severity,
        code: Code,
        title: String,
        detail: String,
        suggestion: String? = nil,
        paths: [String] = [],
        itemIDs: [ConfigItem.ID] = []
    ) {
        self.id = [code.rawValue, paths.joined(separator: ","), itemIDs.joined(separator: ","), title].joined(separator: "|")
        self.severity = severity
        self.code = code
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
        self.paths = paths
        self.itemIDs = itemIDs
    }
}

/// A file or folder Strata looked at, and what it found there.
public struct ScannedSource: Identifiable, Hashable, Codable, Sendable {
    public enum State: Hashable, Codable, Sendable {
        case found
        case missing
        case unreadable(String)
        case malformed(String)
    }

    public var id: String { path }
    public let label: String
    public let path: String
    public let state: State

    public init(label: String, path: String, state: State) {
        self.label = label
        self.path = path
        self.state = state
    }
}
