import Foundation

/// A marketplace Claude Code knows about, from `~/.claude/plugins/known_marketplaces.json`.
public struct Marketplace: Hashable, Sendable {
    public let name: String
    /// Where `claude plugin marketplace update` fetches it from: a GitHub repository, a URL or a path.
    public let source: String
    public let location: URL
}

/// Whether a plugin's marketplace offers a newer version, from the marketplace copy Claude Code keeps on disk.
public struct PluginUpdate: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case upToDate
        case available
        /// Strata can't tell without fetching, which it never does. The text says why.
        case unknown(String)
    }

    public let installed: String?
    public let latest: String?
    public let status: Status
    /// The documented command that updates it, for the user to run in Terminal.
    public let command: String
}

/// Reads installed and offered plugin versions. Nothing here touches the network: refreshing marketplaces and updating
/// plugins are Claude Code commands the user runs, and Strata rescans when they change files.
public enum PluginUpdates {
    /// Refreshes every marketplace's listing without changing installed plugins.
    public static let refreshCommand = "claude plugin marketplace update"

    public static func marketplaces(environment: ScanEnvironment) -> [Marketplace] {
        let plugins = environment.claudeDirectory.appendingPathComponent("plugins")
        guard let data = try? Data(contentsOf: plugins.appendingPathComponent("known_marketplaces.json")),
              let known = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return known.keys.sorted().compactMap { name in
            guard let entry = known[name] as? [String: Any] else { return nil }
            let location = (entry["installLocation"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? plugins.appendingPathComponent("marketplaces/\(name)", isDirectory: true)
            return Marketplace(name: name, source: describe(entry["source"]), location: location.standardizedFileURL)
        }
    }

    /// Nil for a plugin that isn't installed from a marketplace.
    public static func check(_ plugin: ConfigItem, environment: ScanEnvironment) -> PluginUpdate? {
        guard plugin.kind == .plugin, plugin.stage != .declared, let marketplaceName = plugin.origin,
              let entryName = plugin.name.split(separator: "@", maxSplits: 1).first.map(String.init)
        else { return nil }
        let scope = plugin.metadataValue("Install scope") ?? "user"
        let command = FixPlanner.command("update", plugin: plugin.name) + (["user", "project", "local", "managed"].contains(scope) ? " --scope \(scope)" : "")
        let installed = plugin.metadataValue("Version")
        func result(_ latest: String?, _ status: PluginUpdate.Status) -> PluginUpdate {
            PluginUpdate(installed: installed, latest: latest, status: status, command: command)
        }

        guard let marketplace = marketplaces(environment: environment).first(where: { $0.name == marketplaceName }) else {
            return result(nil, .unknown("Claude Code has no record of the \(marketplaceName) marketplace on this Mac."))
        }
        let listing = marketplace.location.appendingPathComponent(".claude-plugin/marketplace.json")
        guard let data = try? Data(contentsOf: listing) else {
            return result(nil, .unknown("There's no local copy of the \(marketplaceName) marketplace. Refresh it to see what it offers."))
        }
        guard let entries = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["plugins"] as? [[String: Any]] else {
            return result(nil, .unknown("The \(marketplaceName) marketplace's listing couldn't be read."))
        }
        guard let entry = entries.last(where: { $0["name"] as? String == entryName }) else {
            return result(nil, .unknown("The \(marketplaceName) marketplace no longer lists \(entryName)."))
        }

        // Claude Code takes the plugin's own manifest version first, then the marketplace entry's.
        var latest: String?
        if let path = entry["source"] as? String {
            let folder = marketplace.location.appendingPathComponent(path).standardizedFileURL
            guard folder.path == marketplace.location.path || folder.path.hasPrefix(marketplace.location.path + "/") else {
                return result(nil, .unknown("Its marketplace entry points outside the marketplace, so Strata didn't read it."))
            }
            let manifest = (try? Data(contentsOf: folder.appendingPathComponent(".claude-plugin/plugin.json")))
                .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            latest = manifest?["version"] as? String
        }
        latest = latest ?? entry["version"] as? String
        guard let latest else {
            return result(nil, .unknown("The marketplace doesn't state a version, so Claude Code compares commits, which Strata can't see."))
        }
        guard let installed else { return result(latest, .unknown("Strata couldn't read the installed version.")) }
        return result(latest, isNewer(latest, than: installed) ? .available : .upToDate)
    }

    /// Versions that both parse are compared by Semantic Versioning. Anything else, such as two commit hashes, counts as
    /// newer when it differs, because the marketplace copy is what Claude Code would install.
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        if let new = SemanticVersion(latest), let old = SemanticVersion(installed) { return new > old }
        return latest != installed
    }

    private static func describe(_ source: Any?) -> String {
        guard let source = source as? [String: Any] else { return (source as? String) ?? "unknown source" }
        for key in ["repo", "url", "path", "package"] {
            if let value = source[key] as? String { return value }
        }
        return (source["source"] as? String) ?? "unknown source"
    }
}
