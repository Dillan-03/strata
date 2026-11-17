@testable import StrataCore
import XCTest

final class ChangeDetectionTests: XCTestCase {
    /// A global skill, a repo skill, a repo subagent, settings, an MCP server and instructions.
    private func makeConfiguredFixture() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy anything"))
        try fixture.write(".claude/skills/review/SKILL.md", in: fixture.repository, Fixture.skill(description: "Review the diff"))
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, "---\nname: reviewer\ndescription: Reviews code\n---\n")
        try fixture.json("settings.json", in: fixture.claude, ["model": "sonnet", "permissions": ["allow": ["Bash(npm test)"]]])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["postgres": ["command": "npx", "args": ["-y", "pg"]]]])
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo rules\n")
        return fixture
    }

    private func onlyChange(_ changes: [ConfigChange], file: StaticString = #filePath, line: UInt = #line) throws -> ConfigChange {
        XCTAssertEqual(changes.count, 1, "\(changes.map { "\($0.kind) \($0.item.kind) \($0.item.name)" })", file: file, line: line)
        return try XCTUnwrap(changes.first, file: file, line: line)
    }

    func testEveryItemHasAFingerprint() throws {
        let fixture = try makeConfiguredFixture()
        let missing = fixture.inspect().items.filter { $0.fingerprint == nil }
        XCTAssertEqual(missing.map(\.name), [])
    }

    func testRescanningUnchangedFilesReportsNothing() throws {
        let fixture = try makeConfiguredFixture()
        XCTAssertEqual(ChangeDetector.changes(from: fixture.inspect(), to: fixture.inspect()), [])
    }

    func testReformattedJSONIsNotAChange() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.write("settings.json", in: fixture.claude, "{\"permissions\":{\"allow\":[\"Bash(npm test)\"]},\n\n  \"model\":   \"sonnet\"}")
        XCTAssertEqual(ChangeDetector.changes(from: before, to: fixture.inspect()), [])
    }

    func testGlobalSkillEditIsLiveAndReachesEveryRepository() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy, then smoke test"))

        let change = try onlyChange(ChangeDetector.changes(from: before, to: fixture.inspect()))
        XCTAssertEqual(change.kind, .updated)
        XCTAssertEqual(change.item.name, "deploy")
        XCTAssertEqual(change.reach, .global)
        XCTAssertEqual(change.pickup.timing, .live)
        XCTAssertEqual(change.previous?.summary, "Deploy anything")
    }

    func testRepositorySkillEditOnlyReachesThisRepository() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.write(".claude/skills/review/SKILL.md", in: fixture.repository, Fixture.skill(description: "Review the diff", extra: "Check tests too."))

        let change = try onlyChange(ChangeDetector.changes(from: before, to: fixture.inspect()))
        XCTAssertEqual(change.kind, .updated)
        XCTAssertEqual(change.reach, .repository)
        XCTAssertEqual(change.pickup.timing, .live)
    }

    func testFirstSkillInAFolderSuggestsReloadingSkillsButTheNextIsLive() throws {
        let fixture = try Fixture()
        let empty = fixture.inspect()
        try fixture.write(".claude/skills/ship/SKILL.md", in: fixture.repository, Fixture.skill())
        let first = try onlyChange(ChangeDetector.changes(from: empty, to: fixture.inspect()))
        XCTAssertEqual(first.kind, .created)
        XCTAssertEqual(first.pickup.timing, .reloadSkills)

        let withOne = fixture.inspect()
        try fixture.write(".claude/skills/lint/SKILL.md", in: fixture.repository, Fixture.skill())
        let second = try onlyChange(ChangeDetector.changes(from: withOne, to: fixture.inspect()))
        XCTAssertEqual(second.pickup.timing, .live)
    }

    func testRenamedSkillFolderIsAMove() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        let skills = fixture.repository.appendingPathComponent(".claude/skills")
        try FileManager.default.moveItem(at: skills.appendingPathComponent("review"), to: skills.appendingPathComponent("code-review"))

        let change = try onlyChange(ChangeDetector.changes(from: before, to: fixture.inspect()))
        XCTAssertEqual(change.kind, .renamed)
        XCTAssertEqual(change.previous?.name, "review")
        XCTAssertEqual(change.item.name, "code-review")
    }

    func testSubagentEditIsLiveButANewAgentsFolderNeedsARestart() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, "---\nname: reviewer\ndescription: Reviews against Acme rules\n---\n")
        XCTAssertEqual(try onlyChange(ChangeDetector.changes(from: before, to: fixture.inspect())).pickup.timing, .live)

        let withRepoAgent = fixture.inspect()
        try fixture.write("agents/helper.md", in: fixture.claude, "---\nname: helper\ndescription: Helps\n---\n")
        let created = try onlyChange(ChangeDetector.changes(from: withRepoAgent, to: fixture.inspect()))
        XCTAssertEqual(created.kind, .created)
        XCTAssertEqual(created.reach, .global)
        XCTAssertEqual(created.pickup.timing, .nextSession)
    }

    func testPluginConfigChangeNeedsReloadPlugins() throws {
        let fixture = try Fixture()
        let root = fixture.claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit", "version": "1.0.0"])
        try fixture.write("skills/migrate/SKILL.md", in: root, Fixture.skill())
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": 2,
            "plugins": ["kit@tools": [["scope": "user", "installPath": root.path, "version": "1.0.0"]]],
        ])
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": true]])
        let before = fixture.inspect()

        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": false]])
        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())

        let plugin = try XCTUnwrap(changes.first { $0.item.kind == .plugin })
        XCTAssertEqual(plugin.kind, .updated)
        XCTAssertEqual(plugin.reach, .global)
        XCTAssertEqual(plugin.pickup.timing, .reloadPlugins)
        let setting = try XCTUnwrap(changes.first { $0.item.kind == .setting })
        XCTAssertEqual(setting.item.name, "enabledPlugins")
        XCTAssertEqual(setting.pickup.timing, .reloadPlugins)
    }

    func testMCPChangesAreDetectedButTheirPickupIsUnknown() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["postgres": ["command": "npx", "args": ["-y", "pg@2"]]]])
        try fixture.json(".claude.json", in: fixture.home, ["mcpServers": ["github": ["type": "http", "url": "https://example.com/mcp"]]])

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        XCTAssertEqual(changes.map(\.kind), [.created, .updated])
        XCTAssertEqual(changes.map(\.item.name), ["github", "postgres"])
        XCTAssertEqual(changes.map(\.reach), [.global, .repository])
        XCTAssertTrue(changes.allSatisfy { $0.pickup.timing == .unknown })
    }

    func testModelNeedsANewSessionButPermissionsAreLive() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.json("settings.json", in: fixture.claude, ["model": "opus", "permissions": ["allow": ["Bash(npm test)", "Bash(npm run lint)"]]])

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        let timings = Dictionary(uniqueKeysWithValues: changes.map { ($0.item.name, $0.pickup.timing) })
        XCTAssertEqual(timings, ["model": .nextSession, "permissions": .live, "Bash(npm run lint)": .live], "A new rule is its own change too")
    }

    func testInstructionReachAndTiming() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo rules\n\nRun the tests.\n")
        try fixture.write("code/CLAUDE.md", in: fixture.home, "# Every repo in code/\n")

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        let parent = try XCTUnwrap(changes.first { $0.item.scope == .ancestor })
        XCTAssertEqual(parent.kind, .created)
        XCTAssertEqual(parent.reach, .shared)
        let repo = try XCTUnwrap(changes.first { $0.item.scope == .project })
        XCTAssertEqual(repo.kind, .updated)
        XCTAssertEqual(repo.pickup.timing, .nextSession)
    }

    func testConcurrentEditsAreAllReportedGlobalFirst() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy v2"))
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent(".claude/agents/reviewer.md"))
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": [
            "postgres": ["command": "npx", "args": ["-y", "pg"]],
            "redis": ["command": "redis-mcp"],
        ]])
        try fixture.json("settings.json", in: fixture.claude, ["model": "sonnet", "permissions": ["allow": []]])

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        XCTAssertEqual(changes.map { "\($0.kind.rawValue) \($0.item.name)" }, [
            "updated deploy", "updated permissions", "deleted Bash(npm test)", "deleted reviewer", "created redis",
        ])
        XCTAssertEqual(changes.map(\.reach), [.global, .global, .global, .repository, .repository])
    }

    func testCheckingOutAnotherBranchReportsOnlyWhatDiffers() throws {
        let fixture = try makeConfiguredFixture()
        let before = fixture.inspect()
        let claude = fixture.repository.appendingPathComponent(".claude")
        let review = try String(contentsOf: claude.appendingPathComponent("skills/review/SKILL.md"), encoding: .utf8)
        try FileManager.default.removeItem(at: claude)
        try fixture.write(".claude/skills/review/SKILL.md", in: fixture.repository, review)
        try fixture.write(".claude/skills/release/SKILL.md", in: fixture.repository, Fixture.skill(description: "Cut a release"))

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        XCTAssertEqual(changes.map { "\($0.kind.rawValue) \($0.item.name)" }, ["created release", "deleted reviewer"])
    }
}
