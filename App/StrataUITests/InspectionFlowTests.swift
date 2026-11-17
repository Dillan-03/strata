import XCTest

/// Walks the main flow against a fixture: a personal skill hiding a repo skill.
final class InspectionFlowTests: XCTestCase {
    private var root: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func makeFixture() throws -> (home: URL, repository: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-flow-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/flow-demo")
        for (base, description) in [(home, "Personal deploy"), (repository, "Repo deploy")] {
            let skill = base.appendingPathComponent(".claude/skills/deploy/SKILL.md")
            try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("---\ndescription: \(description)\n---\n".utf8).write(to: skill)
        }
        return (home, repository)
    }

    func testIssueLeadsToTheOverriddenSkill() throws {
        let fixture = try makeFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        let summary = app.buttons["issuesSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), "Expected the issue summary after scanning")
        summary.click()

        let issue = app.staticTexts["Global skill deploy hides the repo copy"]
        XCTAssertTrue(issue.waitForExistence(timeout: 10))

        // Link-style buttons aren't reported as buttons on macOS, so match any element type by identifier.
        let showRepoCopy = app.descendants(matching: .any).matching(identifier: "showItem.project.deploy").firstMatch
        XCTAssertTrue(showRepoCopy.waitForExistence(timeout: 5))
        showRepoCopy.click()

        XCTAssertTrue(app.staticTexts["Which Copy Runs"].waitForExistence(timeout: 10))
    }

    func testCategoryPickerSwitchesToSkills() throws {
        let fixture = try makeFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        app.typeKey("2", modifierFlags: .command)

        let skillsSection = app.staticTexts["Skills (2)"]
        XCTAssertTrue(skillsSection.waitForExistence(timeout: 10))
    }

    func testFilterChipFiltersTheListAndTicksTheMenu() throws {
        let fixture = try makeFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Skills (2)"].waitForExistence(timeout: 10))

        let overridden = app.descendants(matching: .any).matching(identifier: "filterChip.status.overridden").firstMatch
        XCTAssertTrue(overridden.waitForExistence(timeout: 5))
        overridden.click()
        XCTAssertTrue(app.staticTexts["Skills (1)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "filterChip.clear").firstMatch.exists)

        // XCUITest can't read a menu item's tick, so prove it's shared: choosing Overridden in the menu turns it off.
        let filterMenu = app.descendants(matching: .any).matching(identifier: "filterMenu").firstMatch
        if filterMenu.exists {
            filterMenu.click()
        } else {
            // CI's screen is narrow enough that the toolbar moves Filter into its overflow menu, as a submenu.
            let toolbar = app.toolbars.firstMatch
            let overflow = toolbar.descendants(matching: .any).matching(
                NSPredicate(format: "identifier CONTAINS[c] 'clipped' OR identifier CONTAINS[c] 'overflow' OR label CONTAINS[c] 'more'")
            ).firstMatch
            XCTAssertTrue(overflow.exists, "No Filter menu or overflow button in the toolbar:\n\(toolbar.debugDescription)")
            overflow.click()
            let filterItem = app.menuItems["Filter"]
            XCTAssertTrue(filterItem.waitForExistence(timeout: 5), "No Filter in the overflow menu:\n\(app.menus.firstMatch.debugDescription)")
            filterItem.hover()
        }
        let menuItem = app.menuItems["Overridden"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5))
        menuItem.click()
        XCTAssertTrue(app.staticTexts["Skills (2)"].waitForExistence(timeout: 5), "Expected the menu to show Overridden ticked and turn it off")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "filterChip.clear").firstMatch.exists)
    }

    func testHooksCategoryListsAHookWithItsCommand() throws {
        let fixture = try makeFixture()
        let settings = fixture.repository.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let hooks = #"{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "./audit.sh"}]}]}}"#
        try Data(hooks.utf8).write(to: settings)

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Hooks (1)"].waitForExistence(timeout: 10), "The Hooks category doesn't list the hook")
        let row = app.descendants(matching: .any).matching(identifier: "itemRow.hook.project.PreToolUse: Bash").firstMatch
        XCTAssertTrue(row.exists)
    }

