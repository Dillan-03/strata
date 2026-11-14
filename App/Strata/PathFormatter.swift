import Foundation

/// Shortens absolute paths for display: relative to the repository, or `~/` for the home folder.
struct PathFormatter {
    let repositoryPath: String
    let homePath: String

    func display(_ path: String) -> String {
        if path == repositoryPath { return "." }
        if path.hasPrefix(repositoryPath + "/") { return String(path.dropFirst(repositoryPath.count + 1)) }
        return abbreviatingHome(path)
    }

    /// `~/code/app` rather than the full path; never relative to the repository.
    func abbreviatingHome(_ path: String) -> String {
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~/" + path.dropFirst(homePath.count + 1) }
        return path
    }
}
