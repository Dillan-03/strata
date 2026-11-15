@testable import StrataCore
import XCTest

final class ChangeImpactTests: XCTestCase {
    /// Three repositories sharing one home folder: `plain` has no config of its own, `custom` defines its own
    /// /deploy skill, reviewer subagent, `model` and `github` MCP server, and `outside` sits outside ~/code.
    private struct Workspace {
        let fixture: Fixture
        let plain: URL
        let custom: URL
        let outside: URL

        var repositories: [URL] { [plain, custom, outside] }

        func scan() -> [InspectionReport] {
            let inspector = Inspector(environment: fixture.environment)
            return repositories.map { inspector.inspect($0) }
        }
    }

    private func makeWorkspace() throws -> Workspace {
        let fixture = try Fixture()
        let plain = fixture.home.appendingPathComponent("code/plain")
        let custom = fixture.home.appendingPathComponent("code/custom")
        let outside = fixture.home.appendingPathComponent("elsewhere/outside")
        for folder in [plain, custom, outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy anything"))
        try fixture.write("agents/reviewer.md", in: fixture.claude, "---\nname: reviewer\ndescription: General reviewer\n---\n")
        try fixture.json("settings.json", in: fixture.claude, ["model": "sonnet", "permissions": ["allow": ["Bash(npm test)"]]])
        try fixture.json(".claude.json", in: fixture.home, ["mcpServers": ["github": ["type": "http", "url": "https://example.com/mcp"]]])
        try fixture.write(".claude/skills/deploy/SKILL.md", in: custom, Fixture.skill(description: "Deploy custom to staging"))
        try fixture.write(".claude/agents/reviewer.md", in: custom, "---\nname: reviewer\ndescription: Reviews against custom's rules\n---\n")
        try fixture.json(".claude/settings.json", in: custom, ["model": "opus"])
        try fixture.json(".mcp.json", in: custom, ["mcpServers": ["github": ["command": "github-mcp"]]])
        return Workspace(fixture: fixture, plain: plain, custom: custom, outside: outside)
    }

    /// The single change to `kind`/`name` seen from the first repository's scans.
    private func change(_ kind: ItemKind, _ name: String, before: [InspectionReport], after: [InspectionReport]) throws -> ConfigChange {
        try XCTUnwrap(ChangeDetector.changes(from: before[0], to: after[0]).first { $0.item.kind == kind && $0.item.name == name })
    }

    private func effects(_ impacts: [RepositoryImpact], in workspace: Workspace) -> [String: String] {
        Dictionary(uniqueKeysWithValues: impacts.map { impact in
            let name = URL(fileURLWithPath: impact.repositoryPath).lastPathComponent
            switch impact.effect {
            case .affected: return (name, "affected")
            case .possiblyAffected: return (name, "possibly")
            case .shadowed(let winner): return (name, "shadowed by \(winner.scope.rawValue) \(winner.name)")
            case .unaffected: return (name, "unaffected")
            }
        })
    }

    func testGlobalSkillEditReachesEvenARepositoryWithItsOwnCopy() throws {
        let workspace = try makeWorkspace()
        let before = workspace.scan()
        try workspace.fixture.write("skills/deploy/SKILL.md", in: workspace.fixture.claude, Fixture.skill(description: "Deploy, then smoke test"))
        let after = workspace.scan()

        // A personal skill beats the repository's, so custom's own /deploy doesn't protect it.
        let impacts = ChangeImpact.impacts(of: try change(.skill, "deploy", before: before, after: after), before: before, after: after)
        XCTAssertEqual(effects(impacts, in: workspace), ["plain": "affected", "custom": "affected", "outside": "affected"])
    }

    func testGlobalSubagentEditSkipsTheRepositoryWithItsOwnCopy() throws {
        let workspace = try makeWorkspace()
        let before = workspace.scan()
        try workspace.fixture.write("agents/reviewer.md", in: workspace.fixture.claude, "---\nname: reviewer\ndescription: Stricter reviewer\n---\n")
        let after = workspace.scan()

        // A project subagent beats the user's, so custom keeps its own reviewer.
        let impacts = ChangeImpact.impacts(of: try change(.agent, "reviewer", before: before, after: after), before: before, after: after)
        XCTAssertEqual(effects(impacts, in: workspace), [
            "plain": "affected",
            "custom": "shadowed by project reviewer",
            "outside": "affected",
        ])
    }

    func testRemovingAShadowedGlobalSubagentChangesNothingThere() throws {
        let workspace = try makeWorkspace()
        let before = workspace.scan()
        try FileManager.default.removeItem(at: workspace.fixture.claude.appendingPathComponent("agents/reviewer.md"))
        let after = workspace.scan()

        let removal = try change(.agent, "reviewer", before: before, after: after)
        XCTAssertEqual(removal.kind, .deleted)
        let impacts = ChangeImpact.impacts(of: removal, before: before, after: after)
        XCTAssertEqual(effects(impacts, in: workspace)["custom"], "shadowed by project reviewer")
        XCTAssertEqual(impacts.filter(\.isAffected).count, 2)
    }

    func testNewGlobalSubagentThatARepositoryAlreadyOverrides() throws {
        let workspace = try makeWorkspace()
        try workspace.fixture.write(".claude/agents/planner.md", in: workspace.custom, "---\nname: planner\ndescription: Custom planner\n---\n")
        let before = workspace.scan()
        try workspace.fixture.write("agents/planner.md", in: workspace.fixture.claude, "---\nname: planner\ndescription: Global planner\n---\n")
        let after = workspace.scan()

        let created = try change(.agent, "planner", before: before, after: after)
        XCTAssertEqual(created.kind, .created)
        XCTAssertEqual(effects(ChangeImpact.impacts(of: created, before: before, after: after), in: workspace)["custom"], "shadowed by project planner")
    }

    func testOverriddenSettingVersusCombinedSetting() throws {
        let workspace = try makeWorkspace()
        let before = workspace.scan()
        try workspace.fixture.json("settings.json", in: workspace.fixture.claude, ["model": "haiku", "permissions": ["allow": ["Bash(npm test)", "Bash(npm run lint)"]]])
        let after = workspace.scan()

        let model = ChangeImpact.impacts(of: try change(.setting, "model", before: before, after: after), before: before, after: after)
        XCTAssertEqual(effects(model, in: workspace)["custom"], "shadowed by project model")
        XCTAssertEqual(effects(model, in: workspace)["plain"], "affected")

        let permissions = ChangeImpact.impacts(of: try change(.setting, "permissions", before: before, after: after), before: before, after: after)
        XCTAssertTrue(permissions.allSatisfy(\.isAffected), "Permissions combine across files, so every repository is affected")
    }

    func testGlobalMCPServerShadowedByAProjectServer() throws {
        let workspace = try makeWorkspace()
        let before = workspace.scan()
        try workspace.fixture.json(".claude.json", in: workspace.fixture.home, ["mcpServers": ["github": ["type": "http", "url": "https://example.com/mcp/v2"]]])
        let after = workspace.scan()

        let impacts = ChangeImpact.impacts(of: try change(.mcpServer, "github", before: before, after: after), before: before, after: after)
        XCTAssertEqual(effects(impacts, in: workspace)["custom"], "shadowed by project github")
        XCTAssertEqual(effects(impacts, in: workspace)["plain"], "affected")
    }

    func testPluginUpdateSkipsARepositoryThatTurnsItOff() throws {
        let workspace = try makeWorkspace()
        let fixture = workspace.fixture
        let root = fixture.claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit", "version": "1.0.0"])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": 2,
            "plugins": ["kit@tools": [["scope": "user", "installPath": root.path, "version": "1.0.0"]]],
        ])
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": true]])
        try fixture.json(".claude/settings.json", in: workspace.custom, ["enabledPlugins": ["kit@tools": false]])
        let before = workspace.scan()
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit", "version": "1.0.0", "description": "Now with docs"])
        let after = workspace.scan()

