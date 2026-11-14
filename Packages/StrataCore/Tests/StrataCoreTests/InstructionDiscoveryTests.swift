@testable import StrataCore
import XCTest

final class InstructionDiscoveryTests: XCTestCase {
    func testLoadOrderRunsFromBroadestToMostSpecific() throws {
        let fixture = try Fixture()
        try fixture.write("CLAUDE.md", in: fixture.managed, "# Org")
        try fixture.write(".claude/CLAUDE.md", in: fixture.home, "# Me")
        try fixture.write("code/CLAUDE.md", in: fixture.home, "# Parent")
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo")
        try fixture.write("CLAUDE.local.md", in: fixture.repository, "# Mine")

        let instructions = fixture.inspect().items(of: .instruction).sorted { ($0.loadOrder ?? 0) < ($1.loadOrder ?? 0) }
        XCTAssertEqual(instructions.map(\.scope), [.managed, .user, .ancestor, .project, .local])
        XCTAssertEqual(instructions.map(\.summary), ["Org", "Me", "Parent", "Repo", "Mine"])
        XCTAssertTrue(instructions.allSatisfy { $0.loadTiming == .atLaunch })
    }

    func testAgentsMDIsIgnoredWhenClaudeMDExists() throws {
        let fixture = try Fixture()
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo")
        try fixture.write("AGENTS.md", in: fixture.repository, "# Agents")

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.instruction, named: "AGENTS.md").inactiveReason)
        XCTAssertTrue(report.hasDiagnostic(.agentsMDIgnored))
    }

    func testAgentsMDLoadsWhenThereIsNoClaudeMD() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/CLAUDE.md", in: fixture.home, "# User file doesn't count")
        try fixture.write("AGENTS.md", in: fixture.repository, "# Agents")

        let report = fixture.inspect()
        XCTAssertNil(try report.onlyItem(.instruction, named: "AGENTS.md").inactiveReason)
        XCTAssertFalse(report.hasDiagnostic(.agentsMDIgnored))
    }

    func testBothModeLoadsAgentsMDAlongsideClaudeMD() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.home, [
            "pluginConfigs": ["cc-plugin-agents-md@builtin": ["options": ["instructionFiles": "claude-md-and-agents-md"]]],
        ])
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo")
        try fixture.write("AGENTS.md", in: fixture.repository, "# Agents")

        XCTAssertNil(try fixture.inspect().onlyItem(.instruction, named: "AGENTS.md").inactiveReason)
    }

    func testInstructionModeIsIgnoredInProjectSettings() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.repository, [
            "pluginConfigs": ["cc-plugin-agents-md@builtin": ["options": ["instructionFiles": "claude-md-and-agents-md"]]],
        ])
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo")
        try fixture.write("AGENTS.md", in: fixture.repository, "# Agents")

        XCTAssertNotNil(try fixture.inspect().onlyItem(.instruction, named: "AGENTS.md").inactiveReason)
    }

    func testRulesWithPathsArePathGated() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/rules/api.md", in: fixture.repository, "---\npaths:\n  - src/api/**\n---\n# API rules")
        try fixture.write(".claude/rules/style.md", in: fixture.repository, "# Style")

        let report = fixture.inspect()
        let api = try report.onlyItem(.instruction, named: ".claude/rules/api.md")
        XCTAssertEqual(api.loadTiming, .pathGated)
        XCTAssertEqual(api.metadataValue("Applies to"), "src/api/**")
        XCTAssertEqual(try report.onlyItem(.instruction, named: ".claude/rules/style.md").loadTiming, .atLaunch)
    }

    func testSubdirectoryFilesLoadOnDemand() throws {
        let fixture = try Fixture()
        try fixture.write("packages/api/CLAUDE.md", in: fixture.repository, "# API")

        let item = try fixture.inspect().onlyItem(.instruction, named: "packages/api/CLAUDE.md")
        XCTAssertEqual(item.scope, .nested)
        XCTAssertEqual(item.loadTiming, .onDemand)
        XCTAssertNotNil(item.condition)
    }

    func testClaudeMdExcludesMarksMatchingFilesInactive() throws {
        let fixture = try Fixture()
        try fixture.write("code/CLAUDE.md", in: fixture.home, "# Other team")
        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["claudeMdExcludes": ["**/code/CLAUDE.md"]])

        let item = try fixture.inspect().onlyItem(.instruction, named: "~/code/CLAUDE.md")
        XCTAssertTrue(item.inactiveReason?.contains("claudeMdExcludes") ?? false)
    }

    func testGlobConversion() throws {
        let expression = try XCTUnwrap(InstructionScanner.globExpression("/home/user/monorepo/other-team/.claude/rules/**", home: "/home/user"))
        let match = { (path: String) in expression.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil }
        XCTAssertTrue(match("/home/user/monorepo/other-team/.claude/rules/a.md"))
        XCTAssertTrue(match("/home/user/monorepo/other-team/.claude/rules/sub/b.md"))
        XCTAssertFalse(match("/home/user/monorepo/mine/.claude/rules/a.md"))
    }

    func testImportsAreFollowedReportedAndBounded() throws {
        let fixture = try Fixture()
        try fixture.write("CLAUDE.md", in: fixture.repository, "Read @docs/one.md and @missing/file.md and @someone")
        try fixture.write("docs/one.md", in: fixture.repository, "@two.md")
        try fixture.write("docs/two.md", in: fixture.repository, "@three.md")
        try fixture.write("docs/three.md", in: fixture.repository, "@four.md")
        try fixture.write("docs/four.md", in: fixture.repository, "@five.md")
        try fixture.write("docs/five.md", in: fixture.repository, "too deep")

        let report = fixture.inspect()
        let imported = report.items(of: .instruction).filter { $0.metadataValue("Type") == "Import" }
        XCTAssertEqual(imported.map(\.name), ["docs/one.md", "docs/two.md", "docs/three.md", "docs/four.md"])
        XCTAssertTrue(report.hasDiagnostic(.importDepthExceeded))

        let missing = report.diagnostics.filter { $0.code == .missingImport }
        XCTAssertEqual(missing.map(\.severity).sorted(), [.warning, .info])
    }

    func testImportsOutsideTheRepositoryNeedApproval() throws {
        let fixture = try Fixture()
        try fixture.write("notes/mine.md", in: fixture.home, "# Mine")
        try fixture.write("CLAUDE.md", in: fixture.repository, "@~/notes/mine.md")

        let report = fixture.inspect()
        let imported = try report.onlyItem(.instruction, named: "~/notes/mine.md")
        XCTAssertNotNil(imported.condition)
        XCTAssertTrue(report.hasDiagnostic(.externalImport))
    }

    func testImportCyclesTerminate() throws {
        let fixture = try Fixture()
        try fixture.write("CLAUDE.md", in: fixture.repository, "@a.md")
        try fixture.write("a.md", in: fixture.repository, "@b.md")
        try fixture.write("b.md", in: fixture.repository, "@a.md @CLAUDE.md")

        let names = fixture.inspect().items(of: .instruction).map(\.name)
        XCTAssertEqual(names.filter { $0 == "a.md" }.count, 1)
        XCTAssertEqual(names.filter { $0 == "b.md" }.count, 1)
    }
}
