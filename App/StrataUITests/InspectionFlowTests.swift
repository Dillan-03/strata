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

        let showRepoCopy = app.buttons["Show /deploy (Repo)"]
        XCTAssertTrue(showRepoCopy.waitForExistence(timeout: 5))
        showRepoCopy.click()

        XCTAssertTrue(app.staticTexts["Overridden By"].waitForExistence(timeout: 10))
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
}
