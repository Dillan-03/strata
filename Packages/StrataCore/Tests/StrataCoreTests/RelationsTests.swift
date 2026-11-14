import StrataCore
import XCTest

final class RelationsTests: XCTestCase {
    func testCompetingDefinitionsAreRankedAndIncludeCommands() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill())
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write(".claude/commands/deploy.md", in: fixture.repository, "Deploy")

        let report = fixture.inspect()
        let project = try XCTUnwrap(report.items(.skill, named: "deploy").first { $0.scope == .project })
        let definitions = report.definitions(competingWith: project)
        XCTAssertEqual(definitions.map(\.scope), [.user, .project, .project])
        XCTAssertEqual(definitions.map(\.kind), [.skill, .skill, .command])
        XCTAssertEqual(definitions.first?.applicability, .effective)
    }

    func testPluginComponentsAndProvider() throws {
        let fixture = try Fixture()
        let root = fixture.claude.appendingPathComponent("plugins/cache/kit")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit"])
        try fixture.write("skills/migrate/SKILL.md", in: root, Fixture.skill())
        try fixture.write("agents/schema.md", in: root, "---\nname: schema\ndescription: Schemas\n---\n")
        try fixture.json(".mcp.json", in: root, ["mcpServers": ["db": ["command": "/usr/bin/true"]]])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["plugins": ["kit@m": [["installPath": root.path]]]])

        let report = fixture.inspect()
        let plugin = try report.onlyItem(.plugin, named: "kit@m")
        XCTAssertEqual(Set(report.components(ofPlugin: plugin).map(\.kind)), [.skill, .agent, .mcpServer])
        let skill = try report.onlyItem(.skill, named: "kit:migrate")
        XCTAssertEqual(report.plugin(providing: skill)?.id, plugin.id)
        XCTAssertNil(report.plugin(providing: try report.onlyItem(.plugin, named: "kit@m")))
    }

    func testImportsAndLaunchOrder() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/CLAUDE.md", in: fixture.home, "# Me")
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo\n@docs/style.md")
        try fixture.write("docs/style.md", in: fixture.repository, "# Style")
        try fixture.write("packages/api/CLAUDE.md", in: fixture.repository, "# API")

        let report = fixture.inspect()
        let root = try report.onlyItem(.instruction, named: "CLAUDE.md")
        XCTAssertEqual(report.imports(of: root).map(\.name), ["docs/style.md"])
        XCTAssertEqual(report.launchInstructions.map(\.name), ["~/.claude/CLAUDE.md", "CLAUDE.md", "docs/style.md"])
    }

    func testShadowedByListsTheLosers() throws {
        let fixture = try Fixture()
        try fixture.json(".claude.json", in: fixture.home, [
            "mcpServers": ["api": ["type": "http", "url": "https://user.example.com"]],
            "projects": [fixture.repository.path: ["mcpServers": ["api": ["type": "http", "url": "https://local.example.com"]]]],
        ])

        let report = fixture.inspect()
        let local = try XCTUnwrap(report.items(.mcpServer, named: "api").first { $0.scope == .local })
        XCTAssertEqual(report.items(shadowedBy: local).map(\.scope), [.user])
    }
}
