import XCTest

final class SettingsWindowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSettingsFitsOnTheScreenAndScrollsToTheEnd() {
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["No Repositories"].waitForExistence(timeout: 15))

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(NSPredicate(format: "identifier == %@", "appearancePicker")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        let screenHeight = XCUIScreen.main.screenshot().image.size.height
        XCTAssertLessThanOrEqual(settings.frame.maxY, screenHeight, "Settings \(settings.frame) runs off a \(screenHeight)-point screen")

        // The last section is inside the scroll view, so scrolling reaches it.
        let start = "Strata only reads files"
        let privacy = settings.scrollViews.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", start, start)).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "The Privacy section isn't in Settings' scroll view")
    }
}
