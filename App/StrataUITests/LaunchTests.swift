import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsEmptyStateWithAddAction() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["No Repositories"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["addRepositoryButton"].exists)
    }
}
