import Foundation
import StrataCore
import XCTest

final class RepositoryTests: XCTestCase {
    func testDisplayNameIsTheFolderName() {
        let repository = Repository(url: URL(fileURLWithPath: "/Users/dev/code/momentse/"))
        XCTAssertEqual(repository.displayName, "momentse")
    }

    func testDisplayNameFallsBackToPathForRoot() {
        let repository = Repository(url: URL(fileURLWithPath: "/"))
        XCTAssertEqual(repository.displayName, "/")
    }

    func testSameFolderIgnoresTrailingSlashAndDotSegments() {
        let repository = Repository(url: URL(fileURLWithPath: "/tmp/strata/repo"))
        XCTAssertTrue(repository.refersToSameFolder(as: URL(fileURLWithPath: "/tmp/strata/repo/")))
        XCTAssertTrue(repository.refersToSameFolder(as: URL(fileURLWithPath: "/tmp/strata/other/../repo")))
        XCTAssertFalse(repository.refersToSameFolder(as: URL(fileURLWithPath: "/tmp/strata/other")))
    }

    func testRelocateKeepsIdentity() {
        var repository = Repository(url: URL(fileURLWithPath: "/tmp/a"))
        let id = repository.id
        repository.relocate(to: URL(fileURLWithPath: "/tmp/b"))
        XCTAssertEqual(repository.id, id)
        XCTAssertEqual(repository.displayName, "b")
    }

    func testRoundTripsThroughCodable() throws {
        let repository = Repository(url: URL(fileURLWithPath: "/tmp/strata/repo"))
        let decoded = try JSONDecoder().decode(Repository.self, from: JSONEncoder().encode(repository))
        XCTAssertEqual(decoded, repository)
    }
}
