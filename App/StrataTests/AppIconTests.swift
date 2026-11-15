import AppKit
import XCTest

final class AppIconTests: XCTestCase {
    func testAppDeclaresAndBundlesItsIcon() throws {
        let app = Bundle.main
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")

        let icon = try XCTUnwrap(app.image(forResource: "AppIcon"), "AppIcon.icns is missing from the app's resources")
        XCTAssertEqual(icon.representations.map(\.pixelsWide).max(), 1024)
    }
}
