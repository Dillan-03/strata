@testable import StrataCore
import XCTest

final class ChangeReviewTests: XCTestCase {
    private let mask = SecretRedactor.mask

    private func onlyChange(_ before: InspectionReport, _ after: InspectionReport, file: StaticString = #filePath, line: UInt = #line) throws -> ConfigChange {
        let changes = ChangeDetector.changes(from: before, to: after)
        XCTAssertEqual(changes.count, 1, "\(changes.map { "\($0.kind) \($0.item.kind) \($0.item.name)" })", file: file, line: line)
        return try XCTUnwrap(changes.first, file: file, line: line)
    }

    private struct WrongDiff: Error {}

    private func keys(_ diff: ConfigDiff, file: StaticString = #filePath, line: UInt = #line) throws -> [KeyChange] {
        guard case .keyed(let keys) = diff else {
            XCTFail("Expected a key diff, got \(diff)", file: file, line: line)
            throw WrongDiff()
        }
        return keys
    }

    private func text(_ diff: ConfigDiff, file: StaticString = #filePath, line: UInt = #line) throws -> TextDiff {
        guard case .text(let text) = diff else {
            XCTFail("Expected a text diff, got \(diff)", file: file, line: line)
            throw WrongDiff()
        }
        return text
    }

    // MARK: - Masking what's kept

    func testDocumentsMaskSecretAssignmentsAndTokensButKeepProse() {
        let document = """
        ---
        description: Uses a token for auth
        ---
        export API_KEY=abc123secret
        password: "hunter2"
        GITHUB_TOKEN=${GITHUB_TOKEN}
        Paste ghp_abcdefghijklmnopqrstuvwxyz0123456789 into the prompt.
        """
        let redacted = SecretRedactor.redactDocument(document)

        XCTAssertTrue(redacted.contains("description: Uses a token for auth"))
        XCTAssertTrue(redacted.contains("export API_KEY=\(mask)"))
        XCTAssertTrue(redacted.contains("password: \(mask)"))
        XCTAssertTrue(redacted.contains("GITHUB_TOKEN=${GITHUB_TOKEN}"))
        XCTAssertTrue(redacted.contains("Paste \(mask) into the prompt."))
        for secret in ["abc123secret", "hunter2", "ghp_abcdefghij"] {
            XCTAssertFalse(redacted.contains(secret))
        }
    }

    func testServerEntriesFlattenToMaskedKeys() throws {
        let content = ItemContent.keyed([
            "command": "npx",
            "args": ["-y", "server", "--api-key", "abc123"],
            "env": ["DB_URL": "postgres://localhost/app"],
            "headers": ["X-Trace": "on"],
            "url": "https://user:pa55@mcp.example.com/mcp?token=s3cr3t&region=eu",
        ] as [String: Any])
        guard case .keyed(let values) = content else { return XCTFail("Expected keyed content") }
        let display = Dictionary(uniqueKeysWithValues: values.map { ($0.path, $0.display) })

        XCTAssertEqual(display["command"], "npx")
        XCTAssertEqual(display["args"], "[\"-y\", \"server\", \"--api-key\", \"\(mask)\"]")
        XCTAssertEqual(display["env.DB_URL"], mask, "Every environment value is masked, even harmless-looking ones")
        XCTAssertEqual(display["headers.X-Trace"], mask)
        let url = try XCTUnwrap(display["url"])
        XCTAssertFalse(url.contains("pa55"))
        XCTAssertFalse(url.contains("s3cr3t"))
        XCTAssertTrue(url.contains("region=eu"))
        XCTAssertTrue(content.hasMaskedValues)
    }

