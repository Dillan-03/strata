import StrataCore
import XCTest

final class SkillDiscoveryTests: XCTestCase {
    func testFindsPersonalProjectManagedAndNestedSkills() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill(description: "Personal deploy"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Repo deploy"))
        try fixture.write(".claude/skills/audit/SKILL.md", in: fixture.managed, Fixture.skill())
        try fixture.write("apps/web/.claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Web deploy"))

        let report = fixture.inspect()
        let deploys = report.items(.skill, named: "deploy")
        XCTAssertEqual(Set(deploys.map(\.scope)), [.user, .project, .nested])
        XCTAssertEqual(deploys.first { $0.scope == .user }?.summary, "Personal deploy")
        let nested = try XCTUnwrap(deploys.first { $0.scope == .nested })
        XCTAssertEqual(nested.origin, "apps/web")
        XCTAssertEqual(nested.loadTiming, .onDemand)
        XCTAssertNotNil(nested.condition)
        XCTAssertEqual(try report.onlyItem(.skill, named: "audit").scope, .managed)
    }

    func testFrontmatterNameSetsTheCommand() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy-staging/SKILL.md", in: fixture.repository, Fixture.skill(name: "deploy"))

        let item = try fixture.inspect().onlyItem(.skill, named: "deploy")
        XCTAssertEqual(item.invocation, "/deploy")
        XCTAssertEqual(item.metadataValue("Folder name"), "deploy-staging (also invokes the skill)")
    }

    func testBareMarkdownFileInSkillsWontLoad() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/old-helper.md", in: fixture.repository, "# Old")

        let report = fixture.inspect()
        let item = try report.onlyItem(.skill, named: "old-helper")
        XCTAssertNotNil(item.loadBlocker)
        XCTAssertTrue(report.hasDiagnostic(.skillNotInFolder))
    }

    func testFolderWithoutSkillFileWontLoad() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/empty/notes.txt", in: fixture.repository, "nothing")

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.skill, named: "empty").loadBlocker)
        XCTAssertTrue(report.hasDiagnostic(.skillMissingDefinition))
    }

    func testReservedNamesAreBlocked() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/synced/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write(".claude/skills/anthropic-skills/SKILL.md", in: fixture.repository, Fixture.skill())

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.skill, named: "synced").loadBlocker)
        XCTAssertNotNil(try report.onlyItem(.skill, named: "anthropic-skills").loadBlocker)
        XCTAssertTrue(report.hasDiagnostic(.reservedName))
    }

    func testSyncedSkillsAreReadFromTheirNestedLayout() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/synced/0a1b2c/review-pr/SKILL.md", in: fixture.home, Fixture.skill())

        let report = fixture.inspect()
        let item = try report.onlyItem(.skill, named: "review-pr")
        XCTAssertEqual(item.scope, .synced)
        XCTAssertNil(item.loadBlocker)
        XCTAssertFalse(report.hasDiagnostic(.skillMissingDefinition))
    }

    func testCommandsUseTheirRelativePathAsName() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/commands/frontend/component.md", in: fixture.repository, "---\ndescription: Make a component\n---\n")
        try fixture.write(".claude/commands/deploy.md", in: fixture.home, "Deploy")

        let report = fixture.inspect()
        let component = try report.onlyItem(.command, named: "frontend:component")
        XCTAssertEqual(component.invocation, "/frontend:component")
        XCTAssertEqual(component.summary, "Make a component")
        XCTAssertEqual(try report.onlyItem(.command, named: "deploy").scope, .user)
    }

    func testSkillMetadataDescribesWhoCanStartIt() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/manual/SKILL.md", in: fixture.repository, Fixture.skill(extra: "disable-model-invocation: true\nallowed-tools: Read, Grep"))

        let item = try fixture.inspect().onlyItem(.skill, named: "manual")
        XCTAssertEqual(item.metadataValue("Started by"), "Only you (Claude won't invoke it on its own)")
        XCTAssertEqual(item.metadataValue("Allowed tools"), "Read, Grep")
    }

    func testNestedSearchSkipsDependencyFolders() throws {
        let fixture = try Fixture()
        try fixture.write("node_modules/pkg/.claude/skills/evil/SKILL.md", in: fixture.repository, Fixture.skill())

        XCTAssertTrue(fixture.inspect().items(.skill, named: "evil").isEmpty)
    }

    func testSymlinkedSkillFolderRecordsItsTarget() throws {
        let fixture = try Fixture()
        let shared = fixture.root.appendingPathComponent("shared/lint")
        try fixture.write("SKILL.md", in: shared, Fixture.skill())
        try fixture.makeDirectory(".claude/skills", in: fixture.repository)
        try FileManager.default.createSymbolicLink(
            at: fixture.repository.appendingPathComponent(".claude/skills/lint"),
            withDestinationURL: shared
        )

        let item = try fixture.inspect().onlyItem(.skill, named: "lint")
        XCTAssertEqual(item.metadataValue("Linked from"), shared.path)
        XCTAssertEqual(item.matchKey, shared.path)
    }
}
