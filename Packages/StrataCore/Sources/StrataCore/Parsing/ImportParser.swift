import Foundation

/// Finds `@path` imports in CLAUDE.md-style files the way the Claude Code docs describe:
/// imports outside code spans and fenced blocks, relative to the importing file, with `\ ` escaping spaces.
enum ImportParser {
    static func imports(in text: String) -> [String] {
        var results: [String] = []
        var inFence = false
        var fenceMarker = ""

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarkerPrefix(trimmed) {
                if !inFence {
                    inFence = true
                    fenceMarker = marker
                } else if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                }
                continue
            }
            guard !inFence else { continue }
            results.append(contentsOf: imports(inLine: stripCodeSpans(rawLine)))
        }
        return results
    }

    private static func fenceMarkerPrefix(_ line: String) -> String? {
        for marker in ["```", "~~~"] where line.hasPrefix(marker) {
            return marker
        }
        return nil
    }

    private static func stripCodeSpans(_ line: String) -> String {
        var output = ""
        var inSpan = false
        for character in line {
            if character == "`" {
                inSpan.toggle()
                output.append(" ")
            } else {
                output.append(inSpan ? " " : character)
            }
        }
        return output
    }

    private static func imports(inLine line: String) -> [String] {
        var results: [String] = []
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let isStart = characters[index] == "@" && (index == 0 || characters[index - 1].isWhitespace || "([".contains(characters[index - 1]))
            guard isStart else {
                index += 1
                continue
            }
            var path = ""
            var cursor = index + 1
            while cursor < characters.count {
                let character = characters[cursor]
                if character == "\\", cursor + 1 < characters.count, characters[cursor + 1] == " " {
                    path.append(" ")
                    cursor += 2
                    continue
                }
                if character.isWhitespace || character == "\"" || character == "'" || character == ")" || character == "]" { break }
                path.append(character)
                cursor += 1
            }
            while let last = path.last, ",;:!?".contains(last) {
                path.removeLast()
            }
            if path.hasSuffix("."), !path.hasSuffix("..") {
                path.removeLast()
            }
            if isPlausiblePath(path) {
                results.append(path)
            }
            index = cursor
        }
        return results
    }

    private static func isPlausiblePath(_ path: String) -> Bool {
        guard let first = path.first else { return false }
        return first.isLetter || first.isNumber || "./~_-".contains(first)
    }

    /// Resolves an import relative to the file that contains it.
    static func resolve(_ path: String, from file: URL, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return file.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
    }

    /// True for imports that look like file paths rather than an `@mention` in prose.
    static func looksLikeFilePath(_ path: String) -> Bool {
        path.contains("/") || path.contains(".") || path.hasPrefix("~")
    }
}
