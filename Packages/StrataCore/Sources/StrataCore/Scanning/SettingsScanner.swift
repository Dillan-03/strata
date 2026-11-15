import Foundation

/// One settings file and its parsed contents.
struct SettingsLayer {
    let scope: Scope
    let label: String
    let url: URL
    let values: [String: Any]
    /// Lower is higher precedence, matching the documented order: managed, local, project, user.
    let precedence: Int

    func dictionary(_ key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func strings(_ key: String) -> [String]? { (values[key] as? [Any])?.compactMap { $0 as? String } }
    func bool(_ key: String) -> Bool? { JSONValue.bool(values[key]) }
}

/// Reads every settings file Claude Code uses and lists each top-level key as an item.
struct SettingsScanner {
    let context: ScanContext

    private struct Location {
        let scope: Scope
        let label: String
        let url: URL
        let precedence: Int
    }

    /// Settings files that exist and parse, highest precedence first.
    func layers() -> [SettingsLayer] {
        var locations: [Location] = []
        if let managed = context.managedDirectory {
            locations.append(Location(scope: .managed, label: "Managed settings", url: managed.appendingPathComponent("managed-settings.json"), precedence: 1))
        }
        let project = context.repositoryClaudeDirectory
        locations.append(Location(scope: .local, label: "Project local settings", url: project.appendingPathComponent("settings.local.json"), precedence: 3))
        locations.append(Location(scope: .project, label: "Shared project settings", url: project.appendingPathComponent("settings.json"), precedence: 4))
        locations.append(Location(scope: .user, label: "User settings", url: context.claudeDirectory.appendingPathComponent("settings.json"), precedence: 5))

        return locations.compactMap { location in
            guard let values = context.readJSON(location.url, label: location.label) else { return nil }
            return SettingsLayer(scope: location.scope, label: location.label, url: location.url, values: values, precedence: location.precedence)
        }
    }

    func items(from layers: [SettingsLayer]) -> [ConfigItem] {
        layers.flatMap { layer in
            layer.values.keys.sorted().map { key in
                var item = ConfigItem(
                    kind: .setting,
                    name: key,
                    summary: Self.summary(of: layer.values[key], key: key),
                    scope: layer.scope,
                    source: SourceLocation(path: layer.url.path, keyPath: key),
                    metadata: [
                        Metadatum("File", context.displayPath(layer.url)),
                        Metadatum("Value", Self.summary(of: layer.values[key], key: key)),
                        Metadatum("Value type", Self.typeName(of: layer.values[key])),
                    ]
                )
                item.fingerprint = Fingerprint.of(json: layer.values[key] ?? NSNull())
                context.capture(layer.values[key] ?? NSNull(), root: key, for: item.id)
                return item
            }
        }
    }

    static func typeName(of value: Any?) -> String {
        switch value {
        case is [Any]: "list"
        case is [String: Any]: "object"
        case let value where JSONValue.isBoolean(value): "boolean"
        case is NSNumber: "number"
        case is String: "string"
        case is NSNull: "null"
        default: "unknown"
        }
    }

    /// A short, secret-free description of a settings value.
    static func summary(of value: Any?, key: String) -> String {
        switch value {
        case let dictionary as [String: Any]:
            if key == "env" {
                let names = dictionary.keys.sorted()
                return names.isEmpty ? "No variables" : "\(names.count) variable\(names.count == 1 ? "" : "s"): " + names.joined(separator: ", ")
            }
            if key == "hooks" {
                let events = dictionary.keys.sorted()
                return events.isEmpty ? "No hooks" : "Hooks for " + events.joined(separator: ", ")
            }
            let keys = dictionary.keys.sorted()
            return keys.isEmpty ? "Empty object" : keys.joined(separator: ", ")
        case let array as [Any]:
            let strings = array.compactMap { $0 as? String }
            if strings.count == array.count, !strings.isEmpty, strings.count <= 6, !SecretRedactor.isSensitiveName(key) {
                return strings.map(SecretRedactor.redactText).joined(separator: ", ")
            }
            return "\(array.count) entr\(array.count == 1 ? "y" : "ies")"
        case let string as String:
            return SecretRedactor.isSensitiveName(key) ? SecretRedactor.maskValue(string) : SecretRedactor.redactText(string)
        case let number as NSNumber:
            if JSONValue.isBoolean(number) { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case is NSNull:
            return "null"
        default:
            return "—"
        }
    }
}
