import Foundation

/// FNV-1a hashes for noticing that content changed without keeping the content. Not cryptographic, so they stay in
/// memory, are never shown and are never written to disk.
enum Fingerprint {
    static func of(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
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
