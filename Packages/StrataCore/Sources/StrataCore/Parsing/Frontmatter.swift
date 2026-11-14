import Foundation

/// The YAML frontmatter at the top of a skill, command, agent or rule file.
///
/// This is a deliberately small parser for the subset Claude Code files use: top-level `key: value` pairs, quoted
/// strings, booleans, inline `[a, b]` lists, `- item` lists and `|`/`>` block scalars. Nested maps are kept as raw text.
public struct Frontmatter: Hashable, Sendable {
    public enum Value: Hashable, Sendable {
        case string(String)
        case bool(Bool)
        case list([String])

        public var displayText: String {
            switch self {
            case .string(let value): value
            case .bool(let value): value ? "true" : "false"
            case .list(let values): values.joined(separator: ", ")
            }
        }
    }

    public enum ParseError: Error, Equatable, Sendable {
        case unterminated
    }

    public let values: [String: Value]
    /// Keys in the order they appear in the file.
    public let orderedKeys: [String]

    public static let empty = Frontmatter(values: [:], orderedKeys: [])

    public init(values: [String: Value], orderedKeys: [String]) {
        self.values = values
        self.orderedKeys = orderedKeys
    }

    public subscript(key: String) -> Value? { values[key] }

    public func string(_ key: String) -> String? {
        guard let value = values[key] else { return nil }
        let text = value.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public func bool(_ key: String) -> Bool? {
        switch values[key] {
        case .bool(let value): value
        case .string(let value): Self.boolean(from: value)
        default: nil
        }
    }

    public func list(_ key: String) -> [String]? {
        switch values[key] {
        case .list(let values): values
        case .string(let value):
            value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        default: nil
        }
    }

    /// Splits a Markdown document into frontmatter and body. Documents without frontmatter return `.empty`.
    public static func parse(document: String) throws -> (frontmatter: Frontmatter, body: String) {
        let normalised = document.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalised.components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("\u{FEFF}") {
            lines[0] = String(first.dropFirst())
        }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (.empty, normalised)
        }
        guard let closing = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) else {
            throw ParseError.unterminated
        }
        let frontmatter = parseBlock(Array(lines[1..<closing]))
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return (frontmatter, body)
    }

    static func parseBlock(_ lines: [String]) -> Frontmatter {
        var values: [String: Value] = [:]
        var order: [String] = []
        var index = 0

        func record(_ key: String, _ value: Value) {
            if values[key] == nil { order.append(key) }
            values[key] = value
        }

        while index < lines.count {
            let line = lines[index]
            index += 1
            guard !line.isEmpty, !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let rawValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            var continuation: [String] = []
            while index < lines.count, lines[index].isEmpty || lines[index].hasPrefix(" ") || lines[index].hasPrefix("\t") {
                continuation.append(lines[index])
                index += 1
            }
            while let last = continuation.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                continuation.removeLast()
            }

            if rawValue == "|" || rawValue == ">" || rawValue.hasPrefix("|") || rawValue.hasPrefix(">") {
                let text = dedent(continuation)
                record(key, .string(rawValue.hasPrefix(">") ? text.replacingOccurrences(of: "\n", with: " ") : text))
            } else if rawValue.isEmpty {
                let items = continuation
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("- ") || $0 == "-" }
                    .map { unquote(String($0.dropFirst()).trimmingCharacters(in: .whitespaces)) }
                if !items.isEmpty && items.count == continuation.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count {
                    record(key, .list(items))
                } else {
                    record(key, .string(dedent(continuation)))
                }
            } else if rawValue.hasPrefix("["), rawValue.hasSuffix("]") {
                let inner = rawValue.dropFirst().dropLast()
                let items = inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                record(key, .list(items))
            } else if let boolean = boolean(from: rawValue) {
                record(key, .bool(boolean))
            } else {
                let continued = continuation.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                let joined = continued.isEmpty ? rawValue : rawValue + " " + continued
                record(key, .string(unquote(joined)))
            }
        }
        return Frontmatter(values: values, orderedKeys: order)
    }

    private static func boolean(from text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "yes", "on": true
        case "false", "no", "off": false
        default: nil
        }
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last, first == last, first == "\"" || first == "'" else {
            return text
        }
        let inner = String(text.dropFirst().dropLast())
        return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"") : inner.replacingOccurrences(of: "''", with: "'")
    }

    private static func dedent(_ lines: [String]) -> String {
        let indents = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix { $0 == " " || $0 == "\t" }.count }
        let indent = indents.min() ?? 0
        return lines.map { String($0.dropFirst(min(indent, $0.count))) }.joined(separator: "\n")
    }
}