    func testListsOfObjectsGetIndexedPaths() {
        let hooks: [String: Any] = ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "./check.sh"]]]]]
        guard case .keyed(let values) = ItemContent.keyed(hooks, root: "hooks") else { return XCTFail("Expected keyed content") }
        XCTAssertEqual(values.map(\.path), [
            "hooks.PreToolUse[0].hooks[0].command",
            "hooks.PreToolUse[0].hooks[0].type",
            "hooks.PreToolUse[0].matcher",
        ])
        XCTAssertEqual(values.first?.display, "./check.sh")
    }

    func testEveryItemKeepsItsContent() throws {
        let fixture = try Fixture()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy"))
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, "---\nname: reviewer\ndescription: Reviews\n---\n")
        try fixture.json("settings.json", in: fixture.claude, ["model": "sonnet"])
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": ["command": "npx"]]])
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Rules\n")

        let report = fixture.inspect()
        XCTAssertEqual(report.items.filter { report.contents[$0.id] == nil }.map(\.name), [])
        let skill = try XCTUnwrap(report.items.first { $0.kind == .skill })
        XCTAssertEqual(report.contents[skill.id], .text(Fixture.skill(description: "Deploy")))
    }

    // MARK: - Text diffs

    func testEditShowsTheChangedLineWithContext() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "line 10\n", with: "line ten\n")
        let diff = TextDiff(old: old, new: new)

        XCTAssertEqual(diff.addedCount, 1)
        XCTAssertEqual(diff.removedCount, 1)
        XCTAssertEqual(diff.hunks.count, 1)
        let hunk = diff.hunks[0]
        XCTAssertEqual(hunk.skippedBefore, 6)
        XCTAssertEqual(hunk.lines.map(\.kind), [.unchanged, .unchanged, .unchanged, .removed, .added, .unchanged, .unchanged, .unchanged])
        XCTAssertEqual(hunk.lines[3].oldNumber, 10)
        XCTAssertEqual(hunk.lines[4].newNumber, 10)
        XCTAssertEqual(hunk.lines[4].text, "line ten")
        XCTAssertEqual(diff.skippedAfter, 7)
    }

    func testDistantEditsMakeSeparateHunks() {
        let old = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 2\n", with: "line two\n").replacingOccurrences(of: "line 28\n", with: "line twenty-eight\n")
        let diff = TextDiff(old: old, new: new)

        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertEqual(diff.hunks[0].skippedBefore, 0)
        XCTAssertEqual(diff.hunks[1].skippedBefore, 19)
        XCTAssertEqual(diff.skippedAfter, 0)
    }

    func testNewAndRemovedFilesAreAllAddedOrAllRemoved() {
        let created = TextDiff(old: nil, new: "a\nb\n")
        XCTAssertEqual(created.hunks.flatMap(\.lines).map(\.kind), [.added, .added])
        XCTAssertEqual(created.hunks.flatMap(\.lines).map(\.newNumber), [1, 2])

        let removed = TextDiff(old: "a\r\nb\r\n", new: nil)
        XCTAssertEqual(removed.hunks.flatMap(\.lines).map(\.text), ["a", "b"], "CRLF endings and the final newline add no phantom lines")
        XCTAssertEqual(removed.removedCount, 2)
    }

    func testIdenticalTextHasNoHunks() {
        let diff = TextDiff(old: "a\nb\nc\n", new: "a\nb\nc\n")
        XCTAssertTrue(diff.hunks.isEmpty)
        XCTAssertEqual(diff.skippedAfter, 3)
        XCTAssertTrue(ConfigDiff(before: .text("a"), after: .text("a")).isUnchanged)
    }

    // MARK: - Key diffs

    func testKeyDiffKeepsOrderAndPlacesRemovedKeysByTheirNeighbour() throws {
        let old = ItemContent.keyed(["a": "1", "b": "2", "c": "3"])
        let new = ItemContent.keyed(["a": "1", "c": "4", "d": "5"])
        let changes = try keys(ConfigDiff(before: old, after: new))

        XCTAssertEqual(changes.map(\.path), ["a", "b", "c", "d"])
        XCTAssertEqual(changes.map(\.kind), [.unchanged, .removed, .changed, .added])
        XCTAssertEqual(changes[2].before, "3")
        XCTAssertEqual(changes[2].after, "4")
    }

    func testRotatedSecretIsAChangeBehindTheMask() throws {
        let old = ItemContent.keyed(["env": ["API_TOKEN": "old-secret-value"]] as [String: Any])
        let new = ItemContent.keyed(["env": ["API_TOKEN": "new-secret-value"]] as [String: Any])
        let change = try XCTUnwrap(keys(ConfigDiff(before: old, after: new)).first)

        XCTAssertEqual(change.kind, .changed)
        XCTAssertTrue(change.changedBehindMask)
        XCTAssertEqual(change.before, mask)
        XCTAssertEqual(change.after, mask)
    }

    // MARK: - Changes carry both versions

    func testGlobalSkillEditCarriesBothVersions() throws {
        let fixture = try Fixture()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy anything"))
        let before = fixture.inspect()
        try fixture.write("skills/deploy/SKILL.md", in: fixture.claude, Fixture.skill(description: "Deploy, then smoke test"))

        let change = try onlyChange(before, fixture.inspect())
        let diff = try text(ConfigDiff(change))
        let changed = diff.hunks.flatMap(\.lines).filter { $0.kind != .unchanged }
        XCTAssertEqual(changed.map(\.kind), [.removed, .added])
        XCTAssertEqual(changed.map(\.text), ["description: Deploy anything", "description: Deploy, then smoke test"])
        XCTAssertTrue(SecurityReview.notes(for: change).isEmpty, "A description edit carries no security note")
    }

    func testRotatingAServerSecretNeverExposesIt() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": ["command": "npx", "env": ["PGPASSWORD": "first-secret-1"]]]])
        let before = fixture.inspect()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": ["command": "npx", "env": ["PGPASSWORD": "second-secret-2"]]]])

        let change = try onlyChange(before, fixture.inspect())
        let env = try XCTUnwrap(keys(ConfigDiff(change)).first { $0.path == "env.PGPASSWORD" })
        XCTAssertTrue(env.changedBehindMask)
        let everything = "\(change) \(ConfigDiff(change)) \(SecurityReview.notes(for: change))"
        XCTAssertFalse(everything.contains("first-secret-1"))
        XCTAssertFalse(everything.contains("second-secret-2"))
    }

    func testDeletedItemKeepsWhatItWas() throws {
        let fixture = try Fixture()
        try fixture.write("CLAUDE.md", in: fixture.repository, "# Rules\nBe brief.\n")
        let before = fixture.inspect()
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("CLAUDE.md"))

        let change = try onlyChange(before, fixture.inspect())
        XCTAssertEqual(change.kind, .deleted)
        XCTAssertNil(change.after)
        XCTAssertEqual(try text(ConfigDiff(change)).removedCount, 2)
    }

    // MARK: - Security notes

    func testNewStdioServerNamesTheCommandItRuns() throws {
        let fixture = try Fixture()
        let before = fixture.inspect()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": ["command": "npx", "args": ["-y", "pg"]]]])

        let notes = SecurityReview.notes(for: try onlyChange(before, fixture.inspect()))
        XCTAssertTrue(notes.contains { $0.level == .caution && $0.text.contains("runs `npx`") })
        XCTAssertTrue(notes.contains { $0.text.contains("asks before it first uses") })
    }

    func testChangedServerCommandIsFlagged() throws {
        let fixture = try Fixture()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": ["command": "npx", "args": ["-y", "pg"]]]])
        let before = fixture.inspect()
        try fixture.json(".mcp.json", in: fixture.repository, ["mcpServers": ["pg": ["command": "npx", "args": ["-y", "pg-evil"]]]])

        let notes = SecurityReview.notes(for: try onlyChange(before, fixture.inspect()))
        XCTAssertEqual(notes.map(\.text), ["The command this server runs changed."])
    }

    func testHooksAndPermissionsAreFlagged() throws {
        let fixture = try Fixture()
        try fixture.json("settings.json", in: fixture.claude, ["permissions": ["allow": ["Bash(npm test)"]]])
        let before = fixture.inspect()
        try fixture.json("settings.json", in: fixture.claude, [
            "permissions": ["allow": ["Bash(npm test)", "Bash(rm *)"], "defaultMode": "bypassPermissions"],
            "hooks": ["PostToolUse": [["matcher": "Edit", "hooks": [["type": "command", "command": "./format.sh"]]]]],
        ])

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        let notes = changes.flatMap(SecurityReview.notes(for:)).map(\.text)
        XCTAssertTrue(notes.contains { $0.hasPrefix("Hooks run shell commands") })
        XCTAssertTrue(notes.contains("Changes what Claude Code may do without asking you first."))
        XCTAssertTrue(notes.contains("bypassPermissions skips every permission prompt."))
    }

    func testBypassInARepositoryFileExplainsTheVersionRule() throws {
        let fixture = try Fixture()
        let before = fixture.inspect()
        try fixture.json(".claude/settings.json", in: fixture.repository, ["permissions": ["defaultMode": "bypassPermissions"]])

        let after = fixture.inspect()
        let setting = try XCTUnwrap(ChangeDetector.changes(from: before, to: after).first { $0.item.kind == .setting })
        let notes = SecurityReview.notes(for: setting).map(\.text)
        XCTAssertTrue(notes.contains { $0.contains("2.1.257 and later ignore it here") })
        let mode = try XCTUnwrap(after.items.first { $0.kind == .permission && $0.name == "defaultMode" })
        XCTAssertEqual(mode.applicability, .inactive, "The mode item agrees: a repository file's bypassPermissions is ignored")
    }

    func testSkillAllowedToolsAndAgentToolsAreFlagged() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/ship/SKILL.md", in: fixture.repository, Fixture.skill(description: "Ship"))
        try fixture.write(".claude/agents/fixer.md", in: fixture.repository, "---\nname: fixer\ndescription: Fixes\n---\n")
        let before = fixture.inspect()
        try fixture.write(".claude/skills/ship/SKILL.md", in: fixture.repository, Fixture.skill(description: "Ship", extra: "allowed-tools: Bash(git push *)"))
        try fixture.write(".claude/agents/fixer.md", in: fixture.repository, "---\nname: fixer\ndescription: Fixes\ntools: Read, Edit, Bash\n---\n")

        let changes = ChangeDetector.changes(from: before, to: fixture.inspect())
        let skill = try XCTUnwrap(changes.first { $0.item.kind == .skill })
        let agent = try XCTUnwrap(changes.first { $0.item.kind == .agent })
        let skillNote = try XCTUnwrap(SecurityReview.notes(for: skill).first)
        XCTAssertEqual(skillNote.level, .caution)
        XCTAssertTrue(skillNote.text.contains("without asking"))
        XCTAssertTrue(skillNote.text.contains("haven't trusted"), "A project skill's grant applies without workspace trust")
        XCTAssertEqual(SecurityReview.notes(for: agent).map(\.level), [.info])
    }

    func testMaskedValuesGetANote() throws {
        let fixture = try Fixture()
        let before = fixture.inspect()
        try fixture.json("settings.json", in: fixture.claude, ["env": ["API_TOKEN": "abc"]])

        let notes = SecurityReview.notes(for: try onlyChange(before, fixture.inspect()))
        XCTAssertEqual(notes.map(\.level), [.info])
        XCTAssertTrue(notes[0].text.contains("masked"))
    }
}
