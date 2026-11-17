import Foundation

/// Edits one entry in JSON text without touching anything else, so a file Claude Code also writes keeps its layout,
/// key order and every other byte. Paths are object keys from the root, such as `["mcpServers", "github"]`.
public enum JSONTextEdit {
    public enum Failure: Error, Equatable {
        case malformed
        case notFound
    }

    /// The value's JSON text at `path`, or nil if there's no such entry.
    public static func valueText(at path: [String], in text: String) -> String? {
        let bytes = Array(text.utf8)
        guard let (_, member) = try? locate(path, in: bytes) else { return nil }
        return try? string(bytes[member.value])
    }

    /// Removes the member at `path`, with its comma. Returns the new text and the removed `"key": value` for undo.
    public static func removeMember(at path: [String], in text: String) throws -> (text: String, removed: String) {
        var bytes = Array(text.utf8)
        let (object, member) = try locate(path, in: bytes)
        let position = object.members.lastIndex { $0.keyStart == member.keyStart } ?? 0
        let range: Range<Int>
        if position + 1 < object.members.count {
            range = member.keyStart..<object.members[position + 1].keyStart
        } else if position > 0 {
            range = object.members[position - 1].value.upperBound..<member.value.upperBound
        } else {
            range = (object.open + 1)..<object.close
        }
        let removed = try string(bytes[member.keyStart..<member.value.upperBound])
        bytes.removeSubrange(range)
        return (try string(bytes[...]), removed)
    }

    /// Replaces the value at `path` with `value`, which must already be JSON text. Returns the new text and the old value.
    public static func replaceValue(at path: [String], with value: String, in text: String) throws -> (text: String, old: String) {
        var bytes = Array(text.utf8)
        let (_, member) = try locate(path, in: bytes)
        let old = try string(bytes[member.value])
        bytes.replaceSubrange(member.value, with: Array(value.utf8))
        return (try string(bytes[...]), old)
    }

    /// Adds `member` (`"key": value`) as the last member of the object at `path`, indented like its first member.
    public static func insertMember(_ member: String, intoObjectAt path: [String], in text: String) throws -> String {
        var bytes = Array(text.utf8)
        let object: Object
        if path.isEmpty {
            var parser = Parser(bytes: bytes)
            parser.skipWhitespace()
            object = try parser.object()
        } else {
            let (_, parent) = try locate(path, in: bytes)
            var parser = Parser(bytes: bytes, index: parent.value.lowerBound)
            object = try parser.object()
        }
        let insertion: [UInt8]
        let position: Int
        if let last = object.members.last, let first = object.members.first {
            let separator = Array(bytes[(object.open + 1)..<first.keyStart])
            insertion = Array(",".utf8) + separator + Array(member.utf8)
            position = last.value.upperBound
        } else {
            insertion = Array(member.utf8)
            position = object.open + 1
        }
        bytes.insert(contentsOf: insertion, at: position)
        return try string(bytes[...])
    }

    // MARK: - Locating

    struct Member {
        let key: String
        let keyStart: Int
        let value: Range<Int>
    }

    struct Object {
        let open: Int
        let close: Int
        let members: [Member]
    }

    /// The object holding the last key in `path`, and that member. A repeated key resolves to its last copy, as JSON.parse does.
    static func locate(_ path: [String], in bytes: [UInt8]) throws -> (Object, Member) {
        guard let lastKey = path.last else { throw Failure.notFound }
        var parser = Parser(bytes: bytes)
        parser.skipWhitespace()
        var object = try parser.object()
        for key in path.dropLast() {
            guard let member = object.members.last(where: { $0.key == key }) else { throw Failure.notFound }
            parser.index = member.value.lowerBound
            guard parser.peek == UInt8(ascii: "{") else { throw Failure.notFound }
            object = try parser.object()
        }
        guard let member = object.members.last(where: { $0.key == lastKey }) else { throw Failure.notFound }
        return (object, member)
    }

    /// Every edit cuts at ASCII punctuation, so this can't fail on text that came from a String. If it ever did, the edit
    /// stops rather than writing replacement characters into someone's config.
    private static func string(_ bytes: ArraySlice<UInt8>) throws -> String {
        guard let text = String(bytes: bytes, encoding: .utf8) else { throw Failure.malformed }
        return text
    }

    struct Parser {
        let bytes: [UInt8]
        var index = 0

        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func skipWhitespace() {
            while let byte = peek, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { index += 1 }
        }

        mutating func value() throws -> Range<Int> {
            skipWhitespace()
            let start = index
            switch peek {
            case UInt8(ascii: "{"): _ = try object()
            case UInt8(ascii: "["): try array()
            case UInt8(ascii: "\""): _ = try string()
            case .some: try literal()
            case nil: throw Failure.malformed
            }
            return start..<index
        }

        mutating func object() throws -> Object {
            guard peek == UInt8(ascii: "{") else { throw Failure.malformed }
            let open = index
            index += 1
            var members: [Member] = []
            skipWhitespace()
            if peek == UInt8(ascii: "}") {
                index += 1
                return Object(open: open, close: index - 1, members: [])
            }
            while true {
                skipWhitespace()
                let keyStart = index
                let key = try string()
                skipWhitespace()
                guard peek == UInt8(ascii: ":") else { throw Failure.malformed }
                index += 1
                members.append(Member(key: key, keyStart: keyStart, value: try value()))
                skipWhitespace()
                switch peek {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "}"):
                    index += 1
                    return Object(open: open, close: index - 1, members: members)
                default: throw Failure.malformed
                }
            }
        }

        mutating func array() throws {
            index += 1
            skipWhitespace()
            if peek == UInt8(ascii: "]") {
                index += 1
                return
            }
            while true {
                _ = try value()
                skipWhitespace()
                switch peek {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "]"):
                    index += 1
                    return
                default: throw Failure.malformed
                }
            }
        }

        /// Reads a string and returns it decoded, so keys with escapes compare correctly.
        mutating func string() throws -> String {
            guard peek == UInt8(ascii: "\"") else { throw Failure.malformed }
            let start = index
            index += 1
            while let byte = peek {
                if byte == UInt8(ascii: "\\") {
                    index += 2
                    continue
                }
                index += 1
                if byte == UInt8(ascii: "\"") {
                    let data = Data(bytes[start..<index])
                    guard let decoded = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String else {
                        throw Failure.malformed
                    }
                    return decoded
                }
            }
            throw Failure.malformed
        }

        mutating func literal() throws {
            let start = index
            while let byte = peek, !(byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09), byte != UInt8(ascii: ","),
                  byte != UInt8(ascii: "}"), byte != UInt8(ascii: "]") {
                index += 1
            }
            guard index > start else { throw Failure.malformed }
        }
    }
}
