@testable import Strata
import StrataCore
import XCTest

final class RepositoryStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-store-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSaveAndLoadRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "strata.store.\(UUID().uuidString)"))
        let store = RepositoryStore(defaults: defaults)
        let entry = RepositoryStore.entry(for: Repository(url: try makeFolder("one")))

        store.save([entry])

        XCTAssertEqual(store.load(), [entry])
    }

    func testCorruptDataLoadsAsEmpty() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "strata.store.\(UUID().uuidString)"))
        defaults.set(Data("not json".utf8), forKey: RepositoryStore.defaultsKey)

        XCTAssertEqual(RepositoryStore(defaults: defaults).load(), [])
    }

    func testFolderInPlaceIsAvailable() throws {
        let folder = try makeFolder("here")
        let entry = RepositoryStore.entry(for: Repository(url: folder))

        guard case .available(let url) = RepositoryStore.locate(entry) else { return XCTFail("Expected the folder to be available") }
        XCTAssertEqual(url.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
    }

    func testRenamedFolderIsFoundThroughItsBookmark() throws {
        let folder = try makeFolder("before")
        let entry = RepositoryStore.entry(for: Repository(url: folder))
        XCTAssertNotNil(entry.bookmark)
        let renamed = root.appendingPathComponent("after", isDirectory: true)
        try FileManager.default.moveItem(at: folder, to: renamed)

        guard case .moved(let url) = RepositoryStore.locate(entry) else {
            return XCTFail("Expected the bookmark to follow the rename")
        }
        XCTAssertEqual(url.resolvingSymlinksInPath().lastPathComponent, "after")
    }

    func testDeletedFolderIsMissing() throws {
        let folder = try makeFolder("gone")
        let entry = RepositoryStore.entry(for: Repository(url: folder))
        try FileManager.default.removeItem(at: folder)

        XCTAssertEqual(RepositoryStore.locate(entry), .missing)
    }

    func testEntryWithoutBookmarkFallsBackToPath() throws {
        let folder = try makeFolder("plain")
        let entry = RepositoryStore.Entry(id: UUID(), path: folder.path, bookmark: nil)

        guard case .available(let url) = RepositoryStore.locate(entry) else { return XCTFail("Expected the folder to be available") }
        XCTAssertEqual(url.path, folder.path)
    }
}
