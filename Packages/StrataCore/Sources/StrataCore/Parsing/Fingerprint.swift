import Foundation

/// FNV-1a hashes for noticing that content changed without keeping the content. Not cryptographic, so they are
/// never shown. The only place one is written to disk is a fix's backup record, beside the full copy it describes.
enum Fingerprint {
    static func of(_ text: String) -> String {
        of(bytes: text.utf8)
    }

    static func of(bytes: some Sequence<UInt8>) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// A file's bytes, or every file under a folder with its relative path, so adding, removing or renaming a
    /// supporting file changes the result too. Symbolic links count by where they point, not what they point at.
    static func ofTree(_ url: URL, fileManager: FileManager = .default) throws -> String {
        var bytes: [UInt8] = []
        func add(_ relative: String, _ entry: URL) throws {
            bytes += Array(relative.utf8) + [0]
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: entry.path) {
                bytes += Array("link:\(destination)".utf8) + [0]
            } else if !isDirectory(entry, fileManager: fileManager) {
                bytes += Array(try Data(contentsOf: entry)) + [0]
            }
        }
        guard isDirectory(url, fileManager: fileManager) else {
            try add("", url)
            return of(bytes: bytes)
        }
        let paths = try fileManager.subpathsOfDirectory(atPath: url.path).sorted()
        for path in paths {
            try add(path, url.appendingPathComponent(path))
        }
        return of(bytes: bytes)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Key order doesn't change the result, so reformatting a file isn't reported as a change.
    static func of(json value: Any) -> String {
        let wrapped: [Any] = [value]
        guard JSONSerialization.isValidJSONObject(wrapped),
              let data = try? JSONSerialization.data(withJSONObject: wrapped, options: [.sortedKeys]),
              let text = String(bytes: data, encoding: .utf8) else {
            return of(String(describing: value))
        }
        return of(text)
    }
}
