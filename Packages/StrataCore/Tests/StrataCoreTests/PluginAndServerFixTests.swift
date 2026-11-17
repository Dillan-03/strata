@testable import StrataCore
import XCTest

/// Turning plugins off and on, removing MCP servers, and the commands Strata shows instead of running.
final class PluginAndServerFixTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private var backups: URL { fixture.home.appendingPathComponent("Library/Application Support/Strata/Backups") }
    private var globalConfig: URL { fixture.environment.globalConfigFile }

    private func writer() -> ConfigWriter {
        ConfigWriter(
            backupDirectory: backups,
            allowedRoots: FixPlanner.allowedRoots(repositoryPath: fixture.repository.path, environment: fixture.environment),
            allowedFiles: FixPlanner.allowedFiles(repositoryPath: fixture.repository.path, environment: fixture.environment)
        )
    }

    private func offer(_ kind: ItemKind, named name: String, scope: Scope? = nil) throws -> FixOffer {
        let report = fixture.inspect()
        let item = try XCTUnwrap(report.items.first { $0.kind == kind && $0.name == name && (scope == nil || $0.scope == scope) })
        return FixPlanner.change(for: item, in: report, environment: fixture.environment)
    }

    private func onlyFix(_ offer: FixOffer) throws -> ConfigFix {
        guard case .available(let fixes) = offer, fixes.count == 1 else { throw XCTSkip("Expected one fix, got \(offer)") }
        return fixes[0]
    }

    @discardableResult
    private func installPlugin(enabledIn settings: String = "settings.json", base: URL? = nil, scope: String = "user") throws -> URL {
        let root = fixture.claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit", "version": "1.0.0"])
        try fixture.write("skills/migrate/SKILL.md", in: root, Fixture.skill())
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": 2,
            "plugins": ["kit@tools": [["scope": scope, "installPath": root.path, "version": "1.0.0"]]],
        ])
        let file = (base ?? fixture.claude).appendingPathComponent(settings)
        try fixture.write(settings, in: base ?? fixture.claude, "{\n  \"model\": \"opus\",\n  \"enabledPlugins\": {\n    \"kit@tools\": true\n  }\n}\n")
        return file
    }

    // MARK: - Plugins

    func testDisablingAndEnablingAPluginFlipsOnlyItsEntry() throws {
        let settings = try installPlugin()
        let original = try String(contentsOf: settings, encoding: .utf8)
        let disable = try onlyFix(try offer(.plugin, named: "kit@tools"))
        XCTAssertEqual(disable.action, .disablePlugin)
        XCTAssertEqual(disable.pickup.timing, .reloadPlugins)

        let record = try writer().apply(disable)
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), original.replacingOccurrences(of: "\"kit@tools\": true", with: "\"kit@tools\": false"))
        XCTAssertEqual(fixture.inspect().items.first { $0.kind == .plugin }?.stage, .installed, "Strata's own scan sees it off")

        let enable = try onlyFix(try offer(.plugin, named: "kit@tools"))
        XCTAssertEqual(enable.action, .enablePlugin)
        try writer().undo(record)
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), original, "Undo puts the entry back exactly")
    }

    func testAPluginInRepositorySettingsIsEditedThere() throws {
        let settings = try installPlugin(enabledIn: "settings.local.json", base: fixture.repository.appendingPathComponent(".claude"), scope: "local")
        let fix = try onlyFix(try offer(.plugin, named: "kit@tools"))
        XCTAssertEqual(fix.targetURL.path, settings.standardizedFileURL.path)
    }

    func testAPluginWithNoEntryOffersTheCommandInstead() throws {
        try installPlugin()
        try fixture.write("settings.json", in: fixture.claude, "{}\n")
        guard case .unavailable(let reason) = try offer(.plugin, named: "kit@tools") else { return XCTFail("Expected a reason") }
        XCTAssertTrue(reason.contains("claude plugin disable kit@tools"), reason)
    }

    func testUninstallCommandIsQuotedForTheShell() throws {
        try installPlugin(scope: "project")
        let plugin = try XCTUnwrap(fixture.inspect().items.first { $0.kind == .plugin })
        XCTAssertEqual(FixPlanner.uninstallCommand(for: plugin), "claude plugin uninstall kit@tools --scope project")
        XCTAssertEqual(FixPlanner.shellQuoted("x; rm -rf ~"), "'x; rm -rf ~'")
        XCTAssertEqual(FixPlanner.shellQuoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(FixPlanner.shellQuoted(""), "''")
    }

    func testPluginUninstallRunsTheDocumentedCommandWithoutAShell() throws {
        try installPlugin(scope: "project")
        let plugin = try XCTUnwrap(fixture.inspect().items.first { $0.kind == .plugin })
        var uninstall = try XCTUnwrap(PluginUninstall(plugin))
        XCTAssertEqual(uninstall.arguments, ["plugin", "uninstall", "kit@tools", "--scope", "project", "--keep-data"])
        XCTAssertEqual(uninstall.command, "claude plugin uninstall kit@tools --scope project --keep-data")
        XCTAssertEqual(uninstall.reinstallCommand, "claude plugin install kit@tools --scope project")
        uninstall.keepsData = false
        XCTAssertEqual(uninstall.arguments.last, "project", "Without --keep-data the data folder goes too")

        let option = ConfigItem(
            kind: .plugin, name: "--prune", scope: plugin.scope, source: plugin.source, metadata: plugin.metadata, stage: plugin.stage
        )
        XCTAssertNil(PluginUninstall(option), "An ID that reads as an option must never reach the command")
    }

    // MARK: - MCP servers

    func testRemovingAProjectServerLeavesTheRestOfMcpJson() throws {
        let text = "{\n  \"mcpServers\": {\n    \"github\": {\"type\": \"http\", \"url\": \"https://api.githubcopilot.com/mcp/\"},\n    \"db\": {\"command\": \"pg\"}\n  }\n}\n"
        let file = try fixture.write(".mcp.json", in: fixture.repository, text)
        let fix = try onlyFix(try offer(.mcpServer, named: "github"))
        XCTAssertEqual(fix.action, .removeServer)

        let record = try writer().apply(fix)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{\n  \"mcpServers\": {\n    \"db\": {\"command\": \"pg\"}\n  }\n}\n")
        XCTAssertNil(fixture.inspect().items.first { $0.kind == .mcpServer && $0.name == "github" })

        try writer().undo(record)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? NSDictionary)
        XCTAssertEqual(restored, try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary))
    }

    func testRemovingALocalServerKeepsClaudeJsonPrivateAndOtherWritesSurviveUndo() throws {
        let key = fixture.repository.path
        try fixture.json(".claude.json", in: fixture.home, [
            "numStartups": 3,
            "projects": [key: ["mcpServers": ["notes": ["command": "notes-mcp", "env": ["NOTES_TOKEN": "sk-test-SECRETSECRETSECRET"]]]]],
        ])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: globalConfig.path)
        let fix = try onlyFix(try offer(.mcpServer, named: "notes", scope: .local))
        XCTAssertEqual(fix.jsonPath, ["projects", key, "mcpServers", "notes"])
        let preview = FixPreview(fix)
        XCTAssertEqual(preview.targetFiles, [".claude.json"])
        XCTAssertFalse("\(preview.diff)".contains("SECRETSECRET"), "The preview masks the server's secrets")

        let record = try writer().apply(fix)
        let permissions = try FileManager.default.attributesOfItem(atPath: globalConfig.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600, "~/.claude.json stays readable only by its owner")

        // Claude Code writes the file again before the user undoes.
        let edited = try String(contentsOf: globalConfig, encoding: .utf8).replacingOccurrences(of: "\"numStartups\" : 3", with: "\"numStartups\" : 4")
        try Data(edited.utf8).write(to: globalConfig)
        try writer().undo(record)
        let text = try String(contentsOf: globalConfig, encoding: .utf8)
        XCTAssertTrue(text.contains("\"numStartups\" : 4"), "Undo keeps what Claude Code wrote since")
        XCTAssertNotNil(JSONTextEdit.valueText(at: ["projects", key, "mcpServers", "notes"], in: text))
    }

    func testAServerEditedAfterReviewIsNotRemoved() throws {
        let file = try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "pg"]]])
        let fix = try onlyFix(try offer(.mcpServer, named: "db"))
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "pg", "args": ["--new"]]]])

        XCTAssertThrowsError(try writer().apply(fix)) { error in
            guard case FixError.changedSinceReview = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertNotNil(JSONTextEdit.valueText(at: ["mcpServers", "db"], in: try String(contentsOf: file, encoding: .utf8)))
    }

    func testUndoNeverOverwritesAServerAddedAgain() throws {
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "pg"]]])
        let record = try writer().apply(try onlyFix(try offer(.mcpServer, named: "db")))
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "other"]]])
        XCTAssertThrowsError(try writer().undo(record)) { error in
            guard case FixError.undoBlocked = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testPluginAndManagedServersAreRefused() throws {
        let report = fixture.inspect()
        for (scope, phrase) in [(Scope.plugin, "the acme plugin"), (.managed, "managed settings")] {
            let server = ConfigItem(kind: .mcpServer, name: "x", scope: scope, source: SourceLocation(path: "/tmp/x.json"), origin: "acme")
            guard case .unavailable(let reason) = FixPlanner.change(for: server, in: report, environment: fixture.environment) else {
                return XCTFail("\(scope) should be refused")
            }
            XCTAssertTrue(reason.contains(phrase), reason)
        }
    }

    func testTheWriterRefusesFilesOutsideItsList() throws {
        let elsewhere = try fixture.json("other.json", in: fixture.root, ["mcpServers": ["db": ["command": "pg"]]])
        let item = ConfigItem(kind: .mcpServer, name: "db", scope: .project, source: SourceLocation(path: elsewhere.path))
        guard case .unavailable = FixPlanner.change(for: item, in: fixture.inspect(), environment: fixture.environment) else {
            return XCTFail("Only .mcp.json and ~/.claude.json are edited")
        }
    }
}
