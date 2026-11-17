@testable import StrataCore
import XCTest

final class ReportExportTests: XCTestCase {
    private var fixture: Fixture!
    private var report: InspectionReport!

    override func setUpWithError() throws {
        fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill(description: "Personal deploy"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Repo deploy"))
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": [
            "notes": ["command": "notes-mcp", "env": ["NOTES_TOKEN": "sk-ant-api03-SECRETSECRETSECRET"]],
        ]])
        report = fixture.inspect()
    }

    override func tearDown() {
        fixture = nil
        report = nil
    }

    private func export(_ items: [ConfigItem]? = nil) -> ReportExport {
        ReportExport(report: report, items: items ?? report.items, strataVersion: "0.5.0 (5)", homeDirectory: fixture.home)
    }

    func testMarkdownListsItemsByKindWithStatusAndIssues() throws {
        let markdown = export().markdown()
        XCTAssertTrue(markdown.hasPrefix("# Claude Code configuration for \(fixture.repository.lastPathComponent)"))
        XCTAssertTrue(markdown.contains("## Skills (2)"))
        XCTAssertTrue(markdown.contains("**Overridden**"))
        XCTAssertTrue(markdown.contains("## Issues"), "The overridden skill raises an issue")
        XCTAssertTrue(markdown.contains("## MCP Servers (1)"))
        XCTAssertTrue(markdown.contains("Strata 0.5.0 (5)"))
    }

    func testBothFormatsShortenHomeAndMaskSecrets() throws {
        for format in ReportExport.Format.allCases {
            let text = String(bytes: try export().data(as: format), encoding: .utf8) ?? ""
            XCTAssertFalse(text.contains("SECRETSECRET"), "\(format) leaks a secret")
            XCTAssertFalse(text.contains(fixture.home.path), "\(format) has an unshortened home path")
            XCTAssertTrue(text.contains("~/"), "\(format) shortens home paths")
        }
    }

    func testJSONIsStructuredAndParses() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try export().json()) as? [String: Any])
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, report.items.count)
        let skill = try XCTUnwrap(items.first { $0["kind"] as? String == "skill" && $0["status"] as? String == "Overridden" })
        XCTAssertEqual(skill["scope"] as? String, "project")
        XCTAssertNotNil(object["scannedAt"] as? String)
        XCTAssertFalse((object["issues"] as? [Any] ?? []).isEmpty)
    }

    func testAFilteredExportHasOnlyThoseItems() throws {
        let skills = report.items.filter { $0.kind == .skill }
        let markdown = export(skills).markdown()
        XCTAssertTrue(markdown.contains("## Skills (2)"))
        XCTAssertFalse(markdown.contains("## MCP Servers"))
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: try export(skills).json()) as? [String: Any])["items"] as? [Any]
        XCTAssertEqual(items?.count, 2)
    }
}
