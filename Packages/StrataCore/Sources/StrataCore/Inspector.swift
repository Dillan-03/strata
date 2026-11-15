import Foundation

/// Scans a repository and the user's global Claude Code configuration. Read-only: it never writes, executes or connects.
public struct Inspector: Sendable {
    public let environment: ScanEnvironment

    public init(environment: ScanEnvironment = .current()) {
        self.environment = environment
    }

    public func inspect(_ repository: URL, at date: Date = Date()) -> InspectionReport {
        let context = ScanContext(environment: environment, repository: repository)

        guard context.reader.isDirectory(context.repository) else {
            context.record("Repository", context.repository, .missing)
            context.report(Diagnostic(
                severity: .conflict,
                code: .unreadableFile,
                title: "\(context.repository.lastPathComponent) can't be found",
                detail: "Nothing exists at \(context.repository.path). The folder may have been moved, renamed or deleted, or its disk isn't mounted.",
                suggestion: "Locate the folder again, or remove it from Strata.",
                paths: [context.repository.path]
            ))
            return InspectionReport(
                repositoryPath: context.repository.path,
                scannedAt: date,
                items: [],
                diagnostics: context.diagnostics,
                sources: context.sources
            )
        }
        context.record("Repository", context.repository, .found)

        let settings = SettingsScanner(context: context)
        let layers = settings.layers()
        let plugins = PluginScanner(context: context, layers: layers).scan()

        var items = settings.items(from: layers)
        items += plugins.map(\.item)
        items += SkillScanner(context: context, plugins: plugins).scan()
        items += AgentScanner(context: context, plugins: plugins).scan()
        items += MCPScanner(context: context, layers: layers, plugins: plugins).scan()
        items += InstructionScanner(context: context, layers: layers).scan()
        items = items.map { item in
            var item = item
            if item.fingerprint == nil { item.fingerprint = context.fileFingerprint(for: item.source.path) }
            return item
        }

        let displayPath = { (path: String) in context.displayPath(URL(fileURLWithPath: path)) }
        let resolved = Resolver(displayPath: displayPath).resolve(items)
        DiagnosticRules(displayPath: displayPath).diagnose(resolved).forEach(context.report)

        return InspectionReport(
            repositoryPath: context.repository.path,
            scannedAt: date,
            items: resolved,
            diagnostics: context.diagnostics.sorted { ($0.severity, $0.title) < ($1.severity, $1.title) },
            sources: context.sources
        )
    }
}
