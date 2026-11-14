import Foundation
import StrataCore

/// Saves the list of repositories. Each entry keeps a bookmark so a moved or renamed folder still resolves.
struct RepositoryStore {
    struct Entry: Codable, Equatable {
        let id: UUID
        var path: String
        var bookmark: Data?
    }

    enum Location: Equatable {
        case available(URL)
        case moved(URL)
        case missing
    }

    static let defaultsKey = "repositories.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> [Entry] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func entry(for repository: Repository) -> Entry {
        Entry(id: repository.id, path: repository.url.path, bookmark: try? repository.url.bookmarkData())
    }

    /// Finds where a saved folder is now: still in place, moved (resolved through its bookmark) or gone.
    static func locate(_ entry: Entry, fileManager: FileManager = .default) -> Location {
        if let bookmark = entry.bookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale),
               directoryExists(url, fileManager: fileManager) {
                let resolved = url.standardizedFileURL
                return resolved.path == URL(fileURLWithPath: entry.path).standardizedFileURL.path ? .available(resolved) : .moved(resolved)
            }
        }
        let url = URL(fileURLWithPath: entry.path, isDirectory: true)
        return directoryExists(url, fileManager: fileManager) ? .available(url) : .missing
    }

    private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
