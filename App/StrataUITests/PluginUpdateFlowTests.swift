import XCTest

/// A plugin whose cached marketplace offers a newer version shows the update and the command to run.
final class PluginUpdateFlowTests: XCTestCase {
    private var root: URL?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testANewerMarketplaceVersionShowsTheUpdateCommand() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-updates-\(UUID().uuidString)")
        self.root = root
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("code/updates-demo")
        let plugins = home.appendingPathComponent(".claude/plugins")
        let installed = plugins.appendingPathComponent("cache/tools/kit/1.0.0")
        let marketplace = plugins.appendingPathComponent("marketplaces/tools")
        let files: [(URL, String)] = [
            (installed.appendingPathComponent(".claude-plugin/plugin.json"), #"{"name": "kit", "version": "1.0.0"}"#),
            (
                plugins.appendingPathComponent("installed_plugins.json"),
                #"{"version": 2, "plugins": {"kit@tools": [{"scope": "user", "installPath": "\#(installed.path)", "version": "1.0.0"}]}}"#
            ),
            (
                plugins.appendingPathComponent("known_marketplaces.json"),
                #"{"tools": {"source": {"source": "github", "repo": "acme/tools"}, "installLocation": "\#(marketplace.path)"}}"#
            ),
            (marketplace.appendingPathComponent(".claude-plugin/marketplace.json"), #"{"name": "tools", "plugins": [{"name": "kit", "source": "./plugins/kit"}]}"#),
            (marketplace.appendingPathComponent("plugins/kit/.claude-plugin/plugin.json"), #"{"name": "kit", "version": "1.2.0"}"#),
            (home.appendingPathComponent(".claude/settings.json"), #"{"enabledPlugins": {"kit@tools": true}}"#),
            (repository.appendingPathComponent("README.md"), "# Demo\n"),
        ]
        for (url, contents) in files {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }

        let app = XCUIApplication()
        app.launchArguments = ["-StrataUITesting"]
        app.launchEnvironment = [
            "STRATA_UITEST_REPOSITORY": repository.path,
            "STRATA_UITEST_HOME": home.path,
        ]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "itemRow.plugin.user.kit@tools").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The plugin isn't listed")
        row.click()

        let status = app.descendants(matching: .any).matching(identifier: "pluginUpdateStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), "The inspector doesn't show the plugin's update status")
        XCTAssertTrue(status.label.contains("update is available"), "Status was: \(status.label)")
        // macOS puts a static text's string in its value; only text values are strings.
        let command = "claude plugin update kit@tools --scope user"
        let byLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", command)).firstMatch
        let byValue = app.staticTexts.matching(NSPredicate(format: "value == %@", command)).firstMatch
        XCTAssertTrue(byLabel.exists || byValue.exists, "The update command isn't shown")
    }
}
