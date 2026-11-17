import Foundation

/// A `MAJOR.MINOR.PATCH` version with an optional pre-release suffix, as in Semantic Versioning 2.0.0.
public struct SemanticVersion: Comparable, CustomStringConvertible, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// The part after `-`, such as `beta.1`. Empty for a release.
    public let preRelease: String

    /// Parses `1.2.3`, `v1.2.3`, `1.2.3-beta.1` and `1.2.3+build.5`. Build metadata is ignored, as Semantic Versioning says.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }
        let parts = rest.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = Self.number(numbers[0]), let minor = Self.number(numbers[1]), let patch = Self.number(numbers[2])
        else { return nil }
        if parts.count == 2, parts[1].isEmpty { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        preRelease = parts.count == 2 ? String(parts[1]) : ""
    }

    public var isPreRelease: Bool { !preRelease.isEmpty }

    public var description: String {
        "\(major).\(minor).\(patch)" + (isPreRelease ? "-\(preRelease)" : "")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        // A pre-release comes before its release.
        // ponytail: two pre-releases compare as text, which is right until a number reaches two digits (beta.10 < beta.9).
        // Update checks never see two, because GitHub's latest release is never a pre-release.
        switch (lhs.isPreRelease, rhs.isPreRelease) {
        case (true, false): return true
        case (false, true): return false
        default: return lhs.preRelease < rhs.preRelease
        }
    }

    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber), text == "0" || text.first != "0" else { return nil }
        return Int(text)
    }
}

/// An HTTP response, without depending on `URLSession`, so StrataCore stays free of networking on Linux.
public struct HTTPReply: Sendable {
    public let status: Int
    /// Header names in lowercase.
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.body = body
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(SemanticVersion)
    case available(SemanticVersion, releaseNotes: URL)
    case failed(UpdateCheckFailure)
}

public enum UpdateCheckFailure: Equatable, Sendable {
    case unreachable
    case rateLimited(until: Date?)
    case noRelease
    case unexpectedStatus(Int)
    case malformed
    /// The running app's own version doesn't parse, which only happens in a broken build.
    case unknownCurrentVersion(String)

    public var message: String {
        switch self {
        case .unreachable:
            "Couldn't reach GitHub. Check your internet connection and try again."
        case .rateLimited(let until?):
            "GitHub is limiting requests from your network. Try again after \(until.formatted(date: .omitted, time: .shortened))."
        case .rateLimited(nil):
            "GitHub is limiting requests from your network. Try again later."
        case .noRelease:
            "GitHub has no published release of Strata yet."
        case .unexpectedStatus(let status):
            "GitHub returned an unexpected response (HTTP \(status)). Try again later."
        case .malformed:
            "GitHub's response didn't include a version Strata could read. Try again later."
        case .unknownCurrentVersion(let text):
            "This copy of Strata has an unreadable version (\(text)), so it can't be compared."
        }
    }
}

/// Asks GitHub for Strata's latest release, once per call. It never downloads or installs anything.
public struct UpdateChecker: Sendable {
    public static let repository = "Dillan-03/strata"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// Automatic checks, when the user turns them on, run at most this often.
    public static let automaticCheckInterval: TimeInterval = 86_400

    /// Due a day after the last automatic check, or straight away if the clock has gone back past it.
    public static func isAutomaticCheckDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        return now < lastChecked || now.timeIntervalSince(lastChecked) >= automaticCheckInterval
    }

    private let fetch: @Sendable (URL) async throws -> HTTPReply

    /// `fetch` makes the one request. Any error it throws counts as GitHub being unreachable.
    public init(fetch: @escaping @Sendable (URL) async throws -> HTTPReply) {
        self.fetch = fetch
    }

    public func check(currentVersion: String) async -> UpdateCheckResult {
        guard let current = SemanticVersion(currentVersion) else { return .failed(.unknownCurrentVersion(currentVersion)) }
        guard let reply = try? await fetch(Self.latestReleaseAPI) else { return .failed(.unreachable) }
        return Self.result(for: reply, current: current)
    }

    public static func result(for reply: HTTPReply, current: SemanticVersion) -> UpdateCheckResult {
        switch reply.status {
        case 200:
            break
        case 404:
            return .failed(.noRelease)
        case 429:
            return .failed(.rateLimited(until: resetDate(reply)))
        case 403 where reply.headers["x-ratelimit-remaining"] == "0":
            return .failed(.rateLimited(until: resetDate(reply)))
        default:
            return .failed(.unexpectedStatus(reply.status))
        }
        guard let release = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any],
              let tag = release["tag_name"] as? String,
              let latest = SemanticVersion(tag)
        else { return .failed(.malformed) }
        // The latest-release endpoint already skips drafts and pre-releases. This keeps a mislabelled one from counting.
        let isDraft = JSONValue.bool(release["draft"]) ?? false
        let isPreRelease = JSONValue.bool(release["prerelease"]) ?? false
        guard !isDraft, !isPreRelease, !latest.isPreRelease, latest > current else { return .upToDate(current) }
        // Built from the version, not taken from the response, so the link always goes to this repository's release page.
        return .available(latest, releaseNotes: URL(string: "https://github.com/\(repository)/releases/tag/v\(latest)")!)
    }

    private static func resetDate(_ reply: HTTPReply) -> Date? {
        if let reset = reply.headers["x-ratelimit-reset"].flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        return nil
    }
}
