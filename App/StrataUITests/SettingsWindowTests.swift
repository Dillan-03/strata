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

        // The last section is reachable by scrolling. Rows off screen may not exist until then.
        settings.scroll(byDeltaX: 0, deltaY: -2000)
        let start = "Strata only reads files"
        let privacy = settings.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", start, start)).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "Scrolling to the end doesn't reach the Privacy section")
        XCTAssertTrue(privacy.isHittable, "The Privacy section is still off screen after scrolling to the end")
    }
}
