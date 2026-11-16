@testable import StrataCore
import XCTest

/// Golden-text tests: each prompt variant, word for word, from a realistic before-and-after scan.
final class UpdatePromptTests: XCTestCase {
    private struct Scenario {
        let change: ConfigChange
        let impacts: [RepositoryImpact]
        let conflicts: [Diagnostic]
        let home: String

        var prompt: String { UpdatePrompt.make(for: change, impacts: impacts, conflicts: conflicts, homePath: home) }
    }

    /// Scans, applies `edit`, scans again, and returns the change whose item has `name`.
    private func scenario(
        _ fixture: Fixture,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        edit: () throws -> Void
    ) throws -> Scenario {
        let before = fixture.inspect()
        try edit()
        let after = fixture.inspect()
        let change = try XCTUnwrap(ChangeDetector.changes(from: before, to: after).first { $0.item.name == name }, file: file, line: line)
        return Scenario(
            change: change,
            impacts: ChangeImpact.impacts(of: change, before: [before], after: [after]),
            conflicts: after.diagnostics(for: change.item.id),
            home: fixture.home.path
        )
    }

    func testEditedGlobalSkill() throws {
        let fixture = try Fixture()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy anything"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Repo deploy"))
        let scenario = try scenario(fixture, named: "deploy") {
            try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy, then smoke test"))
        }

        XCTAssertEqual(scenario.prompt, """
            My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:

            The global skill `/deploy` was edited.
            - File: ~/.claude/skills/deploy/SKILL.md
            - Scope: global, so it applies in every repository
            - Takes effect in: ~/code/repo

            What changed (+1 −1 lines):
            ```diff
             ---
            -description: Deploy anything
            +description: Deploy, then smoke test
             ---
             Instructions.
            ```

            Conflicts Strata found:
            - Global skill deploy hides the repo copy: Overridden by the personal skill at ~/.claude/skills/deploy/SKILL.md.\
             Personal skills (~/.claude/skills) take precedence over project skills, so /deploy runs that one.

            When Claude Code sees it: Claude Code watches skills folders and picks up added, edited and removed skills without a restart.

            Please:
            1. Use the current `/deploy`, not the version you saw earlier in this session.
            2. Read ~/.claude/skills/deploy/SKILL.md and tell me in a sentence or two what it now says, so I know you have the new version.
            """)
        XCTAssertNil(UpdatePrompt.beforePasting(scenario.change), "Skill edits are picked up live")
    }

    func testNewProjectServerMasksItsSecrets() throws {
        let fixture = try Fixture()
        let scenario = try scenario(fixture, named: "pg") {
            try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": [
                "command": "npx",
                "args": ["-y", "pg", "postgresql://app:pw-123@localhost/db"],
                "env": ["PGPASSWORD": "pw-123"],
            ]]])
        }

        XCTAssertEqual(scenario.prompt, """
            My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:

            The repo MCP server `pg` was added.
            - File: ~/code/repo/.mcp.json, under `mcpServers.pg`
            - Scope: this repository only
            - May take effect in: ~/code/repo (only under a condition)

            What changed:
            - `args` added: ["-y", "pg", "postgresql://••••••:••••••@localhost/db"]
            - `command` added: npx
            - `env.PGPASSWORD` added: ••••••
            (•••••• marks values Strata masked.)

            When Claude Code sees it: The Claude Code docs don't say whether a running session picks up edits to MCP configuration. A new session is the safe choice.

            Please:
            1. Check whether tools from the `pg` server are available to you, and list them.
            2. If they aren't, say so; I'll check the connection with /mcp.
            """)
        XCTAssertFalse(scenario.prompt.contains("pw-123"))
        XCTAssertEqual(
            UpdatePrompt.beforePasting(scenario.change),
            "Claude Code's docs don't say when this applies. A new session is the sure way; pasting this tells the open one."
        )
    }

    func testEditedInstructionFile() throws {
        let fixture = try Fixture()
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Rules\n- Use npm\n- Be brief\n")
        let scenario = try scenario(fixture, named: "CLAUDE.md") {
            try fixture.write("CLAUDE.md", in: fixture.repository, "# Rules\n- Use pnpm\n- Be brief\n")
        }

        XCTAssertEqual(scenario.prompt, """
            My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:

            The repo instruction file `CLAUDE.md` was edited.
            - File: ~/code/repo/CLAUDE.md
            - Scope: this repository only
            - Takes effect in: ~/code/repo

            What changed (+1 −1 lines):
            ```diff
             # Rules
            -- Use npm
            +- Use pnpm
             - Be brief
            ```

            When Claude Code sees it: Loaded at session start. The project-root CLAUDE.md is also re-read after /compact.

            Please:
            1. Read ~/code/repo/CLAUDE.md again and follow it for the rest of this session.
            2. Summarise what changed in a sentence or two.
            """)
        XCTAssertEqual(UpdatePrompt.beforePasting(scenario.change), "A new session picks this up fully. Pasting this tells the session you have open about it.")
    }

    func testRemovedPluginLeavesOutStrataBookkeeping() throws {
        let fixture = try Fixture()
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": true]])
        let scenario = try scenario(fixture, named: "kit@tools") {
            try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": [String: Bool]()])
        }

        XCTAssertEqual(scenario.prompt, """
            My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:

            The plugin `kit@tools` was removed.
            - Was in: ~/.claude/settings.json, under `enabledPlugins.kit@tools`
            - Scope: global, so it applies in every repository

            When Claude Code sees it: Plugin changes apply after /reload-plugins, or in a new session.

            Please:
            1. Stop using skills, subagents or tools from the `kit@tools` plugin. Tell me if anything we're doing relied on them.
            """)
        XCTAssertEqual(UpdatePrompt.beforePasting(scenario.change), "Run /reload-plugins in Claude Code first, then paste this.")
    }

    func testRotatedSecretSettingSaysOnlyThatItChanged() throws {
        let fixture = try Fixture()
        try fixture.json("settings.json", in: fixture.claude, ["env": ["API_TOKEN": "first-token-value"]])
        let scenario = try scenario(fixture, named: "env") {
            try fixture.json("settings.json", in: fixture.claude, ["env": ["API_TOKEN": "second-token-value"]])
        }

        XCTAssertEqual(scenario.prompt, """
            My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:

            The global setting `env` was edited.
            - File: ~/.claude/settings.json, under `env`
            - Scope: global, so it applies in every repository
            - Takes effect in: ~/code/repo

            What changed:
            - `env.API_TOKEN` changed (the value is masked)
            (•••••• marks values Strata masked.)

            When Claude Code sees it: Claude Code reloads settings files when they change, including permissions and hooks.

            Please:
            1. Take this into account for the rest of the session, and tell me if it affects what we're doing.
            """)
        XCTAssertFalse(scenario.prompt.contains("token-value"))
    }

    func testDeletedSubagent() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, "---\nname: reviewer\ndescription: Reviews diffs\n---\nBe strict.\n")
        let scenario = try scenario(fixture, named: "reviewer") {
            try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent(".claude/agents/reviewer.md"))
        }

        XCTAssertEqual(scenario.prompt, """
            My Claude Code configuration changed while this session was running. Strata, the app I use to inspect it, found this:

            The repo subagent `reviewer` was removed.
            - Was in: ~/code/repo/.claude/agents/reviewer.md
            - Scope: this repository only
            - Takes effect in: ~/code/repo

            What changed (+0 −5 lines):
            ```diff
            ----
            -name: reviewer
            -description: Reviews diffs
            ----
            -Be strict.
            ```

            When Claude Code sees it: Claude Code detects subagent changes within a few seconds; the next delegation uses them.

            Please:
            1. Don't delegate to the `reviewer` subagent any more: it no longer exists.
            """)
    }

    func testLongDiffsStopAtTheLimit() throws {
        let fixture = try Fixture()
        let body = (1...100).map { "Step \($0)." }.joined(separator: "\n")
        let scenario = try scenario(fixture, named: "CLAUDE.md") {
            try fixture.write("CLAUDE.md", in: fixture.repository, body)
        }

        XCTAssertTrue(scenario.prompt.contains("What changed (+100 −0 lines, first \(UpdatePrompt.diffLineLimit) shown):"))
        XCTAssertTrue(scenario.prompt.contains("+Step \(UpdatePrompt.diffLineLimit)."))
        XCTAssertFalse(scenario.prompt.contains("+Step \(UpdatePrompt.diffLineLimit + 1)."))
        XCTAssertTrue(scenario.prompt.contains("@@ \(100 - UpdatePrompt.diffLineLimit) more lines: read the file for the rest @@"))
    }

    func testEmptiedObjectHasNoPlaceholderRow() throws {
        let old = ItemContent.keyed(["kit@tools": true] as [String: Any], root: "enabledPlugins")
        let new = ItemContent.keyed([String: Any](), root: "enabledPlugins")
        guard case .keyed(let keys) = ConfigDiff(before: old, after: new) else { return XCTFail("Expected a key diff") }
        XCTAssertEqual(keys.map(\.path), ["enabledPlugins.kit@tools"])
        XCTAssertEqual(keys.map(\.kind), [.removed])
    }

    func testPathsOutsideHomeStayWhole() {
        XCTAssertEqual(UpdatePrompt.abbreviate("/Users/me/code/app", homePath: "/Users/me"), "~/code/app")
        XCTAssertEqual(UpdatePrompt.abbreviate("/Users/meg/code", homePath: "/Users/me"), "/Users/meg/code")
        XCTAssertEqual(UpdatePrompt.abbreviate("/Library/Claude", homePath: "/Users/me"), "/Library/Claude")
    }
}
