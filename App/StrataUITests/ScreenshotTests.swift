import XCTest

/// Captures the README screenshots against a realistic fixture. Skipped unless the Screenshots workflow sets
/// `STRATA_SCREENSHOTS=1`; the workflow extracts the attachments from the result bundle.
final class ScreenshotTests: XCTestCase {
    private var root: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testCaptureReadmeScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STRATA_SCREENSHOTS"] == "1", "Runs only in the Screenshots workflow")
        let (home, repository) = try makeFixture()

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": repository.path,
            "STRATA_UITEST_HOME": home.path,
        ]
        app.launch()
        let window = app.windows.firstMatch

        let summary = app.buttons["issuesSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        capture(window, as: "overview")

        summary.click()
        XCTAssertTrue(app.staticTexts["Global skill deploy hides the repo copy"].waitForExistence(timeout: 10))
        capture(window, as: "issues")

        let showRepoCopy = app.descendants(matching: .any).matching(identifier: "showItem.project.deploy").firstMatch
        XCTAssertTrue(showRepoCopy.waitForExistence(timeout: 5))
        showRepoCopy.click()
        XCTAssertTrue(app.staticTexts["Which Copy Runs"].waitForExistence(timeout: 10))
        capture(window, as: "inspector")

        app.typeKey("4", modifierFlags: .command)
        let postgres = app.descendants(matching: .any).matching(identifier: "itemRow.mcpServer.project.postgres").firstMatch
        XCTAssertTrue(postgres.waitForExistence(timeout: 10), "The postgres row isn't in the MCP list")
        postgres.click()
        // postgres has one definition, so the inspector shows the MCP safety note rather than "Which Copy Runs".
        // macOS static text can carry its string in value rather than label, so match either. Only static text:
        // other elements' values can be numbers, which a substring match would throw on.
        let noteText = "never runs this command"
        let safetyNote = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", noteText, noteText)).firstMatch
        XCTAssertTrue(safetyNote.waitForExistence(timeout: 10), "The MCP inspector didn't open")
        capture(window, as: "mcp")

        try editConfiguration(home: home, repository: repository)
        app.typeKey("r", modifierFlags: .command)
        let review = app.buttons["reviewChangesButton"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), "The change banner didn't appear")
        review.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "textDiff").firstMatch.waitForExistence(timeout: 10))
        capture(window, as: "review")

        let permissions = app.descendants(matching: .any).matching(identifier: "changeRow.updated.permissions").firstMatch
        XCTAssertTrue(permissions.waitForExistence(timeout: 5), "The permissions change isn't listed")
        permissions.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "keyDiff").firstMatch.waitForExistence(timeout: 10))
        capture(window, as: "review-settings")
    }

    /// Edits made outside the app after the first scan: a skill's description, a new permission and hook, and a server argument.
    private func editConfiguration(home: URL, repository: URL) throws {
        let edits: [(URL, String)] = [
            (
                home.appendingPathComponent(".claude/skills/deploy/SKILL.md"),
                "---\ndescription: Deploy any project, then run the smoke tests\n---\n"
            ),
            (
                home.appendingPathComponent(".claude/settings.json"),
                #"""
                {"model": "sonnet", "enabledPlugins": {"supabase-kit@tools": true},
                  "permissions": {"allow": ["Bash(npm run test:*)", "Bash(git push *)"]},
                  "hooks": {"PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "npx prettier --write ."}]}]}}
                """#
            ),
            (
                repository.appendingPathComponent(".mcp.json"),
                #"""
                {"mcpServers": {"postgres": {"command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://app:example-password@localhost/acme", "--read-only"],
                  "env": {"PGPASSWORD": "example-password"}}}}
                """#
            ),
        ]
        for (url, contents) in edits {
            try Data(contents.utf8).write(to: url)
        }
    }

    private func capture(_ window: XCUIElement, as name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A personal skill hiding a repo skill, competing subagents, a plugin, MCP servers whose secrets get masked,
    /// instructions and settings. Every value is fake.
    private func makeFixture() throws -> (home: URL, repository: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-screens-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/acme-web")
        let plugin = home.appendingPathComponent(".claude/plugins/cache/tools/supabase-kit/1.2.0")

        let files: [(URL, String)] = [
            (home.appendingPathComponent(".claude/skills/deploy/SKILL.md"), "---\ndescription: Deploy any project with my usual checks\n---\n"),
            (home.appendingPathComponent(".claude/skills/review/SKILL.md"), "---\ndescription: Review the current diff\nallowed-tools: Read, Grep\n---\n"),
            (home.appendingPathComponent(".claude/agents/reviewer.md"), "---\nname: reviewer\ndescription: General code reviewer\n---\n"),
            (home.appendingPathComponent(".claude/CLAUDE.md"), "# Personal\n\nPrefer small, reviewable diffs.\n"),
            (
                home.appendingPathComponent(".claude/settings.json"),
                #"""
                {"model": "sonnet", "enabledPlugins": {"supabase-kit@tools": true},
                  "permissions": {"allow": ["Bash(npm run test:*)"]}}
                """#
            ),
            (
                home.appendingPathComponent(".claude.json"),
                #"""
                {"mcpServers": {"github": {"type": "http", "url": "https://api.githubcopilot.com/mcp/",
                  "headers": {"Authorization": "Bearer ${GITHUB_TOKEN}"}}}}
                """#
            ),
            (plugin.appendingPathComponent(".claude-plugin/plugin.json"), #"{"name": "supabase-kit", "version": "1.2.0", "description": "Supabase helpers"}"#),
            (plugin.appendingPathComponent("skills/migrate/SKILL.md"), "---\ndescription: Write and check a migration\n---\n"),
            (
                home.appendingPathComponent(".claude/plugins/installed_plugins.json"),
                #"{"version": 2, "plugins": {"supabase-kit@tools": [{"scope": "user", "installPath": "\#(plugin.path)", "version": "1.2.0"}]}}"#
            ),
            (repository.appendingPathComponent("CLAUDE.md"), "# Acme Web\n\nRun `npm test` before committing.\n\n@docs/conventions.md\n"),
            (repository.appendingPathComponent("docs/conventions.md"), "Use TanStack Query for server state.\n"),
            (repository.appendingPathComponent(".claude/rules/testing.md"), "---\npaths:\n  - \"src/**/*.test.ts\"\n---\nKeep tests next to the code.\n"),
            (repository.appendingPathComponent(".claude/skills/deploy/SKILL.md"), "---\ndescription: Deploy acme-web to staging\n---\n"),
            (repository.appendingPathComponent(".claude/agents/reviewer.md"), "---\nname: reviewer\ndescription: Reviews against Acme conventions\ntools: Read, Grep, Glob\n---\n"),
            (repository.appendingPathComponent(".claude/settings.json"), #"{"permissions": {"deny": ["Read(./.env)"]}}"#),
            (
                repository.appendingPathComponent(".mcp.json"),
                #"""
                {"mcpServers": {"postgres": {"command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://app:example-password@localhost/acme"],
                  "env": {"PGPASSWORD": "example-password"}}}}
                """#
            ),
        ]
        for (url, contents) in files {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        return (home, repository)
    }
}
