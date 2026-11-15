import XCTest

/// Edits a global skill outside the app, then reviews the change: banner, sheet, diff, and marking it reviewed.
final class ChangeReviewFlowTests: XCTestCase {
    private var root: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testEditedSkillCanBeReviewedAndMarkedReviewed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-review-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/review-demo")
        let skill = home.appendingPathComponent(".claude/skills/deploy/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Data("---\ndescription: Deploy anything\n---\nRun the checks first.\n".utf8).write(to: skill)

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": repository.path,
            "STRATA_UITEST_HOME": home.path,
        ]
        app.launch()
        let skillRow = app.descendants(matching: .any).matching(identifier: "itemRow.skill.user.deploy").firstMatch
        XCTAssertTrue(skillRow.waitForExistence(timeout: 20), "Expected the first scan to list the global skill")

        try Data("---\ndescription: Deploy, then smoke test\n---\nRun the checks first.\n".utf8).write(to: skill)
        app.typeKey("r", modifierFlags: .command)

        let review = app.buttons["reviewChangesButton"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), "The change banner didn't appear after the edit")
        review.click()

        let added = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "description: Deploy, then smoke test")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "The diff doesn't show the new line")
        let removed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "description: Deploy anything")).firstMatch
        XCTAssertTrue(removed.exists, "The diff doesn't show the old line")

        app.buttons["markReviewedButton"].click()
        XCTAssertTrue(review.waitForNonExistence(timeout: 10), "The banner should go once changes are reviewed")
    }
}
