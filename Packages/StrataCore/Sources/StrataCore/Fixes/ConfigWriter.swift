import Foundation

/// A fix Strata made, kept beside the backup so it can be undone.
public struct FixRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let action: ConfigFix.Action
    public let itemKind: ItemKind
    public let itemName: String
    /// Where the overridden copy was, and where a replacement now is.
    public let targetPath: String
    /// The original copy, in Strata's backups.
    public let backupPath: String
    /// What a replacement left behind, so undo can tell whether it has been edited since.
    let resultFingerprint: String?
    public internal(set) var undoneAt: Date?
}

public enum FixError: Error, Equatable, LocalizedError {
    /// The copy, or the one it would be replaced with, changed after the fix was reviewed.
    case changedSinceReview(String)
    /// The path is outside the folders Strata may write in.
    case notAllowed(String)
    /// Undo would overwrite something that's there now.
    case undoBlocked(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .changedSinceReview(let detail), .notAllowed(let detail), .undoBlocked(let detail), .failed(let detail): detail
        }
    }
}

/// The only part of Strata that writes Claude Code configuration. Every change keeps a backup, is checked against
/// what was reviewed first, and can be undone. Nothing here runs unless the user turns fixes on and approves one.
public struct ConfigWriter {
    public let backupDirectory: URL
    /// Folders the writer may change. Anything else is refused, whatever the fix says.
    public let allowedRoots: [URL]
    let fileManager: FileManager

    public init(backupDirectory: URL, allowedRoots: [URL], fileManager: FileManager = .default) {
        self.backupDirectory = backupDirectory.standardizedFileURL
        self.allowedRoots = allowedRoots.map(\.standardizedFileURL)
        self.fileManager = fileManager
    }

    private static let recordName = "fix.json"

    // MARK: - Applying

    public func apply(_ fix: ConfigFix, at date: Date = .now) throws -> FixRecord {
        let target = fix.targetURL.standardizedFileURL
        try checkAllowed(target)
        guard (try? Fingerprint.ofTree(target, fileManager: fileManager)) == fix.targetFingerprint else {
            throw FixError.changedSinceReview("\(target.lastPathComponent) changed after you reviewed this fix, so Strata left it alone. Review it again.")
        }
        if let source = fix.sourceURL {
            try checkAllowed(source)
            guard (try? Fingerprint.ofTree(source, fileManager: fileManager)) == fix.sourceFingerprint else {
                throw FixError.changedSinceReview("The copy that runs changed after you reviewed this fix, so Strata left both alone. Review it again.")
            }
        }

        let folder = try makeBackupFolder(at: date)
        let backup = folder.appendingPathComponent(target.lastPathComponent)
        var resultFingerprint: String?
        do {
            switch fix.action {
            case .removeCopy:
                try fileManager.moveItem(at: target, to: backup)
            case .replaceWithWinner:
                guard let source = fix.sourceURL else { throw FixError.failed("There's no copy to replace it with.") }
                try fileManager.copyItem(at: target, to: backup)
                try swap(target, withCopyOf: source)
                resultFingerprint = try Fingerprint.ofTree(target, fileManager: fileManager)
            }
        } catch {
            try? fileManager.removeItem(at: folder)
            throw (error as? FixError) ?? FixError.failed("Strata couldn't change \(target.lastPathComponent): \(error.localizedDescription)")
        }

        let record = FixRecord(
            id: UUID(), date: date, action: fix.action, itemKind: fix.target.kind, itemName: fix.target.name,
            targetPath: target.path, backupPath: backup.path, resultFingerprint: resultFingerprint, undoneAt: nil
        )
        try save(record, in: folder)
        return record
    }

    // MARK: - Undoing

    @discardableResult
    public func undo(_ record: FixRecord, at date: Date = .now) throws -> FixRecord {
        let target = URL(fileURLWithPath: record.targetPath)
        let backup = URL(fileURLWithPath: record.backupPath)
        try checkAllowed(target)
        guard record.undoneAt == nil else { throw FixError.undoBlocked("This fix was already undone.") }
        guard fileManager.fileExists(atPath: backup.path) else {
            throw FixError.undoBlocked("The backup is gone, so there's nothing to put back.")
        }

        switch record.action {
        case .removeCopy:
            guard !exists(target) else {
                throw FixError.undoBlocked("Something new is at \(target.lastPathComponent) now. Move it away, then undo.")
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: backup, to: target)
        case .replaceWithWinner:
            guard (try? Fingerprint.ofTree(target, fileManager: fileManager)) == record.resultFingerprint else {
                throw FixError.undoBlocked("\(target.lastPathComponent) changed after Strata replaced it. Undo would lose that edit, so Strata left it.")
            }
            try swap(target, withCopyOf: backup)
        }

        var undone = record
        undone.undoneAt = date
        try save(undone, in: backup.deletingLastPathComponent())
        return undone
    }

    // MARK: - History

    /// Every fix with a backup, newest first.
    public func records() -> [FixRecord] {
        let folders = (try? fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent(Self.recordName)) }
            .compactMap { try? Self.decoder.decode(FixRecord.self, from: $0) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Pieces

    /// Inside an allowed folder, and not reached through a symbolic link below it.
    private func checkAllowed(_ url: URL) throws {
        let url = url.standardizedFileURL
        guard let root = allowedRoots.first(where: { FixPlanner.contains($0, url) }) else {
            throw FixError.notAllowed("Strata only changes files in ~/.claude and the repository's .claude folder, not \(url.path).")
        }
        if let link = FixPlanner.symbolicLink(between: root, and: url, fileManager: fileManager) {
            throw FixError.notAllowed("\(link.lastPathComponent) is a symbolic link, so Strata won't change it.")
        }
    }

    /// Puts a copy of `source` where `target` is. The copy is made beside the target first, then the two are swapped
    /// by renaming, so a failure part-way leaves the original in place.
    private func swap(_ target: URL, withCopyOf source: URL) throws {
        let parent = target.deletingLastPathComponent()
        let incoming = parent.appendingPathComponent(".strata-incoming-\(UUID().uuidString)")
        let outgoing = parent.appendingPathComponent(".strata-outgoing-\(UUID().uuidString)")
        try fileManager.copyItem(at: source, to: incoming)
        do {
            try fileManager.moveItem(at: target, to: outgoing)
        } catch {
            try? fileManager.removeItem(at: incoming)
            throw error
        }
        do {
            try fileManager.moveItem(at: incoming, to: target)
        } catch {
            try? fileManager.moveItem(at: outgoing, to: target)
            try? fileManager.removeItem(at: incoming)
            throw error
        }
        try? fileManager.removeItem(at: outgoing)
    }

    private func makeBackupFolder(at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = backupDirectory.appendingPathComponent("\(formatter.string(from: date))-\(UUID().uuidString.prefix(8))")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func save(_ record: FixRecord, in folder: URL) throws {
        try Self.encoder.encode(record).write(to: folder.appendingPathComponent(Self.recordName), options: .atomic)
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
