import StrataCore
import XCTest

final class ItemQueryTests: XCTestCase {
    private var report: InspectionReport!

    override func setUpWithError() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill(description: "Ship to production"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Ship the repo"))
        try fixture.write(".claude/skills/lint/SKILL.md", in: fixture.repository, Fixture.skill(description: "Run SwiftLint"))
        try fixture.write(".claude/skills/broken.md", in: fixture.repository, "# Broken")
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["supabase": ["type": "http", "url": "https://mcp.supabase.com"]]])
        report = fixture.inspect()
    }

    func testEmptyQueryReturnsEverything() {
        XCTAssertEqual(ItemQuery().apply(to: report.items, in: report), report.items)
        XCTAssertTrue(ItemQuery().isEmpty)
    }

    func testSearchMatchesNameDescriptionPathAndMetadataWithoutCase() {
        let byName = ItemQuery(text: "LINT").apply(to: report.items, in: report)
        XCTAssertEqual(byName.map(\.name), ["lint"])

        let byDescription = ItemQuery(text: "production").apply(to: report.items, in: report)
        XCTAssertEqual(byDescription.map(\.scope), [.user])

        let byPath = ItemQuery(text: ".mcp.json").apply(to: report.items, in: report)
        XCTAssertEqual(byPath.map(\.name), ["supabase"])

        let byMetadata = ItemQuery(text: "mcp.supabase.com").apply(to: report.items, in: report)
        XCTAssertEqual(byMetadata.map(\.name), ["supabase"])
    }

    func testEverySearchWordMustMatch() {
        XCTAssertEqual(ItemQuery(text: "ship repo").apply(to: report.items, in: report).map(\.scope), [.project])
        XCTAssertTrue(ItemQuery(text: "ship nothing-like-this").apply(to: report.items, in: report).isEmpty)
    }

    func testDiacriticsAreIgnored() {
        XCTAssertEqual(ItemQuery(text: "prodüction").apply(to: report.items, in: report).count, 1)
    }

    func testScopeAndStatusFilters() {
        let repoOnly = ItemQuery(scopes: [.project]).apply(to: report.items(of: .skill), in: report)
        XCTAssertTrue(repoOnly.allSatisfy { $0.scope == .project })
        XCTAssertEqual(repoOnly.count, 3)

        let overridden = ItemQuery(statuses: [.overridden]).apply(to: report.items, in: report)
        XCTAssertEqual(overridden.map(\.name), ["deploy"])

        let wontLoad = ItemQuery(statuses: [.wontLoad]).apply(to: report.items, in: report)
        XCTAssertEqual(wontLoad.map(\.name), ["broken"])
    }

    func testOnlyWithIssuesKeepsFlaggedItems() {
        let flagged = ItemQuery(onlyWithIssues: true).apply(to: report.items, in: report)
        XCTAssertEqual(Set(flagged.map(\.name)), ["deploy", "broken"])
    }

    func testClearFiltersKeepsTheSearchText() {
        var query = ItemQuery(text: "deploy", scopes: [.user], statuses: [.applies], onlyWithIssues: true)
        XCTAssertTrue(query.hasFilters)
        query.clearFilters()
        XCTAssertFalse(query.hasFilters)
        XCTAssertEqual(query.text, "deploy")
    }

    func testDiagnosticsAreSearchable() {
        XCTAssertEqual(ItemQuery(text: "broken.md").apply(to: report.diagnostics).count, 1)
        XCTAssertEqual(ItemQuery().apply(to: report.diagnostics), report.diagnostics)
    }

    func testStatusMapping() {
        XCTAssertEqual(ItemQuery.Status(.effective), .applies)
        XCTAssertEqual(ItemQuery.Status(.combined), .applies)
        XCTAssertEqual(ItemQuery.Status(.shadowed(by: "x")), .overridden)
        XCTAssertEqual(ItemQuery.Status(.invalid), .wontLoad)
    }

    func testFilteringThousandsOfItemsIsFast() {
        let template = report.items[0]
        let many = (0..<5000).map { index in
            var item = ConfigItem(
                kind: .skill,
                name: "skill-\(index)",
                summary: "Generated skill number \(index)",
                scope: index.isMultiple(of: 2) ? .project : .user,
                source: SourceLocation(path: "/tmp/skills/\(index)/SKILL.md")
            )
            item.applicability = template.applicability
            return item
        }
        let start = Date()
        let results = ItemQuery(text: "number 4999", scopes: [.user]).apply(to: many, in: report)
        XCTAssertEqual(results.map(\.name), ["skill-4999"])
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
