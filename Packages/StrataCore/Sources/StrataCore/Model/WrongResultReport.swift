import Foundation

/// A GitHub issue reporting that Strata got an item wrong. The user reads it before their browser opens it; Strata itself
/// sends nothing. Home paths become `~` and anything that looks like a secret is masked.
public struct WrongResultReport: Hashable, Identifiable, Sendable {
    public var id: URL { url }
    public let title: String
    public let body: String
    /// A new-issue link with the title and body filled in, short enough for GitHub to accept.
    public let url: URL

    /// GitHub turns away new-issue links much past 8 KB, and percent-encoding can triple a character.
    static let maximumEncodedBodyLength = 6000

    public init(item: ConfigItem, in report: InspectionReport, strataVersion: String, macOSVersion: String, homeDirectory: URL) {
        let home = homeDirectory.standardizedFileURL.path
        func clean(_ text: String) -> String {
            let shortened = home.count > 1 ? text.replacingOccurrences(of: home, with: "~") : text
            return SecretRedactor.redactText(shortened)
        }
        let name = item.invocation ?? item.name

        var lines = [
            "**What Strata showed**",
            "",
            "- \(item.kind.title) `\(clean(name))`, \(item.scope.title) scope",
            "- Status: \(item.applicability.title)",
            "- Defined in: `\(clean(item.source.path))`" + (item.source.keyPath.map { " at `\(clean($0))`" } ?? ""),
        ]
        if !item.explanation.isEmpty {
            lines += ["- Why, as Strata explained it:"] + item.explanation.map { "  > \(clean($0))" }
        }
        let competing = report.definitions(competingWith: item)
        if competing.count > 1 {
            lines.append("- Competing definitions, in the order Strata ranked them:")
            for (index, definition) in competing.enumerated() {
                lines.append("  \(index + 1). \(definition.scope.title) · `\(clean(definition.source.path))` · \(definition.applicability.title)")
            }
        }
        lines += [
            "",
            "**What Claude Code actually did**",
            "",
            "<!-- What happened instead, and how you checked (for example /skills, /agents, /mcp, /plugin or /hooks). -->",
            "",
            "**Environment**",
            "",
            "- Strata \(strataVersion)",
            "- macOS \(macOSVersion)",
        ]

        title = "[Bug] Wrong result for \(item.kind.title.lowercased()) \(clean(name))"
        body = Self.fitting(lines.joined(separator: "\n"))
        let query = "title=\(Self.encode(title))&body=\(Self.encode(body))"
        url = URL(string: "https://github.com/\(UpdateChecker.repository)/issues/new?\(query)")!
    }

    /// Only RFC 3986 unreserved characters stay as they are, so `&`, `=`, `+` and `#` in the text can't break the link.
    static func encode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Trims the body from the end until it fits, saying it was trimmed.
    static func fitting(_ body: String) -> String {
        func encodedLength(_ text: String) -> Int { encode(text).count }
        guard encodedLength(body) > maximumEncodedBodyLength else { return body }
        let note = "\n\n_Trimmed to fit a GitHub link. Add anything missing by hand._"
        var trimmed = Substring(body)
        while !trimmed.isEmpty, encodedLength(String(trimmed) + note) > maximumEncodedBodyLength {
            trimmed = trimmed.dropLast(max(1, trimmed.count / 10))
        }
        return String(trimmed) + note
    }
}
