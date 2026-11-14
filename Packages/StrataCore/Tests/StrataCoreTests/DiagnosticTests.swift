import StrataCore
import XCTest

final class DiagnosticTests: XCTestCase {
    func testShadowedSkillProducesAWarningLinkingBothCopies() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill())
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())

        let report = fixture.inspect()
        let diagnostic = try XCTUnwrap(report.diagnostics.first { $0.code == .shadowedDefinition })
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.itemIDs.count, 2)
        XCTAssertEqual(diagnostic.title, "Global skill deploy hides the repo copy")
        XCTAssertNotNil(diagnostic.suggestion)
    }

    func testShadowedSubagentIsReported() throws {
        let fixture = try Fixture()
        let agent = "---\nname: reviewer\ndescription: Reviews\n---\n"
        try fixture.write(".claude/agents/reviewer.md", in: fixture.home, agent)
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, agent)

        let diagnostic = try XCTUnwrap(fixture.inspect().diagnostics.first { $0.code == .shadowedDefinition })
        XCTAssertTrue(diagnostic.title.hasPrefix("Repo subagent reviewer"))
    }

    func testDuplicateAgentNamesInOneFolderAreAConflict() throws {
        let fixture = try Fixture()
        let agent = "---\nname: reviewer\ndescription: Reviews\n---\n"
        try fixture.write(".claude/agents/a.md", in: fixture.repository, agent)
        try fixture.write(".claude/agents/b.md", in: fixture.repository, agent)

        let diagnostic = try XCTUnwrap(fixture.inspect().diagnostics.first { $0.code == .duplicateNameInDirectory })
        XCTAssertEqual(diagnostic.severity, .conflict)
        XCTAssertEqual(diagnostic.paths.count, 2)
    }

    func testSameServerNameWithDifferentEndpointsIsAWarning() throws {
        let fixture = try Fixture()
        try fixture.json(".claude.json", in: fixture.home, ["mcpServers": ["api": ["type": "http", "url": "https://a.example.com"]]])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["api": ["type": "http", "url": "https://b.example.com"]]])

        let diagnostic = try XCTUnwrap(fixture.inspect().diagnostics.first { $0.code == .conflictingMCPEndpoints })
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertFalse(diagnostic.detail.contains("a.example.com"), "Diagnostics shouldn't repeat endpoints, which can carry secrets")
    }

    func testSameServerNameWithTheSameEndpointIsNotAConflict() throws {
        let fixture = try Fixture()
        try fixture.json(".claude.json", in: fixture.home, ["mcpServers": ["api": ["type": "http", "url": "https://a.example.com"]]])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["api": ["type": "http", "url": "https://A.example.com/"]]])

        XCTAssertFalse(fixture.inspect().hasDiagnostic(.conflictingMCPEndpoints))
    }

    func testPluginServerDuplicatingAnEndpointIsInfo() throws {
        let fixture = try Fixture()
        let root = fixture.claude.appendingPathComponent("plugins/cache/kit")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit"])
        try fixture.json(".mcp.json", in: root, ["mcpServers": ["copy": ["type": "http", "url": "https://api.example.com"]]])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, ["plugins": ["kit@m": [["installPath": root.path]]]])
        try fixture.json(".claude.json", in: fixture.home, ["mcpServers": ["api": ["type": "http", "url": "https://api.example.com"]]])

        let diagnostic = try XCTUnwrap(fixture.inspect().diagnostics.first { $0.code == .duplicateMCPEndpoint })
        XCTAssertEqual(diagnostic.severity, .info)
    }

    func testEnabledButNotInstalledPluginIsAWarning() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.repository, ["enabledPlugins": ["formatter@team": true]])

        let diagnostic = try XCTUnwrap(fixture.inspect().diagnostics.first { $0.code == .pluginEnabledButNotInstalled })
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.suggestion, "Run `claude plugin install formatter@team`.")
    }

    func testSymlinkedSkillInTwoLocationsIsInfo() throws {
        let fixture = try Fixture()
        let shared = fixture.root.appendingPathComponent("shared/lint")
        try fixture.write("SKILL.md", in: shared, Fixture.skill())
        for base in [fixture.home, fixture.repository] {
            try fixture.makeDirectory(".claude/skills", in: base)
            try FileManager.default.createSymbolicLink(at: base.appendingPathComponent(".claude/skills/lint"), withDestinationURL: shared)
        }

        let diagnostic = try XCTUnwrap(fixture.inspect().diagnostics.first { $0.code == .symlinkDuplicate })
        XCTAssertEqual(diagnostic.severity, .info)
    }

    func testDiagnosticsAreSortedBySeverity() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/settings.json", in: fixture.repository, "{ broken")
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill())
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write("CLAUDE.md", in: fixture.repository, "@someone")

        let severities = fixture.inspect().diagnostics.map(\.severity)
        XCTAssertEqual(severities, severities.sorted())
        XCTAssertEqual(Set(severities), [.conflict, .warning, .info])
    }

    func testCleanRepositoryHasNoDiagnostics() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo\nSee @docs/guide.md")
        try fixture.write("docs/guide.md", in: fixture.repository, "Guide")

        XCTAssertEqual(fixture.inspect().diagnostics, [])
    }
}
