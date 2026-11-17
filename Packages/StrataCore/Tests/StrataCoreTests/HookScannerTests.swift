@testable import StrataCore
import XCTest

/// Hooks as items: where they come from, which run, and what turns them off.
final class HookScannerTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private func hooks(_ events: [String: Any]) -> [String: Any] { ["hooks": events] }

    private func command(_ command: String, matcher: String? = nil, timeout: Int? = nil) -> [[String: Any]] {
        var handler: [String: Any] = ["type": "command", "command": command]
        if let timeout { handler["timeout"] = timeout }
        var group: [String: Any] = ["hooks": [handler]]
        if let matcher { group["matcher"] = matcher }
        return [group]
    }

    private func hookItems(_ report: InspectionReport? = nil) -> [ConfigItem] {
        (report ?? fixture.inspect()).items.filter { $0.kind == .hook }
    }

    private func writeManaged(_ object: [String: Any]) throws {
        try fixture.json("managed-settings.json", in: try XCTUnwrap(fixture.environment.managedDirectory), object)
    }

    @discardableResult
    private func installPlugin(enabled: Bool = true, manifestHooks: Any? = nil, hooksFile: [String: Any]? = nil) throws -> URL {
        let root = fixture.claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0")
        var manifest: [String: Any] = ["name": "kit", "version": "1.0.0"]
        if let manifestHooks { manifest["hooks"] = manifestHooks }
        try fixture.json(".claude-plugin/plugin.json", in: root, manifest)
        if let hooksFile { try fixture.json("hooks/hooks.json", in: root, hooksFile) }
        try fixture.json("plugins/installed_plugins.json", in: fixture.claude, [
            "version": 2,
            "plugins": ["kit@tools": [["scope": "user", "installPath": root.path, "version": "1.0.0"]]],
        ])
        try fixture.json("settings.json", in: fixture.claude, ["enabledPlugins": ["kit@tools": enabled]])
        return root
    }

    func testHooksFromEverySettingsFileAreListedAndWaitForTrust() throws {
        try fixture.json("settings.json", in: fixture.claude, hooks(["Stop": command("say done")]))
        try fixture.json(".claude/settings.json", in: fixture.repository, hooks([
            "PreToolUse": command("./lint.sh", matcher: "Edit|Write", timeout: 30) + command("./audit.sh", matcher: "Edit|Write"),
        ]))
        let items = hookItems()

        XCTAssertEqual(Set(items.map(\.name)), ["Stop", "PreToolUse: Edit|Write"])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, 3, "Two handlers with the same event and matcher are separate items")
        XCTAssertTrue(items.allSatisfy { $0.applicability == .conditional }, "Settings-file hooks wait for workspace trust")
        let lint = try XCTUnwrap(items.first { $0.summary == "./lint.sh" })
        XCTAssertEqual(lint.scope, .project)
        XCTAssertEqual(lint.metadataValue("Event"), "PreToolUse")
        XCTAssertEqual(lint.metadataValue("Matcher"), "Edit|Write")
        XCTAssertEqual(lint.metadataValue("Timeout"), "30 s")
        XCTAssertEqual(items.first { $0.name == "Stop" }?.metadataValue("Matcher"), "Everything (no matcher)")
    }

    func testTheSameHandlerInTwoSettingsFilesRunsOnce() throws {
        try fixture.json("settings.json", in: fixture.claude, hooks(["Stop": command("say done")]))
        try fixture.json(".claude/settings.json", in: fixture.repository, hooks(["Stop": command("say done")]))
        let items = hookItems()
        XCTAssertEqual(items.filter { $0.applicability == .conditional }.map(\.scope), [.project], "The higher-precedence copy counts")
        XCTAssertEqual(items.filter { $0.applicability == .inactive }.map(\.scope), [.user])
    }

    func testDisableAllHooksFollowsPrecedenceAndSparesManagedHooks() throws {
        try writeManaged(hooks(["SessionStart": command("org-check")]))
        try fixture.json("settings.json", in: fixture.claude, hooks(["Stop": command("say done")]))
        try fixture.json(".claude/settings.json", in: fixture.repository, ["disableAllHooks": true])
        var items = hookItems()
        XCTAssertEqual(items.first { $0.scope == .user }?.applicability, .inactive, "A project true turns off user hooks too")
        XCTAssertEqual(items.first { $0.scope == .managed }?.applicability, .conditional, "Only managed settings can turn off managed hooks")

        try fixture.json(".claude/settings.local.json", in: fixture.repository, ["disableAllHooks": false])
        items = hookItems()
        XCTAssertEqual(items.first { $0.scope == .user }?.applicability, .conditional, "Local false wins over project true")

        try writeManaged(hooks(["SessionStart": command("org-check")]).merging(["disableAllHooks": true]) { $1 })
        XCTAssertTrue(hookItems().allSatisfy { $0.applicability == .inactive }, "Managed true turns off every hook")
    }

    func testAllowManagedHooksOnlyKeepsManagedAndForceEnabledPluginHooks() throws {
        try installPlugin(hooksFile: hooks(["PostToolUse": command("${CLAUDE_PLUGIN_ROOT}/fmt.sh", matcher: "Write")]))
        try fixture.json(".claude/settings.json", in: fixture.repository, hooks(["Stop": command("say done")]))
        try writeManaged(hooks(["SessionStart": command("org-check")]).merging(["allowManagedHooksOnly": true]) { $1 })
        var items = hookItems()
        XCTAssertEqual(items.first { $0.scope == .project }?.applicability, .inactive)
        XCTAssertEqual(items.first { $0.scope == .plugin }?.applicability, .inactive, "A plugin the managed file doesn't force-enable is blocked")
        XCTAssertEqual(items.first { $0.scope == .managed }?.applicability, .conditional)

        try writeManaged([
            "allowManagedHooksOnly": true,
            "enabledPlugins": ["kit@tools": true],
            "hooks": ["SessionStart": command("org-check")],
        ])
        items = hookItems()
        XCTAssertEqual(items.first { $0.scope == .plugin }?.applicability, .effective, "Force-enabled plugins are exempt")
    }

    func testPluginHooksFromTheHooksFileAndTheManifest() throws {
        try installPlugin(
            manifestHooks: [["PreCompact": command("save-notes")], "./extra/hooks.json"],
            hooksFile: hooks(["PostToolUse": command("${CLAUDE_PLUGIN_ROOT}/fmt.sh", matcher: "Write")])
        )
        try fixture.json("extra/hooks.json", in: fixture.claude.appendingPathComponent("plugins/cache/tools/kit/1.0.0"), hooks(["Stop": command("bye")]))
        let items = hookItems()
        XCTAssertEqual(Set(items.map(\.name)), ["PostToolUse: Write", "PreCompact", "Stop"])
        XCTAssertTrue(items.allSatisfy { $0.scope == .plugin && $0.origin == "kit@tools" && $0.applicability == .effective })
    }

    func testAPluginHooksFileWithoutTheWrapperIsIgnoredAndADisabledPluginsHooksAreOff() throws {
        try installPlugin(enabled: false, hooksFile: ["PostToolUse": command("fmt.sh")])
        XCTAssertTrue(hookItems().isEmpty, "Claude Code won't load a hooks file without the hooks wrapper")

        try installPlugin(enabled: false, hooksFile: hooks(["PostToolUse": command("fmt.sh")]))
        XCTAssertEqual(hookItems().map(\.applicability), [.inactive])
    }

    func testOtherHandlerTypesAndSecretsAreMasked() throws {
        try fixture.json("settings.json", in: fixture.claude, hooks([
            "Notification": [["hooks": [
                ["type": "http", "url": "https://hooks.example.com/notify?token=sk-ant-api03-SECRETSECRETSECRET"],
                ["type": "mcp_tool", "server": "slack", "tool": "post_message"],
                ["type": "prompt", "prompt": "Summarise the session\nin one line"],
                ["type": "command", "command": "curl -H 'Authorization: Bearer ghp_SECRETSECRETSECRETSECRET' https://example.com"],
            ]]],
        ]))
        let report = fixture.inspect()
        let items = hookItems(report)
        XCTAssertEqual(Set(items.compactMap { $0.metadataValue("Type") }), ["http", "mcp_tool", "prompt", "command"])
        XCTAssertEqual(items.first { $0.metadataValue("Type") == "mcp_tool" }?.summary, "slack / post_message")
        XCTAssertEqual(items.first { $0.metadataValue("Type") == "prompt" }?.summary, "Summarise the session")
        let encoded = String(bytes: try JSONEncoder().encode(report), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains("SECRETSECRET"), "No hook secret reaches the report")
    }

    func testRunningSessionsPickUpSettingsHooksLiveAndPluginHooksOnReload() throws {
        try installPlugin(hooksFile: hooks(["Stop": command("bye")]))
        try fixture.json(".claude/settings.json", in: fixture.repository, hooks(["Stop": command("say done")]))
        let report = fixture.inspect()
        let settingsHook = try XCTUnwrap(hookItems(report).first { $0.scope == .project })
        let pluginHook = try XCTUnwrap(hookItems(report).first { $0.scope == .plugin })
        XCTAssertEqual(ChangeDetector.pickup(.updated, settingsHook, old: report).timing, .live)
        XCTAssertEqual(ChangeDetector.pickup(.updated, pluginHook, old: report).timing, .reloadPlugins)
    }
}
