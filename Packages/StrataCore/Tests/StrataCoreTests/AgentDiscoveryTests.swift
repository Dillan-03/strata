import StrataCore
import XCTest

final class AgentDiscoveryTests: XCTestCase {
    private func agent(name: String?, description: String? = "Reviews code", tools: String? = nil) -> String {
        var lines = ["---"]
        if let name { lines.append("name: \(name)") }
        if let description { lines.append("description: \(description)") }
        if let tools { lines.append("tools: \(tools)") }
        lines += ["---", "You are a reviewer."]
        return lines.joined(separator: "\n")
    }

    func testIdentityComesFromFrontmatterNotFileName() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/review/security.md", in: fixture.repository, agent(name: "security-reviewer", tools: "Read, Grep"))

        let item = try fixture.inspect().onlyItem(.agent, named: "security-reviewer")
        XCTAssertEqual(item.scope, .project)
        XCTAssertEqual(item.metadataValue("Tools"), "Read, Grep")
        XCTAssertNil(item.loadBlocker)
    }

    func testFindsUserManagedAndProjectAgents() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/reviewer.md", in: fixture.home, agent(name: "reviewer"))
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, agent(name: "reviewer"))
        try fixture.write(".claude/agents/policy.md", in: fixture.managed, agent(name: "policy"))

        let report = fixture.inspect()
        XCTAssertEqual(Set(report.items(.agent, named: "reviewer").map(\.scope)), [.user, .project])
        XCTAssertEqual(try report.onlyItem(.agent, named: "policy").scope, .managed)
    }

    func testMissingNameOrDescriptionBlocksLoading() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/nameless.md", in: fixture.repository, agent(name: nil))
        try fixture.write(".claude/agents/vague.md", in: fixture.repository, agent(name: "vague", description: nil))

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.agent, named: "nameless").loadBlocker)
        XCTAssertNotNil(try report.onlyItem(.agent, named: "vague").loadBlocker)
        XCTAssertTrue(report.hasDiagnostic(.missingRequiredField))
    }

    func testColonInNameIsInvalid() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/scoped.md", in: fixture.repository, agent(name: "team:reviewer"))

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.agent, named: "team:reviewer").loadBlocker)
        XCTAssertTrue(report.hasDiagnostic(.invalidName))
    }
}
