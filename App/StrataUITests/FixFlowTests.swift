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

    func testUninstallingTheCopyThatRunsFromTheListCanBeUndone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-uninstall-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/uninstall-demo")
        let personal = home.appendingPathComponent(".claude/skills/deploy/SKILL.md")
        let repoCopy = repository.appendingPathComponent(".claude/skills/deploy/SKILL.md")
        for file in [personal, repoCopy] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try Data("---\ndescription: Personal deploy\n---\n".utf8).write(to: personal)
        try Data("---\ndescription: Repo deploy\n---\n".utf8).write(to: repoCopy)

        let app = XCUIApplication()
        app.launchArguments = ["-allowsFixes", "YES", "-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": repository.path,
            "STRATA_UITEST_HOME": home.path,
        ]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "itemRow.skill.user.deploy").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The personal skill isn't listed")
        row.rightClick()
        let uninstall = app.menuItems["Uninstall…"]
        XCTAssertTrue(uninstall.waitForExistence(timeout: 5), "The list's context menu doesn't offer Uninstall")
        uninstall.click()

        let confirm = app.buttons["confirmFixButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The uninstall review didn't open")
        // macOS puts a static text's string in its value; other elements use the label. Only text values are strings.
        let phrase = "the repo copy runs instead"
        let byLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch
        let byValue = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", phrase)).firstMatch
        XCTAssertTrue(byLabel.exists || byValue.exists, "The review should say the repository copy takes over")
        XCTAssertTrue(FileManager.default.fileExists(atPath: personal.path), "Nothing changes before confirming")
        confirm.click()

        let undo = app.buttons["undoFixButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "The uninstall didn't report success")
        XCTAssertFalse(FileManager.default.fileExists(atPath: personal.path), "The personal skill should be in backups")

        undo.click()
        let restored = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: personal.path) }, evaluatedWith: nil)
        wait(for: [restored], timeout: 10)
        app.buttons["fixDoneButton"].click()
    }

    func testDisablingAPluginEditsOnlyItsEntryAndCanBeUndone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-plugin-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/plugin-demo")
        let claude = home.appendingPathComponent(".claude")
        let pluginRoot = claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0")
        let files: [(URL, String)] = [
            (pluginRoot.appendingPathComponent(".claude-plugin/plugin.json"), #"{"name": "kit", "version": "1.0.0"}"#),
            (pluginRoot.appendingPathComponent("skills/migrate/SKILL.md"), "---\ndescription: Migrate\n---\n"),
            (
                claude.appendingPathComponent("plugins/installed_plugins.json"),
                #"{"version": 2, "plugins": {"kit@tools": [{"scope": "user", "installPath": "\#(pluginRoot.path)", "version": "1.0.0"}]}}"#
            ),
            (claude.appendingPathComponent("settings.json"), "{\n  \"model\": \"opus\",\n  \"enabledPlugins\": {\n    \"kit@tools\": true\n  }\n}\n"),
            (repository.appendingPathComponent("README.md"), "# Demo\n"),
        ]
        for (url, contents) in files {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        let settings = claude.appendingPathComponent("settings.json")
        let original = try String(contentsOf: settings, encoding: .utf8)

        let app = XCUIApplication()
        app.launchArguments = ["-allowsFixes", "YES", "-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": repository.path,
            "STRATA_UITEST_HOME": home.path,
        ]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "itemRow.plugin.user.kit@tools").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The plugin isn't listed")
        row.click()
        let disable = app.buttons["fix.disablePlugin"]
        XCTAssertTrue(disable.waitForExistence(timeout: 10), "The inspector doesn't offer Disable")
        disable.click()
        let confirm = app.buttons["confirmFixButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The review didn't open")
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), original, "Nothing changes before confirming")
        confirm.click()

        let undo = app.buttons["undoFixButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "Disabling didn't report success")
        XCTAssertEqual(
            try String(contentsOf: settings, encoding: .utf8),
            original.replacingOccurrences(of: "\"kit@tools\": true", with: "\"kit@tools\": false"),
            "Only the plugin's entry changes"
        )

        undo.click()
        let restored = expectation(
            for: NSPredicate { _, _ in (try? String(contentsOf: settings, encoding: .utf8)) == original },
            evaluatedWith: nil
        )
        wait(for: [restored], timeout: 10)
        app.buttons["fixDoneButton"].click()
    }
}
