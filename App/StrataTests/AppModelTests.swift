@testable import Strata
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    func testAddingAFolderSelectsIt() {
        let model = AppModel()
        model.add(URL(fileURLWithPath: "/tmp/strata/one"))

        XCTAssertEqual(model.repositories.count, 1)
        XCTAssertEqual(model.selectedRepository?.displayName, "one")
    }

    func testAddingTheSameFolderTwiceKeepsOneEntry() {
        let model = AppModel()
        model.add(URL(fileURLWithPath: "/tmp/strata/one"))
        model.add(URL(fileURLWithPath: "/tmp/strata/two"))
        model.add(URL(fileURLWithPath: "/tmp/strata/one/"))

        XCTAssertEqual(model.repositories.map(\.displayName), ["one", "two"])
        XCTAssertEqual(model.selectedRepository?.displayName, "one")
    }

    func testRemovingTheSelectedRepositorySelectsTheNextOne() throws {
        let model = AppModel()
        model.add(URL(fileURLWithPath: "/tmp/strata/one"))
        model.add(URL(fileURLWithPath: "/tmp/strata/two"))
        let selected = try XCTUnwrap(model.selectedRepositoryID)

        model.remove(selected)

        XCTAssertEqual(model.repositories.map(\.displayName), ["one"])
        XCTAssertEqual(model.selectedRepository?.displayName, "one")
    }
}
