import Foundation

/// Masks secrets before anything reaches the UI, logs or test output.
///
/// The rule of thumb is to over-mask: a hidden non-secret costs a click to the source file, a shown secret can't be
/// taken back. `${VAR}` references are left visible because they name a variable rather than hold its value.
public enum SecretRedactor {
    public static let mask = "••••••"

    private static let sensitiveNameFragments = [
        "token", "secret", "password", "passwd", "pwd", "apikey", "api_key", "api-key", "auth", "credential",
        "private", "session", "cookie", "bearer", "signature", "access_key", "accesskey", "client_secret",
    ]

    private static let tokenPatterns: [NSRegularExpression] = [
        "sk-[A-Za-z0-9_-]{16,}",
        "sk_(live|test)_[A-Za-z0-9]{16,}",
        "gh[pousr]_[A-Za-z0-9]{20,}",
        "github_pat_[A-Za-z0-9_]{20,}",
        "xox[abprs]-[A-Za-z0-9-]{10,}",
        "AKIA[0-9A-Z]{16}",
        "AIza[0-9A-Za-z_-]{30,}",
        "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}",
        "glpat-[A-Za-z0-9_-]{20,}",
        "npm_[A-Za-z0-9]{30,}",
        "(?i)bearer\\s+[A-Za-z0-9._~+/=-]{8,}",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let variableReference = try? NSRegularExpression(pattern: "^\\$\\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\\}$")

    /// True when a key such as an env var or header name usually holds a secret.
    public static func isSensitiveName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return sensitiveNameFragments.contains { lowered.contains($0) } || lowered == "key" || lowered.hasSuffix("_key") || lowered.hasSuffix("-key")
    }

    /// Masks a value whose key is known to be sensitive (header values, env values), keeping `${VAR}` references.
    public static func maskValue(_ value: String) -> String {
        if isVariableReference(value) { return value }
        return value.isEmpty ? value : mask
    }

    /// Masks anything that looks like a token inside free text such as a command line argument.
    public static func redactText(_ text: String) -> String {
        var result = text
        for pattern in tokenPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: mask)
        }
        return result
    }

    /// Redacts command line arguments: values that follow a sensitive flag, `--flag=value` forms, and token-like strings.
    public static func redactArguments(_ arguments: [String]) -> [String] {
        var redacted: [String] = []
        var maskNext = false
        for argument in arguments {
            if maskNext {
                redacted.append(isVariableReference(argument) ? argument : mask)
                maskNext = false
                continue
            }
            if argument.hasPrefix("-"), let equals = argument.firstIndex(of: "=") {
                let flag = String(argument[..<equals])
                let value = String(argument[argument.index(after: equals)...])
                if isSensitiveName(flag) {
                    redacted.append("\(flag)=\(maskValue(value))")
                    continue
                }
            } else if argument.hasPrefix("-"), isSensitiveName(argument) {
                redacted.append(argument)
                maskNext = true
                continue
            }
            redacted.append(redactText(argument))
        }
        return redacted
    }

    /// Removes user info and sensitive query values from a URL.
    public static func redactURL(_ text: String) -> String {
        guard var components = URLComponents(string: text), components.scheme != nil else { return redactText(text) }
        if components.password != nil { components.password = mask }
        if let user = components.user, !user.isEmpty {
            components.user = mask
        }
        if let items = components.queryItems {
            components.queryItems = items.map { item in
                guard let value = item.value, isSensitiveName(item.name) || redactText(value) != value else { return item }
                return URLQueryItem(name: item.name, value: maskValue(value))
            }
        }
        let rebuilt = components.string ?? text
        return redactText(rebuilt.replacingOccurrences(of: "%E2%80%A2", with: "•"))
    }

    /// Redacts a dictionary of strings (headers, env), masking every value whose key looks sensitive and any token-shaped value.
    public static func redactMap(_ map: [String: String], maskAllValues: Bool) -> [(key: String, value: String)] {
        map.keys.sorted().map { key in
            let value = map[key] ?? ""
            if maskAllValues || isSensitiveName(key) {
                return (key, maskValue(value))
            }
            return (key, redactText(value))
        }
    }

    private static func isVariableReference(_ value: String) -> Bool {
        guard let variableReference else { return false }
        return variableReference.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