    func testReportingAWrongResultShowsTheTextFirst() throws {
        let fixture = try makeFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "itemRow.skill.project.deploy").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.rightClick()
        let report = app.menuItems["Report a Wrong Result…"]
        XCTAssertTrue(report.waitForExistence(timeout: 5), "The context menu doesn't offer Report a Wrong Result")
        report.click()

        XCTAssertTrue(app.buttons["openWrongResultReport"].waitForExistence(timeout: 10), "The report isn't shown before opening")
        let body = app.descendants(matching: .any).matching(identifier: "wrongResultBody").firstMatch
        XCTAssertTrue(body.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fixture.home.path)).firstMatch.exists,
                       "The home folder path shouldn't appear")
        app.buttons["Cancel"].click()
    }

    func testSettingsListsPermissionRulesAsTheirOwnItems() throws {
        let fixture = try makeFixture()
        let settings = fixture.repository.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"permissions": {"deny": ["Read(./.env)"], "ask": ["Bash(git push:*)"]}}"#.utf8).write(to: settings)

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        app.typeKey("8", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Permission Rules (2)"].waitForExistence(timeout: 10), "Settings doesn't list the permission rules")
        let deny = app.descendants(matching: .any).matching(identifier: "itemRow.permission.project.Read(./.env)").firstMatch
        XCTAssertTrue(deny.exists)
    }

    func testTheContextEstimateOpensWithItsBreakdown() throws {
        let fixture = try makeFixture()
        try Data("# Flow demo\nAlways run the tests.\n".utf8).write(to: fixture.repository.appendingPathComponent("CLAUDE.md"))
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        let button = app.descendants(matching: .any).matching(identifier: "contextEstimateButton").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "The summary bar doesn't show the estimate")
        button.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "contextEstimateTotal").firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].click()
    }

    func testSettingsListsKeybindingsAndOutputStyles() throws {
        let fixture = try makeFixture()
        let claude = fixture.home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("output-styles"), withIntermediateDirectories: true)
        try Data(#"{"bindings": [{"context": "Chat", "bindings": {"ctrl+e": "chat:externalEditor"}}]}"#.utf8).write(to: claude.appendingPathComponent("keybindings.json"))
        try Data("---\nname: Terse\ndescription: Short answers\n---\nBe brief.\n".utf8).write(to: claude.appendingPathComponent("output-styles/terse.md"))

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        app.typeKey("8", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Keybindings (1)"].waitForExistence(timeout: 10), "Settings doesn't list the keybinding")
        XCTAssertTrue(app.staticTexts["Output Styles (1)"].exists, "Settings doesn't list the output style")
    }

    func testExportReportOpensFromTheInspectMenu() throws {
        let fixture = try makeFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": fixture.repository.path,
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["saveReportButton"].waitForExistence(timeout: 10), "Export Report didn't open")
        app.buttons["Cancel"].click()
    }

    func testSearchingAllRepositoriesFindsAnItemInAnother() throws {
        let fixture = try makeFixture()
        let other = fixture.home.appendingPathComponent("code/other-repo")
        let skill = other.appendingPathComponent(".claude/skills/lint/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\ndescription: Lint the other repo\n---\n".utf8).write(to: skill)

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": "\(fixture.repository.path):\(other.path)",
            "STRATA_UITEST_HOME": fixture.home.path,
        ]
        app.launch()

        XCTAssertTrue(app.buttons["issuesSummary"].waitForExistence(timeout: 20))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("lint")
        let scope = app.descendants(matching: .any).matching(identifier: "searchScopePicker").firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 5), "No search scope picker appears while searching")
        let allScope = scope.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR title == %@", "All Repositories", "All Repositories")).firstMatch
        XCTAssertTrue(allScope.exists, "The scope picker doesn't offer All Repositories:\n\(scope.debugDescription)")
        allScope.click()

        let result = app.descendants(matching: .any).matching(identifier: "searchResult.skill.project.lint").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "The other repository's skill isn't found")
        result.click()
        let row = app.descendants(matching: .any).matching(identifier: "itemRow.skill.project.lint").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Opening the result doesn't show it in its repository")
    }
}
