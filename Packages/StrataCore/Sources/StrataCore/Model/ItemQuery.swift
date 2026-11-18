import Foundation

/// Local search and filters over a report. Everything runs in memory; nothing leaves the machine.
public struct ItemQuery: Equatable, Sendable {
    /// Applicability without associated values, for filtering.
    public enum Status: String, CaseIterable, Hashable, Sendable {
        case applies
        case overridden
        case conditional
        case inactive
        case wontLoad
        case unknown

        public init(_ applicability: Applicability) {
            switch applicability {
            case .effective, .combined: self = .applies
            case .shadowed: self = .overridden
            case .conditional: self = .conditional
            case .inactive: self = .inactive
            case .invalid: self = .wontLoad
            case .unknown: self = .unknown
            }
        }

        public var title: String {
            switch self {
            case .applies: "Applies"
            case .overridden: "Overridden"
            case .conditional: "Conditional"
            case .inactive: "Inactive"
            case .wontLoad: "Won't Load"
            case .unknown: "Unknown"
            }
        }
    }

    public var text: String
    /// Scopes to include. Empty means every scope.
    public var scopes: Set<Scope>
    /// Statuses to include. Empty means every status.
    public var statuses: Set<Status>
    public var onlyWithIssues: Bool

    public init(text: String = "", scopes: Set<Scope> = [], statuses: Set<Status> = [], onlyWithIssues: Bool = false) {
        self.text = text
        self.scopes = scopes
        self.statuses = statuses
        self.onlyWithIssues = onlyWithIssues
    }

    /// True when any filter other than the search text is set.
    public var hasFilters: Bool {
        !scopes.isEmpty || !statuses.isEmpty || onlyWithIssues
    }

    public var isEmpty: Bool {
        !hasFilters && tokens.isEmpty
    }

    public mutating func clearFilters() {
        scopes = []
        statuses = []
        onlyWithIssues = false
    }

    /// Whether a scope is picked. Lets a toggle bind to one scope.
    public subscript(scope scope: Scope) -> Bool {
        get { scopes.contains(scope) }
        set { if newValue { scopes.insert(scope) } else { scopes.remove(scope) } }
    }

    /// Whether a status is picked. Lets a toggle bind to one status.
    public subscript(status status: Status) -> Bool {
        get { statuses.contains(status) }
        set { if newValue { statuses.insert(status) } else { statuses.remove(status) } }
    }

    /// How many items each filter would show if it were the only one picked in its group, keeping the search and every other group.
    public struct Counts: Equatable, Sendable {
        public var scopes: [Scope: Int] = [:]
        public var statuses: [Status: Int] = [:]
        public var withIssues = 0
    }

    /// Counts for every filter in one pass, so it stays as fast as `apply` while typing.
    public func counts(in items: [ConfigItem], report: InspectionReport) -> Counts {
        let flagged = Self.flaggedIDs(in: report)
        let words = tokens
        var counts = Counts()
        for item in items where words.isEmpty || Self.matches(words, in: Self.searchableText(of: item)) {
            let status = Status(item.applicability)
            let inScope = scopes.isEmpty || scopes.contains(item.scope)
            let inStatus = statuses.isEmpty || statuses.contains(status)
            let hasIssues = flagged.contains(item.id)
            let passesIssues = !onlyWithIssues || hasIssues
            if inStatus, passesIssues { counts.scopes[item.scope, default: 0] += 1 }
            if inScope, passesIssues { counts.statuses[status, default: 0] += 1 }
            if inScope, inStatus, hasIssues { counts.withIssues += 1 }
        }
        return counts
    }

    /// Items in the report that pass every filter and contain every search word.
    public func apply(to items: [ConfigItem], in report: InspectionReport) -> [ConfigItem] {
        guard !isEmpty else { return items }
        let flagged = onlyWithIssues ? Self.flaggedIDs(in: report) : []
        let words = tokens
        return items.filter { item in
            if !scopes.isEmpty, !scopes.contains(item.scope) { return false }
            if !statuses.isEmpty, !statuses.contains(Status(item.applicability)) { return false }
            if onlyWithIssues, !flagged.contains(item.id) { return false }
            return words.isEmpty || Self.matches(words, in: Self.searchableText(of: item))
        }
    }

    /// Diagnostics whose text contains every search word. Filters other than text don't apply to diagnostics.
    public func apply(to diagnostics: [Diagnostic]) -> [Diagnostic] {
        let words = tokens
        guard !words.isEmpty else { return diagnostics }
        return diagnostics.filter { diagnostic in
            let text = ([diagnostic.title, diagnostic.detail, diagnostic.suggestion ?? ""] + diagnostic.paths).joined(separator: "\n")
            return Self.matches(words, in: Self.fold(text))
        }
    }

    /// Warnings and errors about items the scope and status filters let through, ignoring the search text.
    /// An issue that names no item always counts, because there's no scope or status to filter it by.
    public func issues(in report: InspectionReport) -> [Diagnostic] {
        let issues = report.diagnostics.filter { $0.severity != .info }
        guard !scopes.isEmpty || !statuses.isEmpty else { return issues }
        let shown = Set(ItemQuery(scopes: scopes, statuses: statuses).apply(to: report.items, in: report).map(\.id))
        return issues.filter { $0.itemIDs.isEmpty || $0.itemIDs.contains(where: shown.contains) }
    }

    private static func flaggedIDs(in report: InspectionReport) -> Set<ConfigItem.ID> {
        Set(report.diagnostics.filter { $0.severity != .info }.flatMap(\.itemIDs))
    }

    private var tokens: [String] {
        Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func matches(_ words: [String], in haystack: String) -> Bool {
        words.allSatisfy { haystack.contains($0) }
    }

    private static func searchableText(of item: ConfigItem) -> String {
        var parts = [item.name, item.invocation ?? "", item.summary ?? "", item.source.path, item.scope.title, item.kind.title, item.origin ?? ""]
        parts += item.metadata.map(\.value)
        return fold(parts.joined(separator: "\n"))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
