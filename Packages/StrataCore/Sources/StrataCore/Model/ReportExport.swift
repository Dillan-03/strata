import Foundation

/// A repository's report as Markdown or JSON, for sharing in a pull request, an issue or a chat. Home paths become `~` and
/// every string goes through the secret masker again, on top of the masking the scanners already did.
public struct ReportExport: Sendable {
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case markdown, json

        public var id: String { rawValue }
        public var title: String { self == .markdown ? "Markdown" : "JSON" }
        public var fileExtension: String { self == .markdown ? "md" : "json" }
    }

    let report: InspectionReport
    let items: [ConfigItem]
    let strataVersion: String
    let home: String

    /// `items` is what to include: every item, or only what the current filters show.
    public init(report: InspectionReport, items: [ConfigItem], strataVersion: String, homeDirectory: URL) {
        self.report = report
        self.items = items
        self.strataVersion = strataVersion
        home = homeDirectory.standardizedFileURL.path
    }

    public func data(as format: Format) throws -> Data {
        switch format {
        case .markdown: Data(markdown().utf8)
        case .json: try json()
        }
    }

    func clean(_ text: String) -> String {
        SecretRedactor.redactText(home.count > 1 ? text.replacingOccurrences(of: home, with: "~") : text)
    }

    private var repositoryName: String { URL(fileURLWithPath: report.repositoryPath).lastPathComponent }

    private var issues: [Diagnostic] { report.diagnostics.filter { $0.severity != .info } }

    // MARK: - Markdown

    public func markdown() -> String {
        var lines = [
            "# Claude Code configuration for \(clean(repositoryName))",
            "",
            "- Repository: `\(clean(report.repositoryPath))`",
            "- Scanned: \(ISO8601DateFormatter().string(from: report.scannedAt))",
            "- \(items.count) item\(items.count == 1 ? "" : "s"), \(items.filter { $0.applicability.isApplied }.count) applying",
            "- Exported by Strata \(strataVersion). Secrets are masked and home paths shortened to ~.",
        ]
        if !issues.isEmpty {
            lines += ["", "## Issues", ""]
            for issue in issues {
                lines.append("- **\(clean(issue.title))**: \(clean(issue.detail))")
            }
        }
        for kind in ItemKind.allCases {
            let ofKind = items.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { continue }
            lines += ["", "## \(kind.pluralTitle) (\(ofKind.count))", ""]
            for item in ofKind {
                let name = item.invocation ?? item.name
                lines.append("- `\(clean(name))` · \(item.scope.title) · **\(item.applicability.title)** · `\(clean(item.source.path))`")
                if let summary = item.summary, !summary.isEmpty { lines.append("  - \(clean(summary))") }
                for sentence in item.explanation { lines.append("  - \(clean(sentence))") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - JSON

    struct ExportedItem: Encodable {
        let kind: String
        let name: String
        let invocation: String?
        let scope: String
        let status: String
        let path: String
        let keyPath: String?
        let summary: String?
        let explanation: [String]
        let details: [String: String]
    }

    struct ExportedIssue: Encodable {
        let severity: String
        let title: String
        let detail: String
        let paths: [String]
    }

    struct Exported: Encodable {
        let strataVersion: String
        let repository: String
        let scannedAt: Date
        let items: [ExportedItem]
        let issues: [ExportedIssue]
    }

    public func json() throws -> Data {
        let exported = Exported(
            strataVersion: strataVersion,
            repository: clean(report.repositoryPath),
            scannedAt: report.scannedAt,
            items: items.map { item in
                ExportedItem(
                    kind: item.kind.rawValue, name: clean(item.name), invocation: item.invocation.map(clean), scope: item.scope.rawValue,
                    status: item.applicability.title, path: clean(item.source.path), keyPath: item.source.keyPath.map(clean),
                    summary: item.summary.map(clean), explanation: item.explanation.map(clean),
                    details: Dictionary(item.metadata.map { ($0.label, clean($0.value)) }, uniquingKeysWith: { first, _ in first })
                )
            },
            issues: issues.map { ExportedIssue(severity: "\($0.severity)", title: clean($0.title), detail: clean($0.detail), paths: $0.paths.map(clean)) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exported)
    }
}
