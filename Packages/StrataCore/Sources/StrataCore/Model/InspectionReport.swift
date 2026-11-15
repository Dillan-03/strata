import Foundation

/// Everything Strata found for one repository.
public struct InspectionReport: Hashable, Codable, Sendable {
    public let repositoryPath: String
    public let scannedAt: Date
    public let items: [ConfigItem]
    public let diagnostics: [Diagnostic]
    public let sources: [ScannedSource]
    /// What defines each item, masked, for showing changes between scans.
    public let contents: [ConfigItem.ID: ItemContent]

    public init(
        repositoryPath: String,
        scannedAt: Date,
        items: [ConfigItem],
        diagnostics: [Diagnostic],
        sources: [ScannedSource],
        contents: [ConfigItem.ID: ItemContent] = [:]
    ) {
        self.repositoryPath = repositoryPath
        self.scannedAt = scannedAt
        self.items = items
        self.diagnostics = diagnostics
        self.sources = sources
        self.contents = contents
    }

    public func items(of kind: ItemKind) -> [ConfigItem] {
        items.filter { $0.kind == kind }
    }

    public func item(withID id: ConfigItem.ID) -> ConfigItem? {
        items.first { $0.id == id }
    }

    public func diagnostics(for itemID: ConfigItem.ID) -> [Diagnostic] {
        diagnostics.filter { $0.itemIDs.contains(itemID) }
    }

    /// True when the repository has no Claude Code configuration of its own (global items may still apply).
    public var hasRepositoryConfiguration: Bool {
        items.contains { [.project, .local, .nested].contains($0.scope) }
    }
}
