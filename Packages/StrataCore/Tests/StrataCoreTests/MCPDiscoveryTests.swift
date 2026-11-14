@testable import StrataCore
import XCTest

final class MCPDiscoveryTests: XCTestCase {
    func testFindsUserLocalAndProjectServers() throws {
        let fixture = try Fixture()
        try fixture.json(".claude.json", in: fixture.home, [
            "mcpServers": ["github": ["type": "http", "url": "https://api.githubcopilot.com/mcp/"]],
            "projects": [fixture.repository.path: ["mcpServers": ["stripe": ["type": "http", "url": "https://mcp.stripe.com"]]]],
        ])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["db": ["command": "/usr/bin/true", "args": ["--port", "5432"]]]])

        let report = fixture.inspect()
        XCTAssertEqual(try report.onlyItem(.mcpServer, named: "github").scope, .user)
        XCTAssertEqual(try report.onlyItem(.mcpServer, named: "stripe").scope, .local)
        let database = try report.onlyItem(.mcpServer, named: "db")
        XCTAssertEqual(database.scope, .project)
        XCTAssertEqual(database.metadataValue("Transport"), "stdio")
        XCTAssertEqual(database.metadataValue("Arguments"), "--port 5432")
        XCTAssertNotNil(database.condition, "Unapproved .mcp.json servers should explain the approval prompt")
    }

    func testURLWithoutTypeIsAConfigurationError() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["broken": ["url": "https://example.com/mcp"]]])

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.mcpServer, named: "broken").loadBlocker)
        XCTAssertTrue(report.hasDiagnostic(.mcpURLWithoutType))
    }

    func testSDKTypeIsSkippedAndStreamableHTTPIsAnAlias() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": [
            "inproc": ["type": "sdk"],
            "remote": ["type": "streamable-http", "url": "https://example.com/mcp"],
        ]])

        let report = fixture.inspect()
        XCTAssertNotNil(try report.onlyItem(.mcpServer, named: "inproc").loadBlocker)
        XCTAssertEqual(try report.onlyItem(.mcpServer, named: "remote").metadataValue("Transport"), "http")
    }

    func testMissingAbsoluteExecutableIsReported() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["gone": ["command": "/nonexistent/server"]]])

        XCTAssertTrue(fixture.inspect().hasDiagnostic(.mcpMissingExecutable))
    }

    func testRelativeExecutableIsReported() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["local": ["command": "./scripts/server"]]])

        XCTAssertTrue(fixture.inspect().hasDiagnostic(.mcpRelativeExecutable))
    }

    func testBareCommandIsLookedUpOnSearchPaths() throws {
        let fixture = try Fixture()
        _ = try fixture.makeExecutable("found-server")
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": [
            "found": ["command": "found-server"],
            "lost": ["command": "lost-server"],
        ]])

        let diagnostics = fixture.inspect().diagnostics.filter { $0.code == .mcpExecutableNotOnStandardPath }
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].title.contains("lost"))
    }

    func testApprovalSettingsAreRespected() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": [
            "approved": ["command": "/usr/bin/true"],
            "rejected": ["command": "/usr/bin/true"],
            "teamApproved": ["command": "/usr/bin/true"],
        ]])
        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["enabledMcpjsonServers": ["approved"]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["disabledMcpjsonServers": ["rejected"], "enabledMcpjsonServers": ["teamApproved"]])

        let report = fixture.inspect()
        let approved = try report.onlyItem(.mcpServer, named: "approved")
        XCTAssertNil(approved.condition)
        XCTAssertEqual(approved.metadataValue("Approval"), "Approved in Project local settings")
        XCTAssertNotNil(try report.onlyItem(.mcpServer, named: "rejected").inactiveReason)
        XCTAssertTrue(try report.onlyItem(.mcpServer, named: "teamApproved").condition?.contains("trust") ?? false)
    }

    func testToggledOffServersAreInactive() throws {
        let fixture = try Fixture()
        try fixture.json(".claude.json", in: fixture.home, [
            "mcpServers": ["github": ["type": "http", "url": "https://example.com"]],
            "projects": [fixture.repository.path: ["disabledMcpServers": ["github"]]],
        ])

        XCTAssertNotNil(try fixture.inspect().onlyItem(.mcpServer, named: "github").inactiveReason)
    }

    func testEndpointNormalisationMatchesDocumentedRules() {
        let normalise = MCPScanner.normalisedEndpoint
        XCTAssertEqual(normalise("HTTPS://MCP.Example.com:443/mcp/"), normalise("https://mcp.example.com/mcp"))
        XCTAssertNotEqual(normalise("https://mcp.example.com/mcp"), normalise("https://mcp.example.com/other"))
        XCTAssertNotEqual(normalise("https://mcp.example.com:8443/mcp"), normalise("https://mcp.example.com/mcp"))
    }

    func testMalformedMCPFileIsReported() throws {
        let fixture = try Fixture()
        try fixture.write(".mcp.json", in: fixture.repository, "{ \"mcpServers\": { ")

        let report = fixture.inspect()
        XCTAssertTrue(report.hasDiagnostic(.malformedJSON))
        XCTAssertTrue(report.sources.contains { $0.path.hasSuffix(".mcp.json") && { if case .malformed = $0.state { return true } else { return false } }($0) })
    }
}
