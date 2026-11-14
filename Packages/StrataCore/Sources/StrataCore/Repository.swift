import Foundation

/// A local folder the user asked Strata to inspect.
public struct Repository: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public private(set) var url: URL

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
    }

    public var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? url.path : name
    }

    /// True when both values point at the same folder, ignoring trailing slashes and `.`/`..` segments.
    public func refersToSameFolder(as other: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path == other.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public mutating func relocate(to newURL: URL) {
        url = newURL.standardizedFileURL
    }
}
