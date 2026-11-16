import XCTest

/// Removes an overridden repository skill through the fix review screen, then undoes it.
final class FixFlowTests: XCTestCase {
    private var root: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testRemovingAnOverriddenCopyCanBeUndone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-fix-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/fix-demo")
        let personal = home.appendingPathComponent(".claude/skills/deploy/SKILL.md")
        let repoCopy = repository.appendingPathComponent(".claude/skills/deploy/SKILL.md")
        for file in [personal, repoCopy] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try Data("---\ndescription: Personal deploy\n---\n".utf8).write(to: personal)
        try Data("---\ndescription: Repo deploy\n---\n".utf8).write(to: repoCopy)

        let app = XCUIApplication()
        // Fixes are off by default; the argument domain turns them on for this run only. The `-key value` pair goes
        // first: after a bare flag, macOS reads the key as the flag's value and the stray YES as a file to open,
        // and an app asked to open a file skips its default window.
        app.launchArguments = ["-allowsFixes", "YES", "-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": repository.path,
            "STRATA_UITEST_HOME": home.path,
        ]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "itemRow.skill.project.deploy").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The overridden repository skill isn't listed")
        row.click()

        let remove = app.buttons["fix.removeCopy"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "The inspector doesn't offer a fix")
        remove.click()
        let confirm = app.buttons["confirmFixButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The fix review screen didn't open")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoCopy.path), "Nothing changes before confirming")
        confirm.click()

        let undo = app.buttons["undoFixButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "The fix didn't report success")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoCopy.path), "The repository copy should be in backups")
        let backups = home.appendingPathComponent("Library/Application Support/Strata/Backups")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 1, "One backup per fix")

        undo.click()
        let restored = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: repoCopy.path) }, evaluatedWith: nil)
        wait(for: [restored], timeout: 10)
        XCTAssertEqual(try String(contentsOf: repoCopy, encoding: .utf8), "---\ndescription: Repo deploy\n---\n")
        app.buttons["fixDoneButton"].click()
    }
}
