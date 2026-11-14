@testable import Strata
import StrataCore
import XCTest

@MainActor
final class InspectionModelTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var repository: URL!
    private var suiteName = ""

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("strata-inspect-\(UUID().uuidString)").resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        repository = home.appendingPathComponent("code/demo")
        try write(".claude/skills/deploy/SKILL.md", in: home, "---\ndescription: Personal deploy\n---\n")
        try write(".claude/skills/deploy/SKILL.md", in: repository, "---\ndescription: Repo deploy\n---\n")
        try write(".mcp.json", in: repository, #"{"mcpServers":{"db":{"command":"/usr/bin/true"}}}"#)
        suiteName = "strata.inspect.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, in base: URL, _ contents: String) throws {
        let url = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func makeModel() throws -> AppModel {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return AppModel(store: RepositoryStore(defaults: defaults), environment: ScanEnvironment(homeDirectory: home, managedDirectory: nil))
    }

    func testScanProducesAReportForTheSelectedRepository() async throws {
        let model = try makeModel()
        model.add(repository)
        await model.scanSelectedRepository()

        let report = try XCTUnwrap(model.selectedReport)
        XCTAssertEqual(report.items(of: .skill).count, 2)
        XCTAssertFalse(model.isScanning(try XCTUnwrap(model.selectedRepositoryID)))
    }

    func testCategoriesFilterVisibleItems() async throws {
        let model = try makeModel()
        model.add(repository)
        await model.scanSelectedRepository()

        model.category = .skills
        XCTAssertEqual(Set(model.visibleItems.map(\.kind)), [.skill])
        model.category = .mcp
        XCTAssertEqual(model.visibleItems.map(\.name), ["db"])
        model.category = .issues
        XCTAssertTrue(model.visibleItems.isEmpty)
        model.category = .all
        XCTAssertEqual(model.visibleItems.count, try XCTUnwrap(model.selectedReport).items.count)
    }

    func testRevealSelectsTheItemAndLeavesIssues() async throws {
        let model = try makeModel()
        model.add(repository)
        await model.scanSelectedRepository()
        let winner = try XCTUnwrap(model.selectedReport?.items(of: .skill).first { $0.scope == .user })

        model.category = .issues
        model.isInspectorPresented = false
        model.reveal(winner.id)

        XCTAssertEqual(model.selectedItem, winner)
        XCTAssertEqual(model.category, .all)
        XCTAssertTrue(model.isInspectorPresented)
    }

    func testScanMarksAVanishedRepositoryMissing() async throws {
        let model = try makeModel()
        model.add(repository)
        let id = try XCTUnwrap(model.selectedRepositoryID)
        try FileManager.default.removeItem(at: repository)

        await model.scan(id)

        XCTAssertTrue(model.isMissing(id))
    }

    func testPathFormatterShortensRepositoryAndHomePaths() throws {
        let formatter = PathFormatter(repositoryPath: "/Users/dev/code/demo", homePath: "/Users/dev")
        XCTAssertEqual(formatter.display("/Users/dev/code/demo/.mcp.json"), ".mcp.json")
        XCTAssertEqual(formatter.display("/Users/dev/.claude/settings.json"), "~/.claude/settings.json")
        XCTAssertEqual(formatter.display("/etc/claude-code/CLAUDE.md"), "/etc/claude-code/CLAUDE.md")
        XCTAssertEqual(formatter.display("/Users/dev/code/demo"), ".")
    }

    func testCategoryShortcutsFollowPickerOrder() {
        XCTAssertEqual(Category.allCases.map(\.shortcut.character), ["1", "2", "3", "4", "5", "6", "7", "8"])
    }
}
