import XCTest

final class ToolbarLayoutTests: XCTestCase {
    private var fixture: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let fixture { try? FileManager.default.removeItem(at: fixture) }
    }

    func testTheCategoryPickerDoesntCoverTheFilterButtonAtMinimumWidth() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("strata-ui-\(UUID().uuidString)/demo-repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fixture = folder.deletingLastPathComponent()

        let app = XCUIApplication()
        app.launchEnvironment = ["STRATA_UITEST_REPOSITORY": folder.path]
        app.launchArguments = ["-StrataUITesting"]
        app.launch()

        let picker = app.descendants(matching: .any).matching(identifier: "categoryPicker").firstMatch
        let filter = app.descendants(matching: .any).matching(identifier: "filterMenu").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        let window = app.windows.containing(NSPredicate(format: "identifier == %@", "categoryPicker")).firstMatch

        // Drag the left edge as far right as it goes: the window stops at its 960-point minimum width.
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 1, dy: 0))
        edge.click(forDuration: 0.3, thenDragTo: edge.withOffset(CGVector(dx: 400, dy: 0)))
        XCTAssertLessThan(window.frame.width, 1000, "The window didn't narrow, so this test checks nothing")

        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        XCTAssertFalse(picker.frame.intersects(filter.frame), "Picker \(picker.frame) overlaps Filter \(filter.frame)")
    }
}
