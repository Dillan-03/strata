import XCTest

final class LaunchTests: XCTestCase {
    private var fixture: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let fixture { try? FileManager.default.removeItem(at: fixture) }
    }

    func testLaunchShowsEmptyStateWithAddAction() {
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["No Repositories"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["addRepositoryButton"].exists)
    }

    func testLaunchWithARepositoryShowsItInTheSidebar() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("strata-ui-\(UUID().uuidString)/demo-repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fixture = folder.deletingLastPathComponent()

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = ["STRATA_UITEST_REPOSITORY": folder.path]
        app.launch()

        XCTAssertTrue(app.outlines.staticTexts["demo-repo"].waitForExistence(timeout: 15) || app.staticTexts["demo-repo"].waitForExistence(timeout: 5))
    }

    func testFirstLaunchSuggestsFoldersFromClaudeCodesProjectList() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-suggest-\(UUID().uuidString)")
        fixture = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/suggested-repo")
        let skill = repository.appendingPathComponent(".claude/skills/deploy/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\ndescription: Deploy\n---\n".utf8).write(to: skill)
        let personal = home.appendingPathComponent(".claude/skills/tidy/SKILL.md")
        try FileManager.default.createDirectory(at: personal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\ndescription: Tidy\n---\n".utf8).write(to: personal)
        let projects = [repository.path: [String: String](), home.appendingPathComponent("code/gone-repo").path: [:]]
        try JSONSerialization.data(withJSONObject: ["projects": projects]).write(to: home.appendingPathComponent(".claude.json"))

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = ["STRATA_UITEST_HOME": home.path]
        app.launch()

        let add = app.buttons["suggestedRepository.suggested-repo"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), "The empty state doesn't suggest the project folder")
        XCTAssertFalse(app.buttons["suggestedRepository.gone-repo"].exists, "A folder that no longer exists is suggested")
        add.click()

        let row = app.descendants(matching: .any).matching(identifier: "itemRow.skill.project.deploy").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Adding the suggestion didn't scan it")

        let personalRow = app.descendants(matching: .any).matching(identifier: "itemRow.skill.user.tidy").firstMatch
        XCTAssertFalse(personalRow.exists, "A newly added repository shows personal items before its own are filtered")
        app.buttons["filterChip.clear"].click()
        XCTAssertTrue(personalRow.waitForExistence(timeout: 5), "Clearing the filter doesn't bring back personal items")
    }
}
