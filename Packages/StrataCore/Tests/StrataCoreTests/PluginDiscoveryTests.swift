import StrataCore
import XCTest

final class PluginDiscoveryTests: XCTestCase {
    private func installPlugin(_ fixture: Fixture, id: String, folder: String, manifestName: String? = nil, format: Int = 2) throws -> URL {
        let root = fixture.claude.appendingPathComponent("plugins/cache/\(folder)")
        var manifest: [String: Any] = ["version": "1.2.0", "description": "Supabase helpers"]
        if let manifestName { manifest["name"] = manifestName }
        try fixture.json(".claude-plugin/plugin.json", in: root, manifest)
        try fixture.write("skills/migrate/SKILL.md", in: root, Fixture.skill())
        try fixture.write("agents/schema.md", in: root, "---\nname: schema-designer\ndescription: Designs schemas\n---\n")
        try fixture.json(".mcp.json", in: root, ["mcpServers": ["supabase": ["command": "${CLAUDE_PLUGIN_ROOT}/bin/server"]]])
        let record: [String: Any] = ["scope": "user", "installPath": root.path, "version": "1.2.0"]
        let entry: Any = format == 2 ? [record] : record
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": format,
            "plugins": [id: entry],
        ])
        return root
    }

    func testInstalledAndEnabledPluginContributesComponents() throws {
        let fixture = try Fixture()
        _ = try installPlugin(fixture, id: "supabase-kit@tools", folder: "tools/supabase-kit/1.2.0", manifestName: "supabase-kit")
        try fixture.json(".claude/settings.json", in: fixture.home, ["enabledPlugins": ["supabase-kit@tools": true]])

        let report = fixture.inspect()
        let plugin = try report.onlyItem(.plugin, named: "supabase-kit@tools")
        XCTAssertEqual(plugin.stage, .enabled)
        XCTAssertEqual(plugin.scope, .user)
        XCTAssertEqual(plugin.metadataValue("Version"), "1.2.0")
        XCTAssertEqual(plugin.metadataValue("Contributes"), "1 skill, 1 agent, 1 MCP server")

        let skill = try report.onlyItem(.skill, named: "supabase-kit:migrate")
        XCTAssertEqual(skill.invocation, "/supabase-kit:migrate")
        XCTAssertEqual(skill.scope, .plugin)
        XCTAssertEqual(try report.onlyItem(.agent, named: "schema-designer").invocation, "supabase-kit:schema-designer")
        XCTAssertEqual(try report.onlyItem(.mcpServer, named: "supabase").origin, "supabase-kit@tools")
    }

    func testHooksFileIsRecordedAsAContribution() throws {
        let fixture = try Fixture()
        let root = try installPlugin(fixture, id: "guard@tools", folder: "tools/guard/1.0.0", manifestName: "guard")
        try fixture.json("hooks/hooks.json", in: root, ["hooks": ["PreToolUse": []]])
        try fixture.json(".claude/settings.json", in: fixture.home, ["enabledPlugins": ["guard@tools": true]])

        let plugin = try fixture.inspect().onlyItem(.plugin, named: "guard@tools")
        XCTAssertEqual(plugin.metadataValue("Hooks"), "hooks/hooks.json")
        XCTAssertEqual(plugin.metadataValue("Contributes"), "1 skill, 1 agent, 1 MCP server, hooks")
    }

    func testHooksDeclaredInManifestAreRecorded() throws {
        let fixture = try Fixture()
        let root = try installPlugin(fixture, id: "guard@tools", folder: "tools/guard/1.0.0", manifestName: "guard")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "guard", "hooks": "./config/hooks.json"])
        try fixture.json(".claude/settings.json", in: fixture.home, ["enabledPlugins": ["guard@tools": true]])

        let plugin = try fixture.inspect().onlyItem(.plugin, named: "guard@tools")
        XCTAssertEqual(plugin.metadataValue("Hooks"), "Declared in plugin.json")
    }

    func testPluginWithoutHooksHasNoHooksEntry() throws {
        let fixture = try Fixture()
        _ = try installPlugin(fixture, id: "supabase-kit@tools", folder: "tools/supabase-kit/1.2.0", manifestName: "supabase-kit")
        try fixture.json(".claude/settings.json", in: fixture.home, ["enabledPlugins": ["supabase-kit@tools": true]])

        XCTAssertNil(try fixture.inspect().onlyItem(.plugin, named: "supabase-kit@tools").metadataValue("Hooks"))
    }

    func testVersionOneInstallRecordsAreRead() throws {
        let fixture = try Fixture()
        _ = try installPlugin(fixture, id: "kit@tools", folder: "tools/kit/1.0.0", format: 1)

        XCTAssertEqual(try fixture.inspect().onlyItem(.plugin, named: "kit@tools").stage, .enabled)
    }

    func testLocalSettingOverridesProjectAndUser() throws {
        let fixture = try Fixture()
        _ = try installPlugin(fixture, id: "kit@tools", folder: "tools/kit/1.0.0", manifestName: "kit")
        try fixture.json(".claude/settings.json", in: fixture.home, ["enabledPlugins": ["kit@tools": true]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["enabledPlugins": ["kit@tools": true]])
        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["enabledPlugins": ["kit@tools": false]])

        let report = fixture.inspect()
        let plugin = try report.onlyItem(.plugin, named: "kit@tools")
        XCTAssertEqual(plugin.stage, .installed)
        XCTAssertEqual(plugin.scope, .local)
        XCTAssertNotNil(try report.onlyItem(.skill, named: "kit:migrate").inactiveReason)
        XCTAssertNotNil(try report.onlyItem(.mcpServer, named: "supabase").inactiveReason)
    }

    func testManagedFalseBlocksEverythingElse() throws {
        let fixture = try Fixture()
        _ = try installPlugin(fixture, id: "kit@tools", folder: "tools/kit/1.0.0")
        try fixture.json("managed-settings.json", in: fixture.managed, ["enabledPlugins": ["kit@tools": false]])
        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["enabledPlugins": ["kit@tools": true]])

        let plugin = try fixture.inspect().onlyItem(.plugin, named: "kit@tools")
        XCTAssertEqual(plugin.scope, .managed)
        XCTAssertEqual(plugin.stage, .installed)
    }

    func testEnabledButNotInstalledIsOnlyDeclared() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.repository, ["enabledPlugins": ["formatter@team": true]])

        let plugin = try fixture.inspect().onlyItem(.plugin, named: "formatter@team")
        XCTAssertEqual(plugin.stage, .declared)
        XCTAssertEqual(plugin.scope, .project)
    }

    func testInstallRecordPointingNowhereIsReported() throws {
        let fixture = try Fixture()
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "plugins": ["ghost@tools": [["scope": "user", "installPath": "/nonexistent/ghost"]]],
        ])

        let report = fixture.inspect()
        XCTAssertEqual(try report.onlyItem(.plugin, named: "ghost@tools").stage, .declared)
        XCTAssertTrue(report.hasDiagnostic(.pluginInstallMissing))
    }

    func testSkillsDirectoryPluginIsRecognised() throws {
        let fixture = try Fixture()
        let folder = fixture.repository.appendingPathComponent(".claude/skills/bundle")
        try fixture.write("SKILL.md", in: folder, Fixture.skill())
        try fixture.json(".claude-plugin/plugin.json", in: folder, ["name": "bundle"])

        let report = fixture.inspect()
        let plugin = try report.onlyItem(.plugin, named: "bundle@skills-dir")
        XCTAssertEqual(plugin.scope, .project)
        XCTAssertEqual(try report.onlyItem(.skill, named: "bundle").metadataValue("Also a plugin"), "This folder has a plugin manifest, so it also loads as a plugin")
    }

    func testUnrecognisedInstallFileIsReportedNotFatal() throws {
        let fixture = try Fixture()
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["something": "else"])

        XCTAssertTrue(fixture.inspect().hasDiagnostic(.unrecognisedFormat))
    }
}
