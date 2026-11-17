import StrataCore
import XCTest

final class ClaudeProjectsTests: XCTestCase {
    func testListsExistingProjectFoldersOnce() throws {
        let fixture = try Fixture()
        let other = fixture.home.appendingPathComponent("code/zeta")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let link = fixture.home.appendingPathComponent("code/alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        try fixture.json(".claude.json", in: fixture.home, [
            "projects": [
                fixture.repository.path: ["allowedTools": []],
                other.path: [:],
                other.path + "/": [:],
                link.path: [:],
                fixture.home.path: [:],
                "/": [:],
                fixture.home.appendingPathComponent("code/deleted").path: [:],
                "relative/path": [:],
            ],
        ])

        let folders = ClaudeProjects.folders(environment: fixture.environment).map(\.lastPathComponent)
        // alias sorts before zeta and points at it, so zeta is the duplicate. The home folder, root, a deleted folder
        // and a relative key are left out.
        XCTAssertEqual(Set(folders), [fixture.repository.lastPathComponent, "alias"])
        XCTAssertEqual(folders.count, 2)
    }

    func testMissingOrMalformedConfigSuggestsNothing() throws {
        let fixture = try Fixture()
        XCTAssertEqual(ClaudeProjects.folders(environment: fixture.environment), [])
        try fixture.write(".claude.json", in: fixture.home, "{ not json")
        XCTAssertEqual(ClaudeProjects.folders(environment: fixture.environment), [])
        try fixture.json(".claude.json", in: fixture.home, ["projects": ["a", "b"]])
        XCTAssertEqual(ClaudeProjects.folders(environment: fixture.environment), [])
    }
}
