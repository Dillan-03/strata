@testable import StrataCore
import XCTest

/// Fixing overridden copies: what's offered, what's written, what's refused, and undo.
final class ConfigFixTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    // MARK: - Helpers

    private var repoSkill: URL { fixture.repository.appendingPathComponent(".claude/skills/deploy") }
    private var personalSkill: URL { fixture.claude.appendingPathComponent("skills/deploy") }
    private var backups: URL { fixture.home.appendingPathComponent("Library/Application Support/Strata/Backups") }

    /// A repository skill with a supporting script, overridden by a personal skill of the same name.
    private func makeOverriddenRepoSkill() throws {
        try fixture.write("SKILL.md", in: repoSkill, Fixture.skill(description: "Repo deploy"))
        try fixture.write("scripts/run.sh", in: repoSkill, "#!/bin/sh\necho repo\n")
        try fixture.write("SKILL.md", in: personalSkill, Fixture.skill(description: "Personal deploy"))
    }

    private func writer(for repository: URL? = nil, fileManager: FileManager = .default) -> ConfigWriter {
        let path = (repository ?? fixture.repository).path
        return ConfigWriter(
            backupDirectory: backups,
            allowedRoots: FixPlanner.allowedRoots(repositoryPath: path, environment: fixture.environment),
            fileManager: fileManager
        )
    }

    private func fixes(for kind: ItemKind, scope: Scope, in report: InspectionReport? = nil) throws -> [ConfigFix] {
        let report = report ?? fixture.inspect()
        let item = try XCTUnwrap(report.items.first { $0.kind == kind && $0.scope == scope })
        guard case .available(let fixes) = FixPlanner.offer(for: item, in: report, environment: fixture.environment) else {
            XCTFail("Expected fixes for \(item.name), got \(FixPlanner.offer(for: item, in: report, environment: fixture.environment))")
            return []
        }
        return fixes
    }

    private func fix(_ action: ConfigFix.Action) throws -> ConfigFix {
        try XCTUnwrap(fixes(for: .skill, scope: .project).first { $0.action == action })
    }

    private func tree(_ url: URL) throws -> String { try Fingerprint.ofTree(url) }

    private var backupFolders: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? []
    }

    // MARK: - What's offered

    func testOverriddenRepositorySkillCanBeRemovedOrReplaced() throws {
        try makeOverriddenRepoSkill()
        let fixes = try fixes(for: .skill, scope: .project)

        XCTAssertEqual(fixes.map(\.action), [.removeCopy, .replaceWithWinner])
        XCTAssertEqual(fixes[0].targetURL.path, repoSkill.standardizedFileURL.path, "A skill is fixed as a whole folder")
        XCTAssertEqual(fixes[1].sourceURL?.path, personalSkill.standardizedFileURL.path)
    }

    func testCommandHiddenByASkillCanOnlyBeRemoved() throws {
        try fixture.write(".claude/commands/deploy.md", in: fixture.repository, "Deploy the old way.\n")
        try fixture.write("SKILL.md", in: personalSkill, Fixture.skill(description: "Personal deploy"))

        XCTAssertEqual(try fixes(for: .command, scope: .project).map(\.action), [.removeCopy], "A skill can't replace a command")
    }

    func testCopiesThatApplyOrAreLinkedAreNotOffered() throws {
        try makeOverriddenRepoSkill()
        let report = fixture.inspect()
        let personal = try XCTUnwrap(report.items.first { $0.kind == .skill && $0.scope == .user })
        XCTAssertEqual(FixPlanner.offer(for: personal, in: report, environment: fixture.environment), .none, "The copy that runs has nothing to fix")

        let elsewhere = fixture.root.appendingPathComponent("dotfiles/deploy")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: repoSkill, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: repoSkill, withDestinationURL: elsewhere)
        let linked = fixture.inspect()
        let repo = try XCTUnwrap(linked.items.first { $0.kind == .skill && $0.scope == .project })
        guard case .unavailable(let reason) = FixPlanner.offer(for: repo, in: linked, environment: fixture.environment) else {
            return XCTFail("A symlinked copy should not be offered a fix")
        }
        XCTAssertTrue(reason.contains("symbolic link"))
    }

    // MARK: - Uninstalling

    private func uninstall(_ item: ConfigItem, in report: InspectionReport) -> FixOffer {
        FixPlanner.uninstall(item, in: report, environment: fixture.environment)
    }

    private func uninstallFix(kind: ItemKind = .skill, scope: Scope) throws -> (fix: ConfigFix, report: InspectionReport) {
        let report = fixture.inspect()
        let item = try XCTUnwrap(report.items.first { $0.kind == kind && $0.scope == scope })
        guard case .available(let fixes) = uninstall(item, in: report), let fix = fixes.first, fixes.count == 1 else {
            XCTFail("Expected one uninstall fix for \(item.name), got \(uninstall(item, in: report))")
            throw XCTSkip()
        }
        return (fix, report)
    }

    func testUninstallingTheCopyThatRunsNamesWhatTakesOverAndCanBeUndone() throws {
        try makeOverriddenRepoSkill()
        let (fix, report) = try uninstallFix(scope: .user)
        let repoCopy = try XCTUnwrap(report.items.first { $0.kind == .skill && $0.scope == .project })
        XCTAssertEqual(fix.action, .uninstall)
        XCTAssertNil(fix.winner)
        XCTAssertEqual(fix.overridden, [repoCopy], "The repository copy runs once the personal one is gone")
        XCTAssertEqual(fix.targetURL.path, personalSkill.standardizedFileURL.path)
        XCTAssertEqual(fix.pickup.timing, .live)

        let original = try tree(personalSkill)
        let writer = writer()
        let record = try writer.apply(fix)
        XCTAssertEqual(record.action, .uninstall)
        XCTAssertFalse(FileManager.default.fileExists(atPath: personalSkill.path))
        let after = fixture.inspect()
        XCTAssertEqual(after.items.filter { $0.kind == .skill }.map(\.scope), [.project])
        XCTAssertTrue(after.items.first { $0.kind == .skill }?.applicability.isApplied ?? false, "The repository copy now runs")

        try writer.undo(record)
        XCTAssertEqual(try tree(personalSkill), original)
    }

    func testUninstallingACopyNothingBacksUpSaysNothingTakesOver() throws {
        try fixture.write(".claude/agents/reviewer.md", in: fixture.repository, "---\nname: reviewer\ndescription: Reviews code\n---\nReview.\n")
        let (fix, _) = try uninstallFix(kind: .agent, scope: .project)
        XCTAssertEqual(fix.overridden, [])
        XCTAssertEqual(fix.targetURL.lastPathComponent, "reviewer.md", "A subagent is uninstalled as its file")
    }

    func testAnOverriddenCopyIsUninstalledWithTheRemoveFix() throws {
        try makeOverriddenRepoSkill()
        let (fix, _) = try uninstallFix(scope: .project)
        XCTAssertEqual(fix.action, .removeCopy)
        XCTAssertNotNil(fix.winner)
    }

    func testUninstallIsRefusedOutsideTheWritableFolders() throws {
        let report = fixture.inspect()
        let expectations: [(Scope, String)] = [
            (.plugin, "the acme plugin"), (.managed, "managed settings"), (.synced, "claude.ai"), (.nested, "~/.claude"),
        ]
        for (scope, phrase) in expectations {
            let item = ConfigItem(
                kind: .skill, name: "deploy", scope: scope,
                source: SourceLocation(path: fixture.root.appendingPathComponent("elsewhere/deploy/SKILL.md").path), origin: "acme"
            )
            guard case .unavailable(let reason) = uninstall(item, in: report) else { return XCTFail("\(scope) should be refused") }
            XCTAssertTrue(reason.contains(phrase), "\(scope): \(reason)")
        }
        let server = ConfigItem(kind: .mcpServer, name: "github", scope: .user, source: SourceLocation(path: "/tmp/.claude.json"))
        XCTAssertEqual(uninstall(server, in: report), .none, "Only skills, commands and subagents are uninstalled here")
    }

    func testAnUninstallReviewedBeforeAnEditIsRefused() throws {
        try makeOverriddenRepoSkill()
        let (fix, _) = try uninstallFix(scope: .user)
        try fixture.write("SKILL.md", in: personalSkill, Fixture.skill(description: "Edited after review"))

        XCTAssertThrowsError(try writer().apply(fix)) { error in
            guard case FixError.changedSinceReview = error else { return XCTFail("Unexpected error \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: personalSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(backupFolders.isEmpty)
    }

    // MARK: - Applying and undoing

    func testRemovingKeepsTheCopyInBackupsAndUndoPutsItBack() throws {
        try makeOverriddenRepoSkill()
        let original = try tree(repoSkill)
        let writer = writer()

        let record = try writer.apply(fix(.removeCopy))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoSkill.path))
        XCTAssertEqual(try tree(URL(fileURLWithPath: record.backupPath)), original, "The backup holds the folder exactly, script included")
        XCTAssertFalse(fixture.inspect().diagnostics.contains { $0.code == .shadowedDefinition }, "No overridden copy left")
        XCTAssertEqual(writer.records().map(\.id), [record.id])

        let undone = try writer.undo(record)
        XCTAssertEqual(try tree(repoSkill), original)
        XCTAssertNotNil(undone.undoneAt)
        XCTAssertNotNil(writer.records().first?.undoneAt, "The record remembers it was undone")
        XCTAssertThrowsError(try writer.undo(undone))
    }

    func testReplacingCopiesTheWinnerAndUndoRestoresTheOriginal() throws {
        try makeOverriddenRepoSkill()
        let original = try tree(repoSkill)
        let writer = writer()

        let record = try writer.apply(fix(.replaceWithWinner))
        XCTAssertEqual(try tree(repoSkill), try tree(personalSkill), "The repository copy now matches the one that runs")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoSkill.appendingPathComponent("scripts/run.sh").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repoSkill.deletingLastPathComponent().path), ["deploy"], "No temporary copies left behind")

        try writer.undo(record)
        XCTAssertEqual(try tree(repoSkill), original, "The original comes back, script included")
    }

    // MARK: - Refusals

    func testAnEditAfterReviewIsNeverOverwritten() throws {
        try makeOverriddenRepoSkill()
        let remove = try fix(.removeCopy)
        let replace = try fix(.replaceWithWinner)
        try fixture.write("SKILL.md", in: repoSkill, Fixture.skill(description: "Edited after review"))

        for fix in [remove, replace] {
            XCTAssertThrowsError(try writer().apply(fix)) { error in
                guard case FixError.changedSinceReview = error else { return XCTFail("Unexpected \(error)") }
            }
        }
        XCTAssertTrue(try String(contentsOf: repoSkill.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Edited after review"))
        XCTAssertTrue(backupFolders.isEmpty, "Nothing was backed up because nothing was changed")
    }

    func testAChangedWinnerIsNotCopied() throws {
        try makeOverriddenRepoSkill()
        let replace = try fix(.replaceWithWinner)
        try fixture.write("SKILL.md", in: personalSkill, Fixture.skill(description: "Personal, edited after review"))

        XCTAssertThrowsError(try writer().apply(replace))
        XCTAssertTrue(try String(contentsOf: repoSkill.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Repo deploy"))
    }

    func testAFixForAnotherRepositoryIsRefused() throws {
        let other = fixture.home.appendingPathComponent("code/other")
        try fixture.write("SKILL.md", in: other.appendingPathComponent(".claude/skills/deploy"), Fixture.skill(description: "Other deploy"))
        try fixture.write("SKILL.md", in: personalSkill, Fixture.skill(description: "Personal deploy"))
        let otherReport = Inspector(environment: fixture.environment).inspect(other)
        let remove = try XCTUnwrap(fixes(for: .skill, scope: .project, in: otherReport).first)

        XCTAssertThrowsError(try writer(for: fixture.repository).apply(remove)) { error in
            guard case FixError.notAllowed = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.appendingPathComponent(".claude/skills/deploy/SKILL.md").path))
    }

    func testAPermissionErrorChangesNothing() throws {
        try XCTSkipIf(getuid() == 0, "root can write whatever the permissions")
        try makeOverriddenRepoSkill()
        let skills = repoSkill.deletingLastPathComponent()
        let remove = try fix(.removeCopy)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: skills.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: skills.path) }

        XCTAssertThrowsError(try writer().apply(remove)) { error in
            guard case FixError.failed = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(backupFolders.isEmpty, "A failed fix leaves no backup behind")
    }

    func testAFailedSwapRollsBack() throws {
        try makeOverriddenRepoSkill()
        let original = try tree(repoSkill)
        let failing = FailingMoves { source, _ in source.lastPathComponent.hasPrefix(".strata-incoming") }

        XCTAssertThrowsError(try writer(fileManager: failing).apply(fix(.replaceWithWinner)))
        XCTAssertEqual(try tree(repoSkill), original, "The original is back in place")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repoSkill.deletingLastPathComponent().path), ["deploy"])
        XCTAssertTrue(backupFolders.isEmpty)
    }

    func testUndoNeverOverwritesNewWork() throws {
        try makeOverriddenRepoSkill()
        let writer = writer()
        let removed = try writer.apply(fix(.removeCopy))
        try fixture.write("SKILL.md", in: repoSkill, Fixture.skill(description: "Written after the fix"))

        XCTAssertThrowsError(try writer.undo(removed)) { error in
            guard case FixError.undoBlocked = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertTrue(try String(contentsOf: repoSkill.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Written after the fix"))
    }

    func testUndoAfterAnEditToTheReplacementIsRefused() throws {
        try makeOverriddenRepoSkill()
        let writer = writer()
        let replaced = try writer.apply(fix(.replaceWithWinner))
        try fixture.write("SKILL.md", in: repoSkill, Fixture.skill(description: "Edited after the fix"))

        XCTAssertThrowsError(try writer.undo(replaced))
        XCTAssertTrue(try String(contentsOf: repoSkill.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Edited after the fix"))
    }
}

/// Fails chosen moves, to exercise rollback.
private final class FailingMoves: FileManager {
    let shouldFail: (URL, URL) -> Bool

    init(_ shouldFail: @escaping (URL, URL) -> Bool) {
        self.shouldFail = shouldFail
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if shouldFail(srcURL, dstURL) { throw CocoaError(.fileWriteUnknown) }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

final class FixPreviewTests: XCTestCase {
    func testPreviewListsFilesAndDiffsTheMainFileMasked() throws {
        let fixture = try Fixture()
        let repoSkill = fixture.repository.appendingPathComponent(".claude/skills/deploy")
        try fixture.write("SKILL.md", in: repoSkill, Fixture.skill(description: "Repo deploy", extra: "API_TOKEN=abc123secret"))
        try fixture.write("scripts/run.sh", in: repoSkill, "echo repo\n")
        try fixture.write("SKILL.md", in: fixture.claude.appendingPathComponent("skills/deploy"), Fixture.skill(description: "Personal deploy"))
        let report = fixture.inspect()
        let item = try XCTUnwrap(report.items.first { $0.kind == .skill && $0.scope == .project })
        guard case .available(let fixes) = FixPlanner.offer(for: item, in: report, environment: fixture.environment) else {
            return XCTFail("Expected fixes")
        }

        let removal = FixPreview(try XCTUnwrap(fixes.first { $0.action == .removeCopy }))
        XCTAssertEqual(removal.targetFiles, ["SKILL.md", "scripts/run.sh"])
        guard case .text(let removed) = removal.diff else { return XCTFail("Expected a text diff") }
        XCTAssertEqual(removed.addedCount, 0, "A removal only takes lines away")

        let replacement = FixPreview(try XCTUnwrap(fixes.first { $0.action == .replaceWithWinner }))
        XCTAssertEqual(replacement.sourceFiles, ["SKILL.md"])
        guard case .text(let changed) = replacement.diff else { return XCTFail("Expected a text diff") }
        let lines = changed.hunks.flatMap(\.lines).filter { $0.kind != .unchanged }.map(\.text)
        XCTAssertTrue(lines.contains("description: Personal deploy"))
        XCTAssertFalse("\(replacement)".contains("abc123secret"), "The preview is masked")
    }
}
