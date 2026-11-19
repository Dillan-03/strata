import XCTest

/// Checks the pixels, not a stored value: a window counts as dark when its average brightness is under half.
final class AppearanceFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheStoredAppearanceAppliesAtLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting", "-appearance", "dark"]
        app.launch()

        let main = mainWindow(of: app)
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { isDark(main) }, "Strata didn't open dark")

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(segment("Dark", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(segment("Dark", in: app).isSelected, "Settings doesn't show the stored choice")
    }

    func testPickingAnAppearanceChangesEveryWindowAtOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launch()

        let main = mainWindow(of: app)
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        let systemIsDark = isDark(main)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(NSPredicate(format: "identifier == %@", "appearancePicker")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(segment("System", in: app).isSelected, "System should be the default")

        segment("Dark", in: app).click()
        XCTAssertTrue(waitUntil { isDark(main) && isDark(settings) }, "Picking Dark didn't darken both windows")
        keep(settings, named: "Settings, Dark")

        segment("Light", in: app).click()
        XCTAssertTrue(waitUntil { !isDark(main) && !isDark(settings) }, "Picking Light didn't lighten both windows")
        keep(settings, named: "Settings, Light")

        segment("System", in: app).click()
        XCTAssertTrue(waitUntil { isDark(main) == systemIsDark }, "Picking System didn't go back to the macOS appearance")
    }

    private func mainWindow(of app: XCUIApplication) -> XCUIElement {
        app.windows.containing(NSPredicate(format: "label == %@ OR value == %@", "No Repositories", "No Repositories")).firstMatch
    }

    private func segment(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "appearancePicker").firstMatch
            .descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Saved in the result bundle, so a reviewer can see both looks without running the app.
    private func keep(_ window: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date.now < deadline
        return false
    }

    private func isDark(_ window: XCUIElement) -> Bool {
        let image = window.screenshot().image
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return false }
        // Scaling the window down to 16 × 16 averages its pixels.
        let side = 16
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let total = (0..<(side * side)).reduce(0) { sum, pixel in
            sum + Int(pixels[pixel * 4]) + Int(pixels[pixel * 4 + 1]) + Int(pixels[pixel * 4 + 2])
        }
        return Double(total) / Double(side * side * 3 * 255) < 0.5
    }
}
