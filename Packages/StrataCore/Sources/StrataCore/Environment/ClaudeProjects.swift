import Foundation

/// Folders Claude Code has been used in, from the `projects` keys in `~/.claude.json`. Strata suggests them as
/// repositories on first launch. Reading the file is all it does.
public enum ClaudeProjects {
    // ponytail: alphabetical, because the file has no documented "last used" field to sort by.
    /// Existing folders, alphabetically, without the home folder, the root, or two keys for the same folder.
    public static func folders(environment: ScanEnvironment, fileManager: FileManager = .default) -> [URL] {
        guard let data = try? Data(contentsOf: environment.globalConfigFile),
              let projects = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["projects"] as? [String: Any]
        else { return [] }
        let home = environment.homeDirectory.resolvingSymlinksInPath().path
        var seen = Set<String>()
        return projects.keys
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .filter { url in
                let canonical = url.resolvingSymlinksInPath().path
                var isDirectory: ObjCBool = false
                return canonical != home && canonical != "/"
                    && fileManager.fileExists(atPath: canonical, isDirectory: &isDirectory) && isDirectory.boolValue
                    && seen.insert(canonical).inserted
            }
    }
}