        let impacts = ChangeImpact.impacts(of: try change(.plugin, "kit@tools", before: before, after: after), before: before, after: after)
        XCTAssertEqual(effects(impacts, in: workspace), ["plain": "affected", "custom": "unaffected", "outside": "affected"])
    }

    func testParentFolderInstructionsOnlyReachRepositoriesBeneathIt() throws {
        let workspace = try makeWorkspace()
        let before = workspace.scan()
        try workspace.fixture.write("code/CLAUDE.md", in: workspace.fixture.home, "# Everything in code/\n")
        let after = workspace.scan()

        let created = try XCTUnwrap(ChangeDetector.changes(from: before[0], to: after[0]).first { $0.item.scope == .ancestor })
        XCTAssertEqual(created.reach, .shared)
        XCTAssertEqual(effects(ChangeImpact.impacts(of: created, before: before, after: after), in: workspace), [
            "plain": "affected",
            "custom": "affected",
            "outside": "unaffected",
        ])
    }

    func testRepositoriesWithoutAnEarlierScanAreSkipped() throws {
        let workspace = try makeWorkspace()
        let before = Array(workspace.scan().prefix(1))
        try workspace.fixture.write("skills/deploy/SKILL.md", in: workspace.fixture.claude, Fixture.skill(description: "Deploy v3"))
        let after = workspace.scan()

        let impacts = ChangeImpact.impacts(of: try change(.skill, "deploy", before: before, after: after), before: before, after: after)
        XCTAssertEqual(impacts.map(\.repositoryPath), [workspace.plain.path])
    }
}
