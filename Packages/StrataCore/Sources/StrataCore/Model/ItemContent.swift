import Foundation

/// What defines an item, with secrets masked, kept so a change between two scans can be shown as a diff.
///
/// Masking happens before content leaves the scan, so unmasked values never reach a report, the UI or a log.
public enum ItemContent: Hashable, Codable, Sendable {
    /// A Markdown file: a skill, command, subagent or instruction file.
    case text(String)
    /// A JSON entry, such as an MCP server, a setting's value or a plugin's record, as key paths and display values.
    case keyed([KeyedValue])

    /// Whether any part of the content is hidden behind the mask.
    public var hasMaskedValues: Bool {
        switch self {
        case .text(let text): text.contains(SecretRedactor.mask)
        case .keyed(let values): values.contains(where: \.isMasked)
        }
    }

    static func document(_ text: String) -> ItemContent {
        .text(SecretRedactor.redactDocument(text))
    }

    /// Flattens a JSON value into key paths. Objects and lists of objects are walked; scalars and lists of scalars
    /// are leaves. `root` names the value when it sits under a key, as a setting does.
    static func keyed(_ value: Any, root: String? = nil) -> ItemContent {
        var values: [KeyedValue] = []
        flatten(value, path: root.map { [$0] } ?? [], into: &values)
        return .keyed(values)
    }

    private static func flatten(_ value: Any, path: [String], into values: inout [KeyedValue]) {
        if let object = value as? [String: Any], !object.isEmpty {
            for key in object.keys.sorted() {
                flatten(object[key] ?? NSNull(), path: path + [key], into: &values)
            }
            return
        }
        if let array = value as? [Any], array.contains(where: { $0 is [String: Any] || $0 is [Any] }) {
            for (index, element) in array.enumerated() {
                let indexed = path.dropLast() + [(path.last ?? "") + "[\(index)]"]
                flatten(element, path: Array(indexed), into: &values)
            }
            return
        }
        let display = Self.display(value, path: path)
        values.append(KeyedValue(
            path: path.joined(separator: "."),
            display: display,
            isMasked: display.contains(SecretRedactor.mask),
            fingerprint: Fingerprint.of(json: value)
        ))
    }

    /// A value as Strata may show it. Everything under `env` or `headers`, and anything whose key looks sensitive,
    /// is masked; other strings are checked for token-shaped text, URLs for credentials, and `args` for secret flags.
    private static func display(_ value: Any, path: [String]) -> String {
        let key = Self.key(path.last ?? "")
        let isSecretMap = path.dropLast().contains { ["env", "headers"].contains(Self.key($0).lowercased()) }
        let isSensitive = isSecretMap || SecretRedactor.isSensitiveName(key)

        func text(_ string: String) -> String {
            if isSensitive { return SecretRedactor.maskValue(string) }
            if key == "url" || string.contains("://") { return SecretRedactor.redactURL(string) }
            return SecretRedactor.redactText(string)
        }

        switch value {
        case let string as String:
            return string.isEmpty ? "\"\"" : text(string)
        case let array as [Any]:
            let strings = array.compactMap { $0 as? String }
            let shown: [String]
            if strings.count == array.count {
                shown = (key == "args" && !isSensitive ? SecretRedactor.redactArguments(strings) : strings.map(text)).map { "\"\($0)\"" }
            } else {
                shown = array.map { scalar($0) ?? "…" }
            }
            return "[" + shown.joined(separator: ", ") + "]"
        case is [String: Any]:
            return "{}"
        default:
            return scalar(value) ?? "—"
        }
    }

    private static func scalar(_ value: Any) -> String? {
        switch value {
        case let bool where JSONValue.isBoolean(bool): JSONValue.bool(bool) == true ? "true" : "false"
        case let number as NSNumber: number.stringValue
        case is NSNull: "null"
        case let string as String: "\"\(SecretRedactor.redactText(string))\""
        default: nil
        }
    }

    /// A path component without its list index: `hooks[0]` → `hooks`.
    private static func key(_ component: String) -> String {
        component.firstIndex(of: "[").map { String(component[..<$0]) } ?? component
    }
}

/// One leaf of a JSON entry.
public struct KeyedValue: Hashable, Codable, Sendable {
    /// Where the value sits, such as `env.GITHUB_TOKEN` or `hooks.PreToolUse[0].matcher`.
    public let path: String
    /// The value as Strata may show it.
    public let display: String
    /// True when `display` hides part or all of the value.
    public let isMasked: Bool
    /// Hash of the unmasked value, so a change behind the mask is still noticed. Never shown.
    let fingerprint: String
}
