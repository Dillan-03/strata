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
}
