import StrataCore
import XCTest

final class InspectorTests: XCTestCase {
    func testMissingRepositoryIsReportedNotCrashed() throws {
        let fixture = try Fixture()
        let missing = fixture.root.appendingPathComponent("moved-away")

        let report = Inspector(environment: fixture.environment).inspect(missing)
        XCTAssertTrue(report.items.isEmpty)
        XCTAssertEqual(report.diagnostics.first?.severity, .conflict)
    }

    func testEmptyRepositoryHasNoRepositoryConfiguration() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/global/SKILL.md", in: fixture.home, Fixture.skill())

        let report = fixture.inspect()
        XCTAssertFalse(report.hasRepositoryConfiguration)
        XCTAssertFalse(report.items.isEmpty)
    }

    func testSettingsFilesAreListedPerKey() throws {
        let fixture = try Fixture()
        try fixture.json(".claude/settings.json", in: fixture.home, ["model": "opus", "env": ["API_TOKEN": "s3cr3t-value", "REGION": "eu"]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["model": "sonnet"])

        let report = fixture.inspect()
        XCTAssertEqual(Set(report.items(.setting, named: "model").map(\.scope)), [.user, .project])
        XCTAssertEqual(try report.onlyItem(.setting, named: "env").summary, "2 variables: API_TOKEN, REGION")
    }

    func testMalformedSettingsAreReported() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/settings.json", in: fixture.repository, "{ \"model\": ")

        let report = fixture.inspect()
        XCTAssertTrue(report.hasDiagnostic(.malformedJSON))
        XCTAssertTrue(report.items(of: .setting).isEmpty)
    }

    func testScanIsDeterministic() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/b/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.write(".claude/skills/a/SKILL.md", in: fixture.repository, Fixture.skill())
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["z": ["command": "/usr/bin/true"], "y": ["command": "/usr/bin/true"]]])

        let date = Date(timeIntervalSince1970: 0)
        let first = Inspector(environment: fixture.environment).inspect(fixture.repository, at: date)
        let second = Inspector(environment: fixture.environment).inspect(fixture.repository, at: date)
        XCTAssertEqual(first, second)
    }

    /// The most important privacy guarantee: no secret value from any config file appears anywhere in a report.
    func testSecretsNeverAppearInTheReport() throws {
        let fixture = try Fixture()
        let secrets = [
            "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
            "sk-ant-api03-SECRETSECRETSECRETSECRET",
            "hunter2-password",
            "bearer-token-value-123",
            "query-secret-777",
            "env-secret-888",
        ]
        try fixture.json(".claude.json", in: fixture.home, [
            "mcpServers": [
                "remote": [
                    "type": "http",
                    "url": "https://admin:\(secrets[2])@mcp.example.com/mcp?token=\(secrets[4])",
                    "headers": ["Authorization": "Bearer \(secrets[3])", "X-Api-Key": secrets[1]],
                ],
            ],
        ])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": [
            "local": ["command": "/usr/bin/true", "args": ["--token", secrets[0], "--api-key=\(secrets[1])"], "env": ["DB_PASSWORD": secrets[5]]],
        ]])
        try fixture.json(".claude/settings.json", in: fixture.home, ["env": ["GITHUB_TOKEN": secrets[0]], "apiKey": secrets[1]])

        let encoded = String(decoding: try JSONEncoder().encode(fixture.inspect()), as: UTF8.self)
        for secret in secrets {
            XCTAssertFalse(encoded.contains(secret), "Report leaked a secret")
        }
    }
}
