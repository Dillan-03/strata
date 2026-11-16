@testable import Strata
import StrataCore
import XCTest

/// Records announcements instead of posting notifications.
@MainActor
private final class AnnouncementRecorder: ChangeAnnouncing {
    var announcements: [[PendingChange]] = []

    func announce(_ changes: [PendingChange]) {
        announcements.append(changes)
    }
}

/// Baselines, the pending-change list and notifications, against a throwaway home folder with two repositories.
@MainActor
final class ChangeTrackingTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-changes-\(UUID().uuidString)").resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        for name in ["web", "api"] {
            try FileManager.default.createDirectory(at: repository(name), withIntermediateDirectories: true)
        }
        suiteName = "strata.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func repository(_ name: String) -> URL {
        home.appendingPathComponent("code/\(name)")
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private var globalSkill: URL { home.appendingPathComponent(".claude/skills/deploy/SKILL.md") }

    /// A model with both repositories added and scanned once, so both have a baseline.
    private func makeScannedModel() async -> AppModel {
        let model = AppModel(store: RepositoryStore(defaults: defaults), environment: ScanEnvironment(homeDirectory: home, managedDirectory: nil))
        model.add(repository("web"))
        model.add(repository("api"))
        await scanAll(model)
        return model
    }

    private func scanAll(_ model: AppModel) async {
        for repository in model.repositories {
            await model.scan(repository.id)
        }
    }

    func testFirstScanIsTheStartingPoint() async throws {
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        let model = await makeScannedModel()

        XCTAssertTrue(model.pendingChanges.isEmpty)
        XCTAssertNotNil(model.changesSince)
    }

    func testGlobalChangeIsListedOnceWithEveryRepositoryItReached() async throws {
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        let model = await makeScannedModel()

        try write("---\ndescription: Deploy, then smoke test\n---\n", to: globalSkill)
        await scanAll(model)

        let pending = try XCTUnwrap(model.pendingChanges.first)
        XCTAssertEqual(model.pendingChanges.count, 1)
        XCTAssertEqual(pending.change.kind, .updated)
        XCTAssertEqual(Set(pending.repositoryIDs), Set(model.repositories.map(\.id)))
        XCTAssertEqual(model.impacts(of: pending.change).map(\.impact.effect), [.affected, .affected])
    }

    func testRepositoryChangeOnlyShowsForThatRepository() async throws {
        let model = await makeScannedModel()
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })
        let api = try XCTUnwrap(model.repositories.first { $0.displayName == "api" })

        try write("# Web rules\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        await scanAll(model)

        XCTAssertEqual(model.changes(reaching: web.id).map(\.change.item.name), ["CLAUDE.md"])
        XCTAssertTrue(model.changes(reaching: api.id).isEmpty)
    }

    func testMarkingReviewedStartsAgainFromNow() async throws {
        let model = await makeScannedModel()
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        await scanAll(model)
        XCTAssertFalse(model.pendingChanges.isEmpty)

        model.markChangesReviewed()
        XCTAssertTrue(model.pendingChanges.isEmpty)
        await scanAll(model)
        XCTAssertTrue(model.pendingChanges.isEmpty, "Nothing changed after the review")
    }

    func testRemovingARepositoryDropsItsChanges() async throws {
        let model = await makeScannedModel()
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })
        try write("# Web rules\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        await scanAll(model)
        XCTAssertEqual(model.pendingChanges.count, 1)

        model.remove(web.id)
        XCTAssertTrue(model.pendingChanges.isEmpty)
    }

    func testNewGlobalSkillThatHidesARepositoryCopyShowsTheConflict() async throws {
        try write("---\ndescription: Repo deploy\n---\n", to: repository("web").appendingPathComponent(".claude/skills/deploy/SKILL.md"))
        let model = await makeScannedModel()

        try write("---\ndescription: Personal deploy\n---\n", to: globalSkill)
        await scanAll(model)

        let pending = try XCTUnwrap(model.pendingChanges.first { $0.change.item.scope == .user })
        XCTAssertEqual(pending.change.kind, .created)
        XCTAssertTrue(model.conflicts(for: pending).contains { $0.code == .shadowedDefinition })
    }

    // MARK: - Status per item

    func testItemStatusFollowsWhenClaudeCodeSeesTheChange() async throws {
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        try write("# Web rules\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        let model = await makeScannedModel()
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })
        let report = try XCTUnwrap(model.reports[web.id])
        let skill = try XCTUnwrap(report.items.first { $0.kind == .skill })
        let rules = try XCTUnwrap(report.items.first { $0.kind == .instruction })
        XCTAssertEqual(model.syncStatus(of: skill.id, in: web.id), .unchanged)

        try write("---\ndescription: Deploy, then smoke test\n---\n", to: globalSkill)
        try write("# Web rules\nBe brief.\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        await scanAll(model)

        XCTAssertEqual(model.syncStatus(of: skill.id, in: web.id), .changeDetected, "Skill edits are picked up live")
        XCTAssertEqual(model.syncStatus(of: rules.id, in: web.id), .actionRequired(.nextSession), "Instructions load at session start")

        model.markChangesReviewed()
        XCTAssertEqual(model.syncStatus(of: skill.id, in: web.id), .unchanged)
    }

    func testChangedItemWithAConflictSaysSo() async throws {
        try write("---\ndescription: Repo deploy\n---\n", to: repository("web").appendingPathComponent(".claude/skills/deploy/SKILL.md"))
        let model = await makeScannedModel()
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })

        try write("---\ndescription: Personal deploy\n---\n", to: globalSkill)
        await scanAll(model)

        let personal = try XCTUnwrap(model.reports[web.id]?.items.first { $0.kind == .skill && $0.scope == .user })
        XCTAssertEqual(model.syncStatus(of: personal.id, in: web.id), .conflict)
    }

    func testReviewingOneChangeOpensTheSheetOnIt() async throws {
        let model = await makeScannedModel()
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        await scanAll(model)
        let pending = try XCTUnwrap(model.pendingChanges.first)

        model.review(pending)
        XCTAssertTrue(model.isReviewingChanges)
        XCTAssertEqual(model.reviewSelection, pending.id)
    }

    // MARK: - Fixes

    private struct OverriddenSkill {
        let repositoryID: Repository.ID
        let fix: ConfigFix
        let folder: URL
    }

    /// The web repository's own deploy skill, overridden by a personal one, and the offered fix of `action`.
    private func overriddenRepoSkill(_ model: AppModel, action: ConfigFix.Action) throws -> OverriddenSkill {
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })
        model.selectedRepositoryID = web.id
        let item = try XCTUnwrap(model.reports[web.id]?.items.first { $0.kind == .skill && $0.scope == .project })
        guard case .available(let fixes) = model.fixOffer(for: item) else {
            XCTFail("Expected a fix for the overridden repository skill")
            throw CancellationError()
        }
        let fix = try XCTUnwrap(fixes.first { $0.action == action })
        return OverriddenSkill(repositoryID: web.id, fix: fix, folder: repository("web").appendingPathComponent(".claude/skills/deploy"))
    }

    private func makeModelWithOverriddenSkill() async throws -> AppModel {
        try write("---\ndescription: Repo deploy\n---\n", to: repository("web").appendingPathComponent(".claude/skills/deploy/SKILL.md"))
        try write("---\ndescription: Personal deploy\n---\n", to: globalSkill)
        return await makeScannedModel()
    }

    func testFixesDoNothingWhileTurnedOff() async throws {
        let model = try await makeModelWithOverriddenSkill()
        let skill = try overriddenRepoSkill(model, action: .removeCopy)
        let (web, fix, folder) = (skill.repositoryID, skill.fix, skill.folder)

        let outcome = await model.apply(fix, in: web)
        guard case .failed = outcome else { return XCTFail("Expected a refusal, got \(outcome)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(model.fixRecords.isEmpty)
    }

    func testAnApprovedFixRunsRescansAndCanBeUndone() async throws {
        defaults.set(true, forKey: PreferenceKey.allowsFixes)
        let model = try await makeModelWithOverriddenSkill()
        let skill = try overriddenRepoSkill(model, action: .removeCopy)
        let (web, fix, folder) = (skill.repositoryID, skill.fix, skill.folder)

        guard case .applied(let record) = await model.apply(fix, in: web) else { return XCTFail("The fix didn't run") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(model.fixRecords.map(\.id), [record.id])
        XCTAssertFalse(model.reports[web]?.items.contains { $0.kind == .skill && $0.scope == .project } ?? true, "Rescanned after the fix")
        XCTAssertTrue(model.pendingChanges.contains { $0.change.kind == .deleted }, "The fix shows up in Review Changes like any other change")
        XCTAssertTrue(record.backupPath.hasPrefix(model.fixBackupDirectory.path))

        guard case .undone = await model.undo(record) else { return XCTFail("Undo didn't run") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("SKILL.md").path))
    }

    func testAFailedFixIsRememberedForTheItem() async throws {
        defaults.set(true, forKey: PreferenceKey.allowsFixes)
        let model = try await makeModelWithOverriddenSkill()
        let skill = try overriddenRepoSkill(model, action: .replaceWithWinner)
        let (web, fix, folder) = (skill.repositoryID, skill.fix, skill.folder)
        try write("---\ndescription: Edited after review\n---\n", to: folder.appendingPathComponent("SKILL.md"))

        guard case .failed = await model.apply(fix, in: web) else { return XCTFail("An edit after review must stop the fix") }
        XCTAssertNotNil(model.failedFixes[fix.target.id], "The inspector shows the failure")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8), "---\ndescription: Edited after review\n---\n")
    }

    // MARK: - Notifications

    /// A scanned model that announces through a recorder, with notifications turned on unless `enabled` is false.
    private func makeAnnouncingModel(enabled: Bool = true) async -> (AppModel, AnnouncementRecorder) {
        defaults.set(enabled, forKey: NotificationPreferences.enabledKey)
        let model = await makeScannedModel()
        let recorder = AnnouncementRecorder()
        model.announcer = recorder
        return (model, recorder)
    }

    func testChangesAreAnnouncedOnceWhenDue() async throws {
        let (model, recorder) = await makeAnnouncingModel()
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        try write("# Web rules\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        await scanAll(model)

        model.announceDueChanges(at: .now)
        XCTAssertTrue(recorder.announcements.isEmpty, "Too soon: the burst hasn't settled")
        model.announceDueChanges(at: .now.addingTimeInterval(60))
        XCTAssertEqual(recorder.announcements.map(\.count), [2])
        model.announceDueChanges(at: .now.addingTimeInterval(120))
        XCTAssertEqual(recorder.announcements.count, 1, "Each change is announced once")
    }

    func testMutedRepositoryIsNotAnnounced() async throws {
        let (model, recorder) = await makeAnnouncingModel()
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })
        model.setNotifiesAboutChanges(false, in: web.id)

        try write("# Web rules\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        await scanAll(model)
        model.announceDueChanges(at: .now.addingTimeInterval(60))

        XCTAssertTrue(recorder.announcements.isEmpty)
        XCTAssertEqual(model.pendingChanges.count, 1, "Muting only silences notifications; the change is still listed")
        XCTAssertFalse(NotificationPreferences(defaults: defaults).mutedRepositoryIDs.isEmpty, "The choice is saved")
    }

    func testGlobalChangeIsAnnouncedWhileAnyRepositoryItReachesIsUnmuted() async throws {
        let (model, recorder) = await makeAnnouncingModel()
        let web = try XCTUnwrap(model.repositories.first { $0.displayName == "web" })
        model.setNotifiesAboutChanges(false, in: web.id)

        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        await scanAll(model)
        model.announceDueChanges(at: .now.addingTimeInterval(60))

        XCTAssertEqual(recorder.announcements.map(\.count), [1])
    }

    func testPausedOrDisabledNotificationsStaySilent() async throws {
        let (model, recorder) = await makeAnnouncingModel(enabled: false)
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        await scanAll(model)
        model.announceDueChanges(at: .now.addingTimeInterval(60))
        XCTAssertTrue(recorder.announcements.isEmpty, "Off by default")

        defaults.set(true, forKey: NotificationPreferences.enabledKey)
        defaults.set(Date.now.addingTimeInterval(3600).timeIntervalSinceReferenceDate, forKey: NotificationPreferences.pausedUntilKey)
        try write("# Web rules\n", to: repository("web").appendingPathComponent("CLAUDE.md"))
        await scanAll(model)
        model.announceDueChanges(at: .now.addingTimeInterval(60))
        XCTAssertTrue(recorder.announcements.isEmpty, "Paused")
    }

    func testNotificationTextNamesOneChangeOrCountsSeveral() async throws {
        let model = await makeScannedModel()
        try write("---\ndescription: Deploy\n---\n", to: globalSkill)
        await scanAll(model)
        XCTAssertEqual(ChangeNotificationText.body(for: model.pendingChanges), "Skill /deploy was added (global).")

        for name in ["web", "api"] {
            try write("# Rules\n", to: repository(name).appendingPathComponent("CLAUDE.md"))
        }
        await scanAll(model)
        XCTAssertEqual(ChangeNotificationText.body(for: model.pendingChanges), "/deploy, CLAUDE.md and 1 more changed. Open Strata to review them.")
    }
}
