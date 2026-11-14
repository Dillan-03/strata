@testable import Strata
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var folders: [URL] = []

    override func setUpWithError() throws {
        suiteName = "strata.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        folders = try (0..<3).map { index in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("strata-model-\(UUID().uuidString)/repo\(index)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        folders.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
    }

    private func makeModel() -> AppModel {
        AppModel(store: RepositoryStore(defaults: defaults))
    }

    func testAddingAFolderSelectsIt() {
        let model = makeModel()
        model.add(folders[0])

        XCTAssertEqual(model.repositories.count, 1)
        XCTAssertEqual(model.selectedRepository?.displayName, "repo0")
    }

    func testAddingTheSameFolderTwiceKeepsOneEntry() {
        let model = makeModel()
        model.add(folders[0])
        model.add(folders[1])
        model.add(folders[0].appendingPathComponent("."))

        XCTAssertEqual(model.repositories.map(\.displayName), ["repo0", "repo1"])
        XCTAssertEqual(model.selectedRepository?.displayName, "repo0")
    }

    func testRemovingTheSelectedRepositorySelectsTheNextOne() throws {
        let model = makeModel()
        model.add(folders[0])
        model.add(folders[1])
        let selected = try XCTUnwrap(model.selectedRepositoryID)

        model.remove(selected)

        XCTAssertEqual(model.repositories.map(\.displayName), ["repo0"])
        XCTAssertEqual(model.selectedRepository?.displayName, "repo0")
    }

    func testRepositoriesPersistAcrossLaunches() {
        let first = makeModel()
        first.add(folders[0])
        first.add(folders[1])

        let second = makeModel()
        XCTAssertEqual(second.repositories.map(\.displayName), ["repo0", "repo1"])
        XCTAssertEqual(second.repositories.map(\.id), first.repositories.map(\.id))
    }

    func testDeletedFolderIsRestoredAsMissing() throws {
        let first = makeModel()
        first.add(folders[2])
        try FileManager.default.removeItem(at: folders[2])

        let second = makeModel()
        let repository = try XCTUnwrap(second.repositories.first)
        XCTAssertTrue(second.isMissing(repository.id))
    }

    func testRelocatingClearsTheMissingState() throws {
        let first = makeModel()
        first.add(folders[2])
        try FileManager.default.removeItem(at: folders[2])
        let second = makeModel()
        let id = try XCTUnwrap(second.repositories.first?.id)

        second.relocate(id, to: folders[1])

        XCTAssertFalse(second.isMissing(id))
        XCTAssertEqual(second.repositories.first?.displayName, "repo1")
        XCTAssertEqual(makeModel().repositories.first?.displayName, "repo1")
    }
}
