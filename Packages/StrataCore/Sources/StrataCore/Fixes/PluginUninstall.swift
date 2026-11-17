import Foundation

/// `claude plugin uninstall`, which Strata runs for the user once they approve it, because only Claude Code can remove a
/// plugin's install record, options and secrets safely. It runs without a shell, so nothing in a plugin's ID reaches one.
/// (https://code.claude.com/docs/en/plugins/cli-reference#plugin-uninstall)
public struct PluginUninstall: Identifiable, Hashable, Sendable {
    public let pluginID: String
    /// `user`, `project` or `local`: the settings file the command writes to.
    public let scope: String
    /// Passes `--keep-data`, so `~/.claude/plugins/data/<id>/` survives and a reinstall picks up where it left off.
    public var keepsData = true

    public var id: String { "\(pluginID) \(scope)" }

    /// nil when the plugin isn't installed at a scope the command takes, or its ID would read as an option.
    public init?(_ plugin: ConfigItem) {
        guard FixPlanner.uninstallCommand(for: plugin) != nil, !plugin.name.isEmpty, !plugin.name.hasPrefix("-") else { return nil }
        pluginID = plugin.name
        scope = plugin.metadataValue("Install scope") ?? "user"
    }

    public var arguments: [String] {
        ["plugin", "uninstall", pluginID, "--scope", scope] + (keepsData ? ["--keep-data"] : [])
    }

    /// The same command, quoted as you'd type it in Terminal.
    public var command: String {
        FixPlanner.command("uninstall", plugin: pluginID) + " --scope \(scope)" + (keepsData ? " --keep-data" : "")
    }

    /// Strata can't undo an uninstall. This brings the plugin back.
    public var reinstallCommand: String {
        FixPlanner.command("install", plugin: pluginID) + " --scope \(scope)"
    }

    /// Where Claude Code's installers put `claude`, in the order Strata looks. Apps don't get the shell's PATH.
    /// ponytail: a fixed list. Ask the login shell for its PATH if people install claude somewhere else.
    public static func executableCandidates(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
    }
}
