@testable import StrataCore
import XCTest

/// Permission rules as items: where they come from, which wait for trust, and which a deny or ask rule certainly beats.
final class PermissionScannerTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private func permissions(_ value: [String: Any]) -> [String: Any] { ["permissions": value] }

    private func rules(_ report: InspectionReport? = nil) -> [ConfigItem] {
        (report ?? fixture.inspect()).items.filter { $0.kind == .permission }
    }

    private func rule(_ name: String, list: String, in items: [ConfigItem]) throws -> ConfigItem {
        try XCTUnwrap(items.first { $0.name == name && $0.metadataValue("List") == list }, "\(list) \(name)")
    }

    func testRulesFromEveryFileAndWhichWaitForTrust() throws {
        try fixture.json("settings.json", in: fixture.claude, permissions(["allow": ["Bash(git status)"], "deny": ["Read(./.env)"]]))
        try fixture.json(".claude/settings.json", in: fixture.repository, permissions(["allow": ["Bash(npm run test:*)"], "ask": ["Bash(git push:*)"]]))
        try fixture.json(".claude/settings.local.json", in: fixture.repository, permissions(["allow": ["WebFetch(domain:example.com)"]]))
        let items = rules()

        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(try rule("Bash(git status)", list: "Allow", in: items).applicability, .effective, "User allow rules apply")
        XCTAssertEqual(try rule("Bash(npm run test:*)", list: "Allow", in: items).applicability, .conditional, "Project allow rules wait for trust")
        XCTAssertEqual(try rule("Bash(git push:*)", list: "Ask", in: items).applicability, .effective, "Ask rules only restrict, so they don't wait")
        XCTAssertEqual(try rule("Read(./.env)", list: "Deny", in: items).applicability, .effective)
        let local = try rule("WebFetch(domain:example.com)", list: "Allow", in: items)
        XCTAssertEqual(local.applicability, .effective, "Your own settings.local.json is applied without trust")
        XCTAssertNotNil(local.metadataValue("Note"), "It says git tracking would change that")
        let test = try rule("Bash(npm run test:*)", list: "Allow", in: items)
        XCTAssertEqual(test.metadataValue("Tool"), "Bash")
        XCTAssertEqual(test.metadataValue("Specifier"), "npm run test:*")
    }

    func testALinkedClaudeFolderMakesLocalAllowRulesWaitForTrust() throws {
        let real = fixture.root.appendingPathComponent("shared-claude")
        try fixture.json("settings.local.json", in: real, permissions(["allow": ["Bash(make)"]]))
        try FileManager.default.createSymbolicLink(at: fixture.repository.appendingPathComponent(".claude"), withDestinationURL: real)
        XCTAssertEqual(try rule("Bash(make)", list: "Allow", in: rules()).applicability, .conditional)
    }

    func testDenyAndAskRulesThatCertainlyMatchOverrideAllowRules() throws {
        try fixture.json("settings.json", in: fixture.claude, permissions(["deny": ["WebFetch"], "ask": ["Bash(git push:*)"]]))
        try fixture.json(".claude/settings.local.json", in: fixture.repository, permissions([
            "allow": ["WebFetch(domain:example.com)", "Bash(git push:*)", "Bash(git status)"],
        ]))
        let items = rules()
        let deny = try rule("WebFetch", list: "Deny", in: items)
        let ask = try rule("Bash(git push:*)", list: "Ask", in: items)

        XCTAssertEqual(try rule("WebFetch(domain:example.com)", list: "Allow", in: items).applicability, .shadowed(by: deny.id),
                       "A deny with no specifier blocks every use, whatever file it's in")
        XCTAssertEqual(try rule("Bash(git push:*)", list: "Allow", in: items).applicability, .shadowed(by: ask.id),
                       "An identical ask rule prompts first")
        XCTAssertEqual(try rule("Bash(git status)", list: "Allow", in: items).applicability, .effective, "A different specifier isn't assumed to overlap")
    }

    func testToolWithStarIsTheSameAsTheBareTool() {
        XCTAssertEqual(PermissionScanner.parse("Bash(*)").specifier, nil)
        XCTAssertEqual(PermissionScanner.parse("Bash").tool, "Bash")
        XCTAssertEqual(PermissionScanner.parse("Bash(echo (hi))").specifier, "echo (hi)", "Parentheses inside are literal")
        XCTAssertEqual(PermissionScanner.parse("mcp__github__create_issue").tool, "mcp__github__create_issue")
    }

    func testManagedOnlyRulesTurnOffEveryOtherFile() throws {
        try fixture.json("managed-settings.json", in: try XCTUnwrap(fixture.environment.managedDirectory), [
            "allowManagedPermissionRulesOnly": true,
            "permissions": ["deny": ["Bash(curl:*)"]],
        ])
        try fixture.json("settings.json", in: fixture.claude, permissions(["allow": ["Bash(git status)"]]))
        let items = rules()
        XCTAssertEqual(try rule("Bash(git status)", list: "Allow", in: items).applicability, .inactive)
        XCTAssertEqual(try rule("Bash(curl:*)", list: "Deny", in: items).applicability, .effective)
    }

    func testDefaultModeFollowsPrecedenceAndExtraDirectoriesWaitForTrust() throws {
        try fixture.json("settings.json", in: fixture.claude, permissions(["defaultMode": "acceptEdits"]))
        try fixture.json(".claude/settings.json", in: fixture.repository, permissions(["defaultMode": "plan", "additionalDirectories": ["../shared"]]))
        let items = rules()
        let modes = items.filter { $0.metadataValue("List") == "Default mode" }
        let project = try XCTUnwrap(modes.first { $0.scope == .project })
        XCTAssertEqual(project.applicability, .effective, "Project settings outrank user settings")
        XCTAssertEqual(modes.first { $0.scope == .user }?.applicability, .shadowed(by: project.id))
        XCTAssertEqual(items.first { $0.metadataValue("List") == "Additional directory" }?.applicability, .conditional)
    }

    func testSecretsInRulesAreMaskedAndAllowRulesGetASecurityNote() throws {
        try fixture.json("settings.json", in: fixture.claude, permissions(["allow": ["Bash(curl -H 'Authorization: Bearer ghp_SECRETSECRETSECRETSECRET' *)"]]))
        let report = fixture.inspect()
        let encoded = String(bytes: try JSONEncoder().encode(report), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains("SECRETSECRET"))

        let item = try XCTUnwrap(rules(report).first)
        let notes = SecurityReview.notes(for: ConfigChange(kind: .created, item: item, pickup: ChangeDetector.pickup(.created, item, old: report)))
        XCTAssertTrue(notes.contains { $0.text.contains("without asking") })
    }
}
