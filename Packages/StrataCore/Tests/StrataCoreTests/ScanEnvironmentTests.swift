import Foundation
import StrataCore
import XCTest

final class ScanEnvironmentTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func testDefaultsToTheHomeFolder() {
        let environment = ScanEnvironment.current(environment: [:], home: home)
        XCTAssertEqual(environment.claudeDirectory.path, "/Users/someone/.claude")
        XCTAssertEqual(environment.globalConfigFile.path, "/Users/someone/.claude.json")
        XCTAssertNotNil(environment.managedDirectory)
    }

    func testClaudeConfigDirMovesBothLocations() {
        let environment = ScanEnvironment.current(environment: ["CLAUDE_CONFIG_DIR": "/opt/claude-config"], home: home)
        XCTAssertEqual(environment.claudeDirectory.path, "/opt/claude-config")
        XCTAssertEqual(environment.globalConfigFile.path, "/opt/claude-config/.claude.json")
    }

    func testClaudeConfigDirExpandsATilde() {
        let environment = ScanEnvironment.current(environment: ["CLAUDE_CONFIG_DIR": "~/work-claude"], home: home)
        XCTAssertEqual(environment.claudeDirectory.path, "/Users/someone/work-claude")
    }

    func testEmptyClaudeConfigDirIsIgnored() {
        let environment = ScanEnvironment.current(environment: ["CLAUDE_CONFIG_DIR": ""], home: home)
        XCTAssertEqual(environment.claudeDirectory.path, "/Users/someone/.claude")
    }

    func testSearchPathKeepsPathOrderThenAddsStandardFoldersOnce() {
        let environment = ScanEnvironment.current(environment: ["PATH": "/custom/bin:/usr/bin"], home: home)
        let paths = environment.executableSearchPaths.map(\.path)
        XCTAssertEqual(Array(paths.prefix(2)), ["/custom/bin", "/usr/bin"])
        XCTAssertEqual(paths.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/Users/someone/.local/bin"))
    }
}
