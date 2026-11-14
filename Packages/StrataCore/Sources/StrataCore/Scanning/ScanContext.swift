import Foundation

/// Shared state for one inspection: where to look, and the diagnostics and sources found along the way.
final class ScanContext {
    let environment: ScanEnvironment
    let repository: URL
    let reader: FileReader
    let walker: DirectoryWalker

    private(set) var diagnostics: [Diagnostic] = []
    private var sourcesByPath: [String: ScannedSource] = [:]
    private var sourceOrder: [String] = []

    init(environment: ScanEnvironment, repository: URL, fileManager: FileManager = .default) {
        self.environment = environment
        self.repository = repository.standardizedFileURL
        self.reader = FileReader(fileManager: fileManager)
        self.walker = DirectoryWalker(reader: reader, fileManager: fileManager)
    }

    var sources: [ScannedSource] { sourceOrder.compactMap { sourcesByPath[$0] } }

    var claudeDirectory: URL { environment.claudeDirectory }
    var repositoryClaudeDirectory: URL { repository.appendingPathComponent(".claude") }
    var managedDirectory: URL? { environment.managedDirectory }

    func record(_ label: String, _ url: URL, _ state: ScannedSource.State) {
        let path = url.standardizedFileURL.path
        if sourcesByPath[path] == nil { sourceOrder.append(path) }
        if let existing = sourcesByPath[path], existing.state != .missing, state == .missing { return }
        sourcesByPath[path] = ScannedSource(label: label, path: path, state: state)
    }

    func report(_ diagnostic: Diagnostic) {
        guard !diagnostics.contains(where: { $0.id == diagnostic.id }) else { return }
        diagnostics.append(diagnostic)
    }

    /// Reads a JSON object, recording the source and reporting malformed files. Returns nil when missing or broken.
    func readJSON(_ url: URL, label: String) -> [String: Any]? {
        switch reader.jsonObject(at: url) {
        case .success(let object):
            record(label, url, .found)
            return object
        case .failure(.read(.missing)):
            record(label, url, .missing)
            return nil
        case .failure(.read(let error)):
            record(label, url, .unreadable(error.message))
            report(Diagnostic(
                severity: .warning,
                code: .unreadableFile,
                title: "Couldn't read \(url.lastPathComponent)",
                detail: error.message,
                paths: [url.path]
            ))
            return nil
        case .failure(let error):
            record(label, url, .malformed(error.message))
            report(Diagnostic(
                severity: .conflict,
                code: .malformedJSON,
                title: "\(label) isn't valid JSON",
                detail: "\(error.message) Claude Code reports a broken settings file at startup and skips what it can't parse.",
                suggestion: "Fix the JSON in \(url.lastPathComponent). `claude doctor` shows the same error from your terminal.",
                paths: [url.path]
            ))
            return nil
        }
    }

    /// Reads a Markdown document with optional frontmatter, reporting unreadable files and unterminated frontmatter.
    func readDocument(_ url: URL, label: String) -> (frontmatter: Frontmatter, body: String)? {
        switch reader.text(at: url) {
        case .failure(.missing):
            record(label, url, .missing)
            return nil
        case .failure(let error):
            record(label, url, .unreadable(error.message))
            report(Diagnostic(
                severity: .warning,
                code: .unreadableFile,
                title: "Couldn't read \(url.lastPathComponent)",
                detail: error.message,
                paths: [url.path]
            ))
            return nil
        case .success(let text):
            do {
                let parsed = try Frontmatter.parse(document: text)
                record(label, url, .found)
                return parsed
            } catch {
                record(label, url, .malformed("Frontmatter has no closing ---"))
                report(Diagnostic(
                    severity: .warning,
                    code: .malformedFrontmatter,
                    title: "Frontmatter in \(url.lastPathComponent) isn't closed",
                    detail: "The file starts with `---` but has no closing `---` line, so its settings (name, description and so on) can't be read.",
                    suggestion: "Add a `---` line after the last frontmatter field.",
                    paths: [url.path]
                ))
                return (.empty, text)
            }
        }
    }

    /// Path shown to the user: relative to the repository or `~` when possible.
    func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let repositoryPath = repository.path
        if path == repositoryPath { return "." }
        if path.hasPrefix(repositoryPath + "/") { return String(path.dropFirst(repositoryPath.count + 1)) }
        let home = environment.homeDirectory.path
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }

    func isInsideRepository(_ url: URL) -> Bool {
        let path = reader.canonical(url).path
        let root = reader.canonical(repository).path
        return path == root || path.hasPrefix(root + "/")
    }
}
