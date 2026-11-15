@testable import Strata
import StrataCore
import XCTest

/// Baselines and the pending-change list, against a throwaway home folder with two repositories.
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
}
