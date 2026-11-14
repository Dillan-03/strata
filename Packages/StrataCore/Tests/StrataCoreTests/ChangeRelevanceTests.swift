import StrataCore
import XCTest

final class ChangeRelevanceTests: XCTestCase {
    private let environment = ScanEnvironment(
        homeDirectory: URL(fileURLWithPath: "/Users/dev"),
        managedDirectory: URL(fileURLWithPath: "/Library/Application Support/ClaudeCode")
    )

    private var relevance: ChangeRelevance {
        ChangeRelevance(environment: environment, repositoryPaths: ["/Users/dev/code/app", "/Users/dev/code/app/packages/sub"])
    }

    func testGlobalConfigurationChangesAffectEveryRepository() {
        for path in [
            "/Users/dev/.claude/settings.json",
            "/Users/dev/.claude/skills/deploy/SKILL.md",
            "/Users/dev/.claude/agents/reviewer.md",
            "/Users/dev/.claude/plugins/installed_plugins.json",
            "/Users/dev/.claude/CLAUDE.md",
            "/Users/dev/.claude.json",
            "/Library/Application Support/ClaudeCode/managed-settings.json",
        ] {
            XCTAssertEqual(relevance.classify(path), .global, path)
        }
    }

    func testClaudeCodeWorkingDataIsIgnored() {
        for path in [
            "/Users/dev/.claude/projects/-Users-dev-code-app/abc.jsonl",
            "/Users/dev/.claude/todos/x.json",
            "/Users/dev/.claude/shell-snapshots/snap.sh",
            "/Users/dev/.claude/file-history/s/1",
            "/Users/dev/.claude/plugins/data/kit/state.json",
            "/Users/dev/.claude/plugins/marketplaces/m/.git/index",
        ] {
            XCTAssertEqual(relevance.classify(path), .none, path)
        }
    }

    func testRepositoryConfigurationChangesAffectThatRepository() {
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/.claude/skills/x/SKILL.md"), .repository("/Users/dev/code/app"))
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/CLAUDE.md"), .repository("/Users/dev/code/app"))
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/apps/web/.claude/skills/y/SKILL.md"), .repository("/Users/dev/code/app"))
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/.mcp.json"), .repository("/Users/dev/code/app"))
    }

    func testTheMostSpecificRepositoryWins() {
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/packages/sub/CLAUDE.md"), .repository("/Users/dev/code/app/packages/sub"))
    }

    func testOrdinarySourceEditsAreIgnored() {
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/src/main.swift"), .none)
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/node_modules/pkg/.claude/skills/x/SKILL.md"), .none)
        XCTAssertEqual(relevance.classify("/Users/dev/code/app/.git/index"), .none)
    }

    func testAncestorInstructionFilesAreGlobal() {
        XCTAssertEqual(relevance.classify("/Users/dev/code/CLAUDE.md"), .global)
        XCTAssertEqual(relevance.classify("/Users/dev/code/notes.txt"), .none)
    }

    func testUnrelatedPathsAreIgnored() {
        XCTAssertEqual(relevance.classify("/Users/dev/Downloads/file.zip"), .none)
    }

    /// A scan must not crash when files disappear while it runs.
    func testScanningWhileFilesAreDeletedDoesNotCrash() throws {
        let fixture = try Fixture()
        for index in 0..<200 {
            try fixture.write(".claude/skills/skill-\(index)/SKILL.md", in: fixture.repository, Fixture.skill())
            try fixture.write(".claude/agents/agent-\(index).md", in: fixture.repository, "---\nname: a\(index)\ndescription: d\n---\n")
        }
        let environment = fixture.environment
        let repository = fixture.repository
        let done = expectation(description: "scans finished")
        done.expectedFulfillmentCount = 5
        DispatchQueue.concurrentPerform(iterations: 6) { iteration in
            if iteration == 0 {
                try? FileManager.default.removeItem(at: repository.appendingPathComponent(".claude"))
            } else {
                _ = Inspector(environment: environment).inspect(repository)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 30)
    }
}
