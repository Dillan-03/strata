@testable import StrataCore
import XCTest

/// What loads at launch, and roughly how big it is.
final class ContextEstimateTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private func entry(_ estimate: ContextEstimate, named name: String) -> ContextEstimate.Entry? {
        estimate.entries.first { $0.name == name }
    }

    func testInstructionChainsAndImportsCountButPathScopedRulesDont() throws {
        let body = String(repeating: "Use tabs. ", count: 40)
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Repo\n\(body)\n@docs/style.md\n")
        try fixture.write("docs/style.md", in: fixture.repository, "Style guide.\n")
        try fixture.write(".claude/rules/api.md", in: fixture.repository, "---\npaths: [\"src/api/**\"]\n---\nAPI rules.\n")
        try fixture.write(".claude/rules/general.md", in: fixture.repository, "Always run tests.\n")
        try fixture.write("packages/web/CLAUDE.md", in: fixture.repository, "Web only.\n")
        let estimate = ContextEstimate(report: fixture.inspect())

        let names = Set(estimate.entries.filter { $0.kind == .instruction }.map(\.name))
        XCTAssertTrue(names.contains { $0.hasSuffix("CLAUDE.md") && !$0.contains("packages") }, "The root CLAUDE.md loads at launch")
        XCTAssertTrue(names.contains { $0.contains("style.md") }, "Imports load with the file that imports them")
        XCTAssertTrue(names.contains { $0.contains("general.md") }, "Rules without paths load at launch")
        XCTAssertFalse(names.contains { $0.contains("api.md") }, "Path-scoped rules load later")
        XCTAssertFalse(names.contains { $0.contains("packages") }, "Subdirectory CLAUDE.md files load later")
        let root = try XCTUnwrap(estimate.entries.first { $0.kind == .instruction && $0.name.hasSuffix("CLAUDE.md") })
        XCTAssertEqual(root.characters, "# Repo\n\(body)\n@docs/style.md\n".count)
        XCTAssertEqual(root.tokens, (root.characters + 3) / 4)
    }

    func testSkillsCountTheirListingLineUnlessOnlyYouCanStartThem() throws {
        let skill = Fixture.skill(description: "Ship it", extra: "when_to_use: After a merge\n") + String(repeating: "Long body. ", count: 500)
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, skill)
        try fixture.write(".claude/skills/secret/SKILL.md", in: fixture.repository, Fixture.skill(description: "Manual only", extra: "disable-model-invocation: true\n"))
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, "---\nname: reviewer\ndescription: Reviews diffs\n---\nYou review.\n")
        let estimate = ContextEstimate(report: fixture.inspect())

        let deploy = try XCTUnwrap(entry(estimate, named: "/deploy"))
        XCTAssertEqual(deploy.characters, "/deploy".count + "Ship it".count + "After a merge".count, "Only the listing line counts, not the body")
        XCTAssertNil(entry(estimate, named: "/secret"), "A skill only you can start isn't in Claude's listing")
        XCTAssertEqual(entry(estimate, named: "reviewer")?.characters, "reviewer".count + "Reviews diffs".count)
        XCTAssertEqual(estimate.tokens(for: [.agent]), ContextEstimate.tokens("reviewer".count + "Reviews diffs".count))
    }

    func testOverriddenCopiesDontCount() throws {
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill(description: "Personal"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Repo copy"))
        let estimate = ContextEstimate(report: fixture.inspect())
        XCTAssertEqual(estimate.entries.filter { $0.name == "/deploy" }.count, 1)
        XCTAssertEqual(entry(estimate, named: "/deploy")?.characters, "/deploy".count + "Personal".count)
    }

    func testDocumentedThresholdsRaiseWarnings() throws {
        try fixture.write("CLAUDE.md", in: fixture.repository, String(repeating: "A line.\n", count: 250))
        let description = String(repeating: "Handles a very specific kind of review. ", count: 400)
        for index in 0..<4 {
            try fixture.write(".claude/agents/agent\(index).md", in: fixture.repository, "---\nname: agent\(index)\ndescription: \(description)\n---\nBody.\n")
        }
        let warnings = ContextEstimate(report: fixture.inspect()).warnings.map(\.text)
        XCTAssertTrue(warnings.contains { $0.contains("251 lines") || $0.contains("250 lines") }, "\(warnings)")
        XCTAssertTrue(warnings.contains { $0.contains("Subagent descriptions") })
    }

    func testASmallSetupHasNoWarnings() throws {
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Short\n")
        XCTAssertTrue(ContextEstimate(report: fixture.inspect()).warnings.isEmpty)
    }
}
