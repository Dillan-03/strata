import StrataCore
import XCTest

final class ResolutionTests: XCTestCase {
    // MARK: Skills

    func testPersonalSkillBeatsProjectSkill() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill())
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())

        let deploys = fixture.inspect().items(.skill, named: "deploy")
        let personal = try XCTUnwrap(deploys.first { $0.scope == .user })
        let project = try XCTUnwrap(deploys.first { $0.scope == .project })
        XCTAssertEqual(personal.applicability, .effective)
        XCTAssertEqual(project.applicability, .shadowed(by: personal.id))
        XCTAssertEqual(personal.precedenceRank, 1)
        XCTAssertEqual(project.precedenceRank, 2)
        XCTAssertTrue(project.explanation.joined().lowercased().contains("personal skills"), project.explanation.joined())
    }

    func testManagedSkillBeatsPersonalSkill() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/audit/SKILL.md", in: fixture.managed, Fixture.skill())
        try fixture.write(".claude/skills/audit/SKILL.md", in: fixture.home, Fixture.skill())

        let audits = fixture.inspect().items(.skill, named: "audit")
        XCTAssertEqual(audits.first { $0.scope == .managed }?.applicability, .effective)
        XCTAssertEqual(audits.first { $0.scope == .user }?.applicability.isApplied, false)
    }

    func testSkillBeatsCommandWithTheSameName() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write(".claude/commands/deploy.md", in: fixture.home, "Deploy")

        let report = fixture.inspect()
        let skill = try report.onlyItem(.skill, named: "deploy")
        XCTAssertEqual(skill.applicability, .effective)
        XCTAssertEqual(try report.onlyItem(.command, named: "deploy").applicability, .shadowed(by: skill.id))
    }

    func testNestedSkillWithClashingNameGetsAQualifiedInvocation() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write("apps/web/.claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())

        let nested = try XCTUnwrap(fixture.inspect().items(.skill, named: "deploy").first { $0.scope == .nested })
        XCTAssertEqual(nested.applicability, .conditional)
        XCTAssertEqual(nested.invocation, "/apps/web:deploy")
    }

    func testPluginSkillsAreCombinedNotCompeting() throws {
        let fixture = try Fixture()
        let root = fixture.claude.appendingPathComponent("plugins/cache/kit")
        try fixture.write("skills/deploy/SKILL.md", in: root, Fixture.skill())
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit"])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["plugins": ["kit@tools": [["installPath": root.path]]]])
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())

        let report = fixture.inspect()
        XCTAssertEqual(try report.onlyItem(.skill, named: "kit:deploy").applicability, .combined)
        XCTAssertEqual(try report.onlyItem(.skill, named: "deploy").applicability, .effective)
    }

    func testSyncedSkillYieldsToLocalSkill() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/synced/abc/review/SKILL.md", in: fixture.home, Fixture.skill())
        try fixture.write(".claude/skills/review/SKILL.md", in: fixture.repository, Fixture.skill())

        let synced = try XCTUnwrap(fixture.inspect().items(.skill, named: "review").first { $0.scope == .synced })
        XCTAssertFalse(synced.applicability.isApplied)
        XCTAssertTrue(synced.explanation.joined().contains("full name"))
    }

    func testInvalidAndInactiveItemsKeepTheirStatus() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/loose.md", in: fixture.repository, "# Loose")

        let item = try fixture.inspect().onlyItem(.skill, named: "loose")
        XCTAssertEqual(item.applicability, .invalid)
        XCTAssertFalse(item.explanation.isEmpty)
    }

    // MARK: Subagents

    private func agent(_ name: String) -> String {
        "---\nname: \(name)\ndescription: Reviews\n---\nBody"
    }

    func testProjectAgentBeatsUserAgentUnlikeSkills() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/reviewer.md", in: fixture.home, agent("reviewer"))
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, agent("reviewer"))

        let reviewers = fixture.inspect().items(.agent, named: "reviewer")
        let project = try XCTUnwrap(reviewers.first { $0.scope == .project })
        XCTAssertEqual(project.applicability, .effective)
        XCTAssertEqual(reviewers.first { $0.scope == .user }?.applicability, .shadowed(by: project.id))
        XCTAssertTrue(project.explanation.joined().contains("opposite of skills"))
    }

    func testDuplicateAgentNamesInOneFolderAreUnknown() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/a.md", in: fixture.repository, agent("reviewer"))
        try fixture.write(".claude/agents/nested/b.md", in: fixture.repository, agent("reviewer"))

        let reviewers = fixture.inspect().items(.agent, named: "reviewer")
        XCTAssertEqual(reviewers.count, 2)
        XCTAssertTrue(reviewers.allSatisfy { $0.applicability == .unknown })
    }

    // MARK: MCP servers

    func testLocalBeatsProjectBeatsUserWithoutMerging() throws {
        let fixture = try Fixture()
        try fixture.json(".claude.json", in: fixture.home, [
            "mcpServers": ["api": ["type": "http", "url": "https://user.example.com"]],
            "projects": [fixture.repository.path: ["mcpServers": ["api": ["type": "http", "url": "https://local.example.com"]]]],
        ])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["api": ["type": "http", "url": "https://project.example.com"]]])

        let servers = fixture.inspect().items(.mcpServer, named: "api")
        let local = try XCTUnwrap(servers.first { $0.scope == .local })
        XCTAssertEqual(local.applicability, .effective)
        XCTAssertEqual(servers.filter { $0.applicability == .shadowed(by: local.id) }.count, 2)
        XCTAssertTrue(local.explanation.joined().contains("aren't merged"))
    }

    func testPluginServerWithSameEndpointIsADuplicate() throws {
        let fixture = try Fixture()
        let root = fixture.claude.appendingPathComponent("plugins/cache/kit")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit"])
        try fixture.json(".mcp.json", in: root, ["mcpServers": [
            "github-copy": ["type": "http", "url": "https://API.example.com/mcp/"],
            "other": ["type": "http", "url": "https://other.example.com/mcp"],
        ]])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["plugins": ["kit@tools": [["installPath": root.path]]]])
        try fixture.json(".claude.json", in: fixture.home, ["mcpServers": ["github": ["type": "http", "url": "https://api.example.com/mcp"]]])

        let report = fixture.inspect()
        let user = try report.onlyItem(.mcpServer, named: "github")
        XCTAssertEqual(try report.onlyItem(.mcpServer, named: "github-copy").applicability, .shadowed(by: user.id))
        XCTAssertEqual(try report.onlyItem(.mcpServer, named: "other").applicability, .effective)
    }

    func testUnapprovedProjectServerIsConditional() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "/usr/bin/true"]]])

        XCTAssertEqual(try fixture.inspect().onlyItem(.mcpServer, named: "db").applicability, .conditional)
    }

    // MARK: Plugins

    func testPluginStagesMapToApplicability() throws {
        let fixture = try Fixture()
        let on = fixture.claude.appendingPathComponent("plugins/cache/on")
        let off = fixture.claude.appendingPathComponent("plugins/cache/off")
        try fixture.json(".claude-plugin/plugin.json", in: on, ["name": "on"])
        try fixture.json(".claude-plugin/plugin.json", in: off, ["name": "off"])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["plugins": [
            "on@m": [["installPath": on.path]],
            "off@m": [["installPath": off.path]],
        ]])
        try fixture.json(".claude/settings.json", in: fixture.home, ["enabledPlugins": ["off@m": false, "on@m": false]])
        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["enabledPlugins": ["on@m": true, "missing@m": true]])

        let report = fixture.inspect()
        let enabled = try report.onlyItem(.plugin, named: "on@m")
        XCTAssertEqual(enabled.applicability, .effective)
        XCTAssertTrue(enabled.explanation.joined().contains("Project local settings: on"))
        XCTAssertEqual(try report.onlyItem(.plugin, named: "off@m").applicability, .inactive)
        XCTAssertEqual(try report.onlyItem(.plugin, named: "missing@m").applicability, .inactive)
    }

    func testRepositoryEnabledPluginWaitsForTrust() throws {
        let fixture = try Fixture()
        let root = fixture.claude.appendingPathComponent("plugins/cache/team")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "team"])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["plugins": ["team@m": [["installPath": root.path]]]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["enabledPlugins": ["team@m": true]])

        XCTAssertEqual(try fixture.inspect().onlyItem(.plugin, named: "team@m").applicability, .conditional)
    }

    // MARK: Instructions

    func testInstructionsCombineAndExplainTheirPosition() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/CLAUDE.md", in: fixture.home, "# Me")
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo")
        try fixture.write("packages/api/CLAUDE.md", in: fixture.repository, "# API")

        let report = fixture.inspect()
        let repo = try report.onlyItem(.instruction, named: "CLAUDE.md")
        XCTAssertEqual(repo.applicability, .combined)
        XCTAssertTrue(repo.explanation.joined().contains("2nd of 2"))
        XCTAssertEqual(try report.onlyItem(.instruction, named: "packages/api/CLAUDE.md").applicability, .conditional)
    }

    // MARK: Settings

    func testScalarSettingsTakeTheHighestFile() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.home, ["model": "a"])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["model": "b"])
        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["model": "c"])

        let models = fixture.inspect().items(.setting, named: "model")
        let local = try XCTUnwrap(models.first { $0.scope == .local })
        XCTAssertEqual(local.applicability, .effective)
        XCTAssertEqual(models.filter { $0.applicability == .shadowed(by: local.id) }.map(\.scope).sorted { $0.rawValue < $1.rawValue }, [.project, .user])
    }

    func testListAndPermissionSettingsCombine() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.home, ["claudeMdExcludes": ["a"], "permissions": ["allow": ["Read"]]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["claudeMdExcludes": ["b"], "permissions": ["deny": ["Bash"]]])

        let report = fixture.inspect()
        XCTAssertTrue(report.items(.setting, named: "claudeMdExcludes").allSatisfy { $0.applicability == .combined })
        XCTAssertTrue(report.items(.setting, named: "permissions").allSatisfy { $0.applicability == .combined })
    }

    func testUndocumentedObjectMergeIsUnknown() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.home, ["env": ["A": "1"]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["env": ["B": "2"]])

        XCTAssertTrue(fixture.inspect().items(.setting, named: "env").allSatisfy { $0.applicability == .unknown })
    }

    func testModelPickerIsIgnoredInProjectSettings() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.repository, ["modelPicker": ["rows": []]])

        XCTAssertEqual(try fixture.inspect().onlyItem(.setting, named: "modelPicker").applicability, .inactive)
    }

    func testSingleSettingApplies() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.home, ["theme": "dark"])

        XCTAssertEqual(try fixture.inspect().onlyItem(.setting, named: "theme").applicability, .effective)
    }

    // MARK: Ordering

    func testItemsAreOrderedByKindThenName() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/zeta/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write(".claude/skills/alpha/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "/usr/bin/true"]]])

        let items = fixture.inspect().items
        XCTAssertEqual(items.filter { $0.kind == .skill }.map(\.name), ["alpha", "zeta"])
        let firstServer = try XCTUnwrap(items.firstIndex { $0.kind == .mcpServer })
        let lastSkill = try XCTUnwrap(items.lastIndex { $0.kind == .skill })
        XCTAssertLessThan(lastSkill, firstServer)
    }
}
