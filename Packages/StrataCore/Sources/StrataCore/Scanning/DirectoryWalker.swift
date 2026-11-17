import Foundation

/// Bounded, symlink-loop-safe directory traversal.
struct DirectoryWalker {
    static let skippedDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData", "Pods", "Carthage", "vendor", "dist",
        ".next", ".nuxt", "target", ".venv", "venv", "__pycache__", ".gradle", ".idea", ".turbo", ".expo",
        "coverage", ".swiftpm", ".terraform",
    ]

    let reader: FileReader
    let fileManager: FileManager

    init(reader: FileReader = FileReader(), fileManager: FileManager = .default) {
        self.reader = reader
        self.fileManager = fileManager
    }

    /// Immediate children of a folder, sorted by name. Missing or unreadable folders give an empty list.
    func children(of directory: URL) -> [URL] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted().map { directory.appendingPathComponent($0) }
    }

    /// Every file below `directory` whose name satisfies `include`, sorted by path.
    func files(under directory: URL, maxDepth: Int = 8, include: (URL) -> Bool) -> [URL] {
        var results: [URL] = []
        var visited: Set<String> = []
        walk(directory, depth: 0, maxDepth: maxDepth, visited: &visited) { url, isDirectory in
            if !isDirectory, include(url) { results.append(url) }
            return true
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Every folder below `root` (not `root` itself) named `name`, skipping dependency and build folders.
    func directories(named name: String, under root: URL, maxDepth: Int) -> [URL] {
        var results: [URL] = []
        var visited: Set<String> = []
        walk(root, depth: 0, maxDepth: maxDepth, visited: &visited) { url, isDirectory in
            guard isDirectory else { return false }
            if url.lastPathComponent == name {
                // Paths, not URLs: URL equality counts a trailing slash, so on Linux the root's own folder looked nested.
                if url.deletingLastPathComponent().standardizedFileURL.path != root.standardizedFileURL.path {
                    results.append(url)
                }
                return false
            }
            return !Self.skippedDirectoryNames.contains(url.lastPathComponent)
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Every file below `root` (not directly in it) whose name is in `names`, skipping dependency and build folders.
    func nestedFiles(named names: Set<String>, under root: URL, maxDepth: Int) -> [URL] {
        var results: [URL] = []
        var visited: Set<String> = []
        walk(root, depth: 0, maxDepth: maxDepth, visited: &visited) { url, isDirectory in
            if isDirectory {
                return !Self.skippedDirectoryNames.contains(url.lastPathComponent) && url.lastPathComponent != ".claude"
            }
            let parent = url.deletingLastPathComponent().standardizedFileURL.path
            if names.contains(url.lastPathComponent), parent != root.standardizedFileURL.path {
                results.append(url)
            }
            return false
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Calls `visit` for every entry below `directory`. Returning `true` for a folder descends into it.
    private func walk(_ directory: URL, depth: Int, maxDepth: Int, visited: inout Set<String>, visit: (URL, Bool) -> Bool) {
        guard depth <= maxDepth else { return }
        let canonical = reader.canonical(directory).path
        guard visited.insert(canonical).inserted else { return }
        for child in children(of: directory) {
            let isDirectory = reader.isDirectory(child)
            if visit(child, isDirectory), isDirectory {
                walk(child, depth: depth + 1, maxDepth: maxDepth, visited: &visited, visit: visit)
            }
        }
    }
}
