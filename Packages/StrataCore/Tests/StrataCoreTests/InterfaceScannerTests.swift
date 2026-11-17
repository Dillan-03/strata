@testable import StrataCore
import XCTest

/// Output styles, the status line, keybindings, and plugin LSP servers and monitors.
final class InterfaceScannerTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private func items(_ kind: ItemKind, _ report: InspectionReport? = nil) -> [ConfigItem] {
        (report ?? fixture.inspect()).items.filter { $0.kind == kind }
    }

    private func style(_ name: String, description: String = "A style", extra: String = "") -> String {
        "---\nname: \(name)\ndescription: \(description)\n\(extra)---\nRespond like this.\n"
    }

    @discardableResult
    private func installPlugin(enabled: Bool = true, manifestExtra: [String: Any] = [:]) throws -> URL {
        let root = fixture.claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0")
        try fixture.json(".claude-plugin/plugin.json", in: root, ["name": "kit", "version": "1.0.0"].merging(manifestExtra) { $1 })
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": 2,
            "plugins": ["kit@tools": [["scope": "user", "installPath": root.path, "version": "1.0.0"]]],
        ])
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": enabled]])
        return root
    }

    // MARK: - Output styles

    func testTheSelectedStyleAppliesAndOthersAreAvailable() throws {
        try fixture.write("output-styles/terse.md", in: fixture.claude, style("Terse"))
        try fixture.write(".claude/output-styles/teaching.md", in: fixture.repository, style("Teaching"))
        try fixture.json(".claude/settings.json", in: fixture.repository, ["outputStyle": "Teaching"])
        let styles = items(.outputStyle)
        XCTAssertEqual(styles.first { $0.name == "Teaching" }?.applicability, .effective)
        XCTAssertEqual(styles.first { $0.name == "Terse" }?.applicability, .inactive)

        try fixture.json(".claude/settings.json", in: fixture.repository, ["outputStyle": "Explanatory"])
        XCTAssertTrue(items(.outputStyle).allSatisfy { $0.applicability == .inactive }, "A built-in style is selected, so no custom one applies")
    }

    func testAStyleNameIsCaseSensitive() throws {
        try fixture.json("settings.json", in: fixture.claude, ["outputStyle": "explanatory"])
        let report = fixture.inspect()
        XCTAssertTrue(report.diagnostics.contains { $0.code == .unknownOutputStyle }, "A mismatched name silently gives the Default style")
    }

    func testStylesWithTheSameNameInDifferentFoldersAreUnknown() throws {
        try fixture.write("output-styles/review.md", in: fixture.claude, style("Review"))
        try fixture.write(".claude/output-styles/review.md", in: fixture.repository, style("Review"))
        XCTAssertTrue(items(.outputStyle).allSatisfy { $0.applicability == .unknown }, "The docs don't say which folder wins")
    }

    func testAForcedPluginStyleOverridesTheSetting() throws {
        let root = try installPlugin()
        try fixture.write("output-styles/brand.md", in: root, style("Brand", extra: "force-for-plugin: true\n"))
        try fixture.write("output-styles/terse.md", in: fixture.claude, style("Terse"))
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": true], "outputStyle": "Terse"])
        let styles = items(.outputStyle)
        XCTAssertEqual(styles.first { $0.name == "Brand" }?.applicability, .effective)
        XCTAssertEqual(styles.first { $0.name == "Terse" }?.applicability, .inactive)
    }

    // MARK: - Status line

    func testTheHighestStatusLineWinsAndWaitsForTrust() throws {
        try fixture.json("settings.json", in: fixture.claude, ["statusLine": ["type": "command", "command": "~/.claude/line.sh"]])
        try fixture.json(".claude/settings.json", in: fixture.repository, ["statusLine": ["type": "command", "command": "./line.sh --token=ghp_SECRETSECRETSECRETSECRET"]])
        let lines = items(.statusLine)
        let project = try XCTUnwrap(lines.first { $0.scope == .project })
        XCTAssertEqual(project.applicability, .conditional, "The status line stays blank until the folder is trusted")
        XCTAssertEqual(lines.first { $0.scope == .user }?.applicability, .shadowed(by: project.id))
        XCTAssertFalse(project.summary?.contains("SECRETSECRET") ?? true)
    }

    func testDisableAllHooksLeavesOnlyAManagedStatusLine() throws {
        try fixture.json("managed-settings.json", in: try XCTUnwrap(fixture.environment.managedDirectory), ["statusLine": ["type": "command", "command": "org-line"]])
        try fixture.json("settings.json", in: fixture.claude, ["statusLine": ["type": "command", "command": "mine"], "disableAllHooks": true])
        let lines = items(.statusLine)
        XCTAssertEqual(lines.first { $0.scope == .user }?.applicability, .inactive)
        XCTAssertEqual(lines.first { $0.scope == .managed }?.applicability, .conditional)
    }

    // MARK: - Keybindings

    func testKeybindingsListEachBindingAndRefuseReservedKeys() throws {
        try fixture.json("keybindings.json", in: fixture.claude, ["bindings": [
            ["context": "Chat", "bindings": ["ctrl+e": "chat:externalEditor", "ctrl+s": NSNull(), "ctrl+c": "chat:submit"]],
        ]])
        let bindings = items(.keybinding)
        XCTAssertEqual(Set(bindings.map(\.name)), ["Chat: ctrl+e", "Chat: ctrl+s", "Chat: ctrl+c"])
        XCTAssertEqual(bindings.first { $0.name == "Chat: ctrl+e" }?.applicability, .effective)
        XCTAssertEqual(bindings.first { $0.name == "Chat: ctrl+s" }?.summary, "Unbinds the default shortcut")
        XCTAssertEqual(bindings.first { $0.name == "Chat: ctrl+c" }?.applicability, .invalid, "Ctrl+C is reserved")
    }

    // MARK: - Plugin LSP servers and monitors

    func testPluginLSPServersLaterConfigsReplaceEarlierOnes() throws {
        let root = try installPlugin(manifestExtra: ["lspServers": ["go": ["command": "gopls-nightly", "extensionToLanguage": [".go": "go"]]]])
        try fixture.json(".lsp.json", in: root, [
            "go": ["command": "gopls", "args": ["serve"], "extensionToLanguage": [".go": "go"]],
            "ts": ["command": "tsserver", "extensionToLanguage": [".ts": "typescript"]],
        ])
        let servers = items(.lspServer)
        let manifestGo = try XCTUnwrap(servers.first { $0.name == "go" && $0.summary == "gopls-nightly" })
        XCTAssertEqual(manifestGo.applicability, .effective)
        XCTAssertEqual(servers.first { $0.name == "go" && $0.summary == "gopls serve" }?.applicability, .shadowed(by: manifestGo.id))
        XCTAssertEqual(servers.first { $0.name == "ts" }?.metadataValue("File types"), ".ts")
    }

    func testMonitorsAndADisabledPluginsComponents() throws {
        let root = try installPlugin(enabled: false)
        try fixture.json("monitors/monitors.json", in: root, ["monitors": [
            ["name": "build-watch", "command": "npm run watch", "description": "Watches the build"],
            ["name": "deploy-tail", "command": "tail -f deploy.log", "description": "Tails deploys", "when": "on-skill-invoke:deploy"],
        ]])
        var monitors = items(.monitor)
        XCTAssertEqual(monitors.count, 2)
        XCTAssertTrue(monitors.allSatisfy { $0.applicability == .inactive }, "A turned-off plugin's monitors don't run")

        try installPlugin(enabled: true)
        monitors = items(.monitor)
        XCTAssertEqual(monitors.first { $0.name == "deploy-tail" }?.metadataValue("Starts"), "The first time /deploy runs")
        XCTAssertEqual(monitors.first { $0.name == "build-watch" }?.applicability, .effective)
    }
}
