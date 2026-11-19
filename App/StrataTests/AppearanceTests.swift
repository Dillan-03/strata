import AppKit
@testable import Strata
import XCTest

final class AppearanceTests: XCTestCase {
    func testEachOptionMapsToItsAppearance() {
        XCTAssertNil(Appearance.system.appearanceName, "System must leave the appearance to macOS")
        XCTAssertEqual(Appearance.light.appearanceName, .aqua)
        XCTAssertEqual(Appearance.dark.appearanceName, .darkAqua)
        XCTAssertEqual(Appearance.allCases.map(\.title), ["System", "Light", "Dark"])
    }
}
