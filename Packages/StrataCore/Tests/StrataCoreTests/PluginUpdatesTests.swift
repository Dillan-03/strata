@testable import StrataCore
import XCTest

/// Installed and offered plugin versions, read from disk with no network.
final class PluginUpdatesTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private var marketplace: URL { fixture.claude.appendingPathComponent("plugins/marketplaces/tools") }

    /// `kit@tools` installed at 1.0.0, from a marketplace whose cached copy has `listing` as its plugins.
    private func install(installed: String = "1.0.0", listing: [[String: Any]]?, known: Bool = true) throws -> ConfigItem {
        let root = fixture.claude.appendingPathComponent("plugins/cache/tools/kit/\(installed)")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit", "version": installed])
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": 2,
            "plugins": ["kit@tools": [["scope": "project", "installPath": root.path, "version": installed]]],
        ])
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": true]])
        if known {
            try fixture.json("plugins/known_marketplaces.json", in: fixture.claude, [
                "tools": ["source": ["source": "github", "repo": "acme/tools"], "installLocation": marketplace.path],
            ])
        }
        if let listing {
            try fixture.json(".claude-plugin/marketplace.json", in: marketplace, ["name": "tools", "plugins": listing])
        }
        return try XCTUnwrap(fixture.inspect().items.first { $0.kind == .plugin })
    }

    private func check(_ plugin: ConfigItem) throws -> PluginUpdate {
        try XCTUnwrap(PluginUpdates.check(plugin, environment: fixture.environment))
    }

    func testAManifestInTheMarketplaceCopyOffersANewerVersion() throws {
        try fixture.json(".claude-plugin/plugin.json", in: marketplace.appendingPathComponent("plugins/kit"), ["name": "kit", "version": "1.2.0"])
        let update = try check(try install(listing: [["name": "kit", "source": "./plugins/kit", "version": "1.1.0"]]))
        XCTAssertEqual(update.latest, "1.2.0", "The plugin's own manifest wins over the marketplace entry")
        XCTAssertEqual(update.installed, "1.0.0")
        XCTAssertEqual(update.status, .available)
        XCTAssertEqual(update.command, "claude plugin update kit@tools --scope project")
    }

    func testTheEntryVersionIsUsedForARemoteSource() throws {
        let update = try check(try install(installed: "2.0.0", listing: [["name": "kit", "source": ["source": "github", "repo": "acme/kit"], "version": "2.0.0"]]))
        XCTAssertEqual(update.status, .upToDate)
    }

    func testAnOlderMarketplaceVersionIsNotAnUpdate() throws {
        let update = try check(try install(installed: "1.10.0", listing: [["name": "kit", "source": ["source": "github", "repo": "acme/kit"], "version": "1.9.0"]]))
        XCTAssertEqual(update.status, .upToDate, "1.10.0 is newer than 1.9.0 by Semantic Versioning, not by text")
    }

    func testCommitHashesThatDifferCountAsAnUpdate() {
        XCTAssertTrue(PluginUpdates.isNewer("a1b2c3d4e5f6", than: "0f9e8d7c6b5a"))
        XCTAssertFalse(PluginUpdates.isNewer("a1b2c3d4e5f6", than: "a1b2c3d4e5f6"))
    }

    func testWhatStrataCantTellIsSaid() throws {
        struct Case {
            let listing: [[String: Any]]?
            let known: Bool
            let phrase: String
        }
        let cases = [
            Case(listing: nil, known: false, phrase: "no record of the tools marketplace"),
            Case(listing: nil, known: true, phrase: "no local copy"),
            Case(listing: [["name": "other"]], known: true, phrase: "no longer lists kit"),
            Case(listing: [["name": "kit", "source": ["source": "github", "repo": "acme/kit"]]], known: true, phrase: "doesn't state a version"),
            Case(listing: [["name": "kit", "source": "../../../outside"]], known: true, phrase: "points outside the marketplace"),
        ]
        for testCase in cases {
            let (listing, known, phrase) = (testCase.listing, testCase.known, testCase.phrase)
            fixture = try Fixture()
            guard case .unknown(let reason) = try check(try install(listing: listing, known: known)).status else {
                return XCTFail("Expected unknown for \(phrase)")
            }
            XCTAssertTrue(reason.contains(phrase), reason)
        }
    }

    func testMarketplacesListTheirSources() throws {
        _ = try install(listing: [])
        XCTAssertEqual(PluginUpdates.marketplaces(environment: fixture.environment).map(\.source), ["acme/tools"])
    }
}
